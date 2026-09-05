#' Bring a cleaned table to an analysable format, reporting every assumption
#'
#' [clean_table()] makes the fixes that are unambiguously safe: it legalises
#' column names and trims whitespace, and it *reports* near-duplicate labels
#' without merging them. `conform_table()` is the next step, and it handles the
#' two jobs that are judgement calls rather than hygiene: deciding that
#' `"NSW"` and `"Nsw"` are one category, and deciding that a character column
#' holding six labels is a factor.
#'
#' Both are **off by default**. The default `"report"` mode names every change
#' it would make, in plain words, and applies none of them, because a merged
#' category and a coerced type are decisions about what the data *means* and
#' masque does not make those silently. Set a mode to `"auto"` to apply them,
#' and the assumption behind each one is recorded in the returned object.
#'
#' Storage is decided **before** categories, deliberately. A column of numbers
#' or dates held as text is not a set of categories, and proposing to merge
#' `"4.2"` into `"4.4"` because they differ by one character is how an automatic
#' cleaner destroys data. Only columns that remain categorical are considered
#' for merging, and a one-character edit between labels shorter than four
#' characters is ignored, because `"a"` and `"b"` are one edit apart and are
#' plainly different things.
#'
#' What it deliberately does not do: merge two labels that differ by an edit
#' when neither spelling is the more common, coerce a column whose values do not
#' all parse, or touch a numeric column's storage. Each is reported as a
#' `not applied` row with the reason, so the gap is visible rather than silent.
#'
#' @param df A data frame.
#' @param merge_labels One of `"report"` (default), `"auto"` or `"off"`.
#'   Governs near-duplicate category labels, and treats the two kinds
#'   differently. A pair differing **only by capitalisation** is one category
#'   whatever happens, so it is merged onto the more frequent spelling, and on a
#'   tie onto whichever appeared first, which is deterministic and recorded. A
#'   pair differing **by one edit** might be two real categories, so it is
#'   merged only when one spelling is clearly the more common; on a tie it is
#'   refused and reported.
#' @param types One of `"report"` (default), `"auto"` or `"off"`. Governs
#'   storage format: a low-cardinality character column becomes a factor, a
#'   fully numeric character column becomes numeric, and a fully ISO-8601
#'   character column becomes a `Date`.
#' @param max_levels Cardinality at or below which a character column is
#'   treated as categorical. Default `20`.
#' @param clean Passed to [clean_table()], which always runs first. Default
#'   `"auto"`.
#' @param quiet Logical. When `FALSE` (default) a `cli` summary is printed.
#'
#' @return An object of class `masque_conformance`: a list with
#'   \itemize{
#'     \item `data` - the conformed data frame;
#'     \item `cleaning` - the `masque_cleaning` record from [clean_table()];
#'     \item `merges` - one row per near-duplicate pair considered
#'       (`col`, `from`, `to`, `n_from`, `n_to`, `applied`, `reason`);
#'     \item `types` - one row per column whose storage was considered
#'       (`col`, `from`, `to`, `applied`, `reason`);
#'     \item `assumptions` - every decision as a plain sentence
#'       (`col`, `assumption`, `applied`), which is the thing to read;
#'     \item `modes` - the modes applied.
#'   }
#'
#' @examples
#' df <- data.frame(
#'   state = c("NSW", "Nsw", "NSW", "VIC", "VIC"),
#'   yield = c("3.1", "2.9", "5.0", "4.2", "3.8"),
#'   sown  = c("2024-05-01", "2024-05-03", "2024-05-01", "2024-05-08", "2024-05-08"),
#'   stringsAsFactors = FALSE
#' )
#' # report only: nothing is changed
#' cf <- conform_table(df, quiet = TRUE)
#' cf$assumptions
#'
#' # apply the decisions
#' cf2 <- conform_table(df, merge_labels = "auto", types = "auto", quiet = TRUE)
#' str(cf2$data)
#'
#' @seealso [clean_table()] for the safe fixes, [propose_roles()] for what a
#'   column is, [mask()] for the round-trip.
#' @export
conform_table <- function(df,
                          merge_labels = c("report", "auto", "off"),
                          types = c("report", "auto", "off"),
                          max_levels = 20L,
                          clean = c("auto", "report", "off"),
                          quiet = FALSE) {
  if (!is.data.frame(df)) {
    cli::cli_abort("`df` must be a data frame; got {.cls {class(df)[1]}}.")
  }
  merge_labels <- match.arg(merge_labels)
  types <- match.arg(types)
  clean <- match.arg(clean)
  if (!is.numeric(max_levels) || length(max_levels) != 1L || max_levels < 1) {
    cli::cli_abort("`max_levels` must be a single positive number.")
  }

  cl <- clean_table(df, clean = clean, quiet = TRUE)
  out_df <- cl$data

  # Storage is decided FIRST. A column of numbers or dates held as text is not
  # a set of categories, and proposing to merge "4.2" into "4.4" because they
  # differ by one character is how an automatic cleaner destroys data.
  tps <- .conform_types(out_df, types, max_levels)

  cat_cols <- .categorical_cols(out_df, tps, max_levels)
  merges <- .conform_merges(out_df, cl$near_duplicates, merge_labels, cat_cols)
  if (identical(merge_labels, "auto") && nrow(merges)) {
    out_df <- .apply_merges(out_df, merges[merges$applied, , drop = FALSE])
  }
  if (identical(types, "auto") && nrow(tps)) {
    out_df <- .apply_types(out_df, tps[tps$applied, , drop = FALSE])
  }

  out <- list(
    data = out_df,
    cleaning = cl,
    merges = merges,
    types = tps,
    assumptions = .conform_assumptions(merges, tps),
    modes = c(clean = clean, merge_labels = merge_labels, types = types)
  )
  class(out) <- "masque_conformance"

  if (!quiet) .report_conformance(out)
  out
}

#' @export
print.masque_conformance <- function(x, ...) {
  .report_conformance(x)
  invisible(x)
}

# --- which columns hold categories ------------------------------------------

# A column is categorical when it is already a factor, or when the storage pass
# concluded it should become one. Anything parsing as a number or a date is
# not, and neither is a column whose labels are nearly all distinct: that is an
# identifier or free text wearing a character class.
.categorical_cols <- function(df, tps, max_levels) {
  out <- character(0)
  for (nm in names(df)) {
    if (is.factor(df[[nm]])) { out <- c(out, nm); next }
    if (!is.character(df[[nm]])) next
    hit <- tps[tps$col == nm, , drop = FALSE]
    if (nrow(hit) && identical(hit$to[1], "factor")) out <- c(out, nm)
  }
  out
}

# --- merges -----------------------------------------------------------------

.empty_merges <- function() {
  data.frame(
    col = character(), from = character(), to = character(),
    n_from = integer(), n_to = integer(), applied = logical(),
    reason = character(), stringsAsFactors = FALSE
  )
}

# Decide, for each near-duplicate pair clean_table() reported and that sits in a
# genuinely categorical column, which spelling survives. Frequency decides. A
# case-only tie is broken by first appearance (the pair IS one category; only
# the spelling is open); an edit-distance tie is refused, because those may be
# two different things.
MIN_EDIT_NCHAR <- 4L   # below this, a one-character difference means nothing

.conform_merges <- function(df, near_dups, mode, cat_cols) {
  if (identical(mode, "off") || is.null(near_dups) || !nrow(near_dups)) {
    return(.empty_merges())
  }
  near_dups <- near_dups[near_dups$col %in% cat_cols, , drop = FALSE]
  if (!nrow(near_dups)) return(.empty_merges())

  rows <- list()
  for (i in seq_len(nrow(near_dups))) {
    col <- near_dups$col[i]
    a <- near_dups$a[i]
    b <- near_dups$b[i]
    kind <- near_dups$kind[i]
    is_case <- identical(kind, "case")

    # A one-character edit between short labels is not evidence of a typo:
    # "a" and "b" are one edit apart and are plainly different categories.
    if (!is_case && min(nchar(a), nchar(b)) < MIN_EDIT_NCHAR) next

    v <- as.character(df[[col]])
    na_ <- sum(v == a, na.rm = TRUE)
    nb_ <- sum(v == b, na.rm = TRUE)

    if (na_ == nb_ && !is_case) {
      # differing by an edit, with no majority: this may be two real categories
      rows[[length(rows) + 1L]] <- data.frame(
        col = col, from = a, to = b, n_from = na_, n_to = nb_, applied = FALSE,
        reason = paste("the spellings differ by one edit and occur equally",
                       "often; masque will not choose between them"),
        stringsAsFactors = FALSE)
      next
    }

    if (na_ > nb_)      { keep <- a; drop <- b }
    else if (nb_ > na_) { keep <- b; drop <- a }
    else {
      # a case-only tie: the two ARE one category, only the spelling is open.
      # The first spelling to appear wins, which is deterministic and stated.
      first <- v[!is.na(v) & v %in% c(a, b)][1]
      keep <- first; drop <- if (identical(first, a)) b else a
    }

    rows[[length(rows) + 1L]] <- data.frame(
      col = col, from = drop, to = keep,
      n_from = min(na_, nb_), n_to = max(na_, nb_),
      applied = identical(mode, "auto"),
      reason = if (is_case) {
        sprintf("differs from %s by capitalisation only", keep)
      } else {
        sprintf("differs from %s by a single character", keep)
      },
      stringsAsFactors = FALSE)
  }
  if (!length(rows)) return(.empty_merges())
  do.call(rbind, rows)
}

.apply_merges <- function(df, m) {
  if (!nrow(m)) return(df)
  for (i in seq_len(nrow(m))) {
    col <- m$col[i]
    x <- df[[col]]
    if (is.factor(x)) {
      lv <- levels(x)
      lv[lv == m$from[i]] <- m$to[i]
      df[[col]] <- factor(lv[as.integer(x)], levels = unique(lv))
    } else {
      x[!is.na(x) & x == m$from[i]] <- m$to[i]
      df[[col]] <- x
    }
  }
  df
}

# --- types ------------------------------------------------------------------

.empty_types <- function() {
  data.frame(
    col = character(), from = character(), to = character(),
    applied = logical(), reason = character(), stringsAsFactors = FALSE
  )
}

# Storage decisions, one per character column. Only a column whose values ALL
# parse is proposed for conversion; a single unparseable value blocks it and
# says so, because a coercion that quietly produces NA loses data.
.conform_types <- function(df, mode, max_levels) {
  if (identical(mode, "off")) return(.empty_types())
  rows <- list()
  for (nm in names(df)) {
    x <- df[[nm]]
    if (!is.character(x)) next
    ok <- x[!is.na(x) & nzchar(x)]
    if (!length(ok)) next
    n_u <- length(unique(ok))

    num <- suppressWarnings(as.numeric(ok))
    if (!anyNA(num)) {
      rows[[length(rows) + 1L]] <- data.frame(
        col = nm, from = "character", to = "numeric",
        applied = identical(mode, "auto"),
        reason = "every value parses as a number", stringsAsFactors = FALSE
      )
      next
    }

    dt <- suppressWarnings(as.Date(ok, format = "%Y-%m-%d"))
    if (!anyNA(dt)) {
      rows[[length(rows) + 1L]] <- data.frame(
        col = nm, from = "character", to = "Date",
        applied = identical(mode, "auto"),
        reason = "every value parses as an ISO-8601 date", stringsAsFactors = FALSE
      )
      next
    }

    if (n_u <= max_levels && n_u < length(ok)) {
      rows[[length(rows) + 1L]] <- data.frame(
        col = nm, from = "character", to = "factor",
        applied = identical(mode, "auto"),
        reason = sprintf("%d distinct labels over %d values", n_u, length(ok)),
        stringsAsFactors = FALSE
      )
      next
    }

    rows[[length(rows) + 1L]] <- data.frame(
      col = nm, from = "character", to = "character", applied = FALSE,
      reason = sprintf("%d distinct labels is above max_levels = %d; left as text",
                       n_u, as.integer(max_levels)),
      stringsAsFactors = FALSE
    )
  }
  if (!length(rows)) return(.empty_types())
  do.call(rbind, rows)
}

.apply_types <- function(df, t) {
  if (!nrow(t)) return(df)
  for (i in seq_len(nrow(t))) {
    col <- t$col[i]
    df[[col]] <- switch(
      t$to[i],
      numeric = suppressWarnings(as.numeric(df[[col]])),
      Date = suppressWarnings(as.Date(df[[col]], format = "%Y-%m-%d")),
      factor = factor(df[[col]]),
      df[[col]]
    )
  }
  df
}

# --- the assumption report --------------------------------------------------

# The thing a reader should actually look at: every decision as a sentence,
# whether or not it was applied.
.conform_assumptions <- function(merges, tps) {
  rows <- list()
  if (nrow(merges)) {
    for (i in seq_len(nrow(merges))) {
      rows[[length(rows) + 1L]] <- data.frame(
        col = merges$col[i],
        assumption = sprintf(
          '"%s" and "%s" are the same category, recorded as "%s" (%s)',
          merges$from[i], merges$to[i], merges$to[i], merges$reason[i]
        ),
        applied = merges$applied[i], stringsAsFactors = FALSE
      )
    }
  }
  if (nrow(tps)) {
    for (i in seq_len(nrow(tps))) {
      txt <- if (identical(tps$from[i], tps$to[i])) {
        sprintf("left as %s: %s", tps$from[i], tps$reason[i])
      } else {
        sprintf("stored as %s rather than %s, because %s",
                tps$to[i], tps$from[i], tps$reason[i])
      }
      rows[[length(rows) + 1L]] <- data.frame(
        col = tps$col[i], assumption = txt, applied = tps$applied[i],
        stringsAsFactors = FALSE
      )
    }
  }
  if (!length(rows)) {
    return(data.frame(col = character(), assumption = character(),
                      applied = logical(), stringsAsFactors = FALSE))
  }
  do.call(rbind, rows)
}

.report_conformance <- function(x) {
  a <- x$assumptions
  if (!nrow(a)) {
    cli::cli_alert_success("No category or storage decisions to make.")
    return(invisible(NULL))
  }
  done <- a[a$applied, , drop = FALSE]
  held <- a[!a$applied, , drop = FALSE]
  if (nrow(done)) {
    cli::cli_alert_info("Applied {nrow(done)} decision{?s}:")
    cli::cli_ul(sprintf("%s: %s", done$col, done$assumption))
  }
  if (nrow(held)) {
    cli::cli_alert_warning("Reported, NOT applied ({nrow(held)}):")
    cli::cli_ul(sprintf("%s: %s", held$col, held$assumption))
    if (identical(unname(x$modes["merge_labels"]), "report") ||
        identical(unname(x$modes["types"]), "report")) {
      cli::cli_text(
        "Re-run with {.code merge_labels = \"auto\"} / {.code types = \"auto\"} to apply."
      )
    }
  }
  invisible(NULL)
}
