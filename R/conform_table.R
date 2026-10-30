#' Bring a cleaned table to an analysable format, reporting every assumption
#'
#' [clean_table()] makes the fixes that are unambiguously safe: it legalises
#' column names and trims whitespace, and it *reports* near-duplicate labels
#' without merging them. `conform_table()` is the next step and makes the two
#' decisions that need judgement: deciding that
#' `"NSW"` and `"Nsw"` are one category, and deciding that a character column
#' holding six labels is a factor.
#'
#' Both are **off by default**: the default `"report"` mode lists every change
#' it would make, in plain words, and applies none. Set a mode to `"auto"` to
#' apply them; the assumption behind each one is recorded in the returned
#' object.
#'
#' Storage is decided **before** categories, so a column of numbers or dates
#' held as text is typed first and `"4.2"` is never merged into `"4.4"`. Only
#' columns that remain categorical are considered for merging, and a
#' one-character edit between labels shorter than four characters is ignored
#' (`"a"` and `"b"` are one edit apart).
#'
#' Two labels that differ by an edit are merged only when one spelling is
#' clearly more common; a column is converted only when every value parses;
#' numeric columns keep their storage. Anything not changed for these reasons
#' is reported as a `not applied` row with the reason.
#'
#' Merges follow chains: if `"Nsw"` merges onto `"nsw"` and `"nsw"` onto
#' `"NSW"`, both end on `"NSW"`. A label whose merges end on two different
#' labels (`"colur"` beside `"color"` and `"colour"` that occur equally
#' often) is not merged; it is reported, and a `masque_conform_ambiguous_merge`
#' warning is raised under `merge_labels = "auto"`. Codes that differ only
#' inside a run of digits (`"G01"` and `"G02"`) are never treated as
#' near-duplicates. Which columns hold categories is decided the same way
#' whatever `types` is, so `types = "off"` still merges labels and leaves
#' storage as it is.
#'
#' Pass the result to [mask()] (or as a table of [mask_set()]): the recipe
#' records the merges and type changes, and [apply_recipe()] replays them on
#' the original so a pipeline built on the conformed clone sees the same
#' labels and storage.
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
#'     \item `data` - the conformed data.table;
#'     \item `cleaning` - the `masque_cleaning` record from [clean_table()];
#'     \item `merges` - one row per near-duplicate pair considered
#'       (`col`, `from`, `to`, `n_from`, `n_to`, `applied`, `reason`);
#'     \item `merge_map` - the merges as applied to the data (`col`, `from`,
#'       `to`), one row per merged-away label, each `to` a label left in
#'       the column. This is what [mask()] records and [apply_recipe()]
#'       replays;
#'     \item `types` - one row per column whose storage was considered
#'       (`col`, `from`, `to`, `applied`, `reason`);
#'     \item `assumptions` - every decision as a plain sentence
#'       (`col`, `assumption`, `applied`), which is the thing to read;
#'     \item `modes` - the modes applied;
#'     \item `max_levels` - the cardinality threshold used.
#'   }
#'
#' @examples
#' df <- data.frame(
#'   state = c("NSW", "Nsw", "NSW", "VIC", "VIC"),
#'   yield = c("3.1", "2.9", "5.0", "4.2", "3.8"),
#'   sown  = c("2024-05-01", "2024-05-03", "2024-05-01", "2024-05-08",
#'             "2024-05-08"),
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

  # Storage first: numbers or dates held as text are not categories, and
  # merging "4.2" into "4.4" would destroy data. Which columns are categories
  # is read from a report-only storage pass, so it holds under types = "off".
  tps <- .conform_types(out_df, types, max_levels)
  cat_cols <- .categorical_cols(
    out_df, .conform_types(out_df, "report", max_levels), max_levels
  )

  merges <- .conform_merges(out_df, cl$near_duplicates, merge_labels, cat_cols)
  resolved <- .resolve_merges(merges)
  merges <- resolved$merges
  if (identical(merge_labels, "auto")) {
    .warn_ambiguous_merges(resolved$ambiguous)
    out_df <- .apply_merge_map(out_df, resolved$map)
  }
  if (identical(types, "auto") && nrow(tps)) {
    out_df <- .apply_types(out_df, tps[tps$applied, , drop = FALSE])
  }

  out <- list(
    data = .as_owned_dt(out_df),
    cleaning = cl,
    merges = data.table::as.data.table(merges),
    merge_map = data.table::as.data.table(resolved$map),
    types = data.table::as.data.table(tps),
    assumptions = .conform_assumptions(merges, tps),
    modes = c(clean = clean, merge_labels = merge_labels, types = types),
    max_levels = max_levels
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

# Categorical: a factor, or text the storage pass would make one. Numbers,
# dates and columns of nearly all distinct labels (ids, free text) are not.
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

.empty_merge_map <- function() {
  data.frame(
    col = character(), from = character(), to = character(),
    stringsAsFactors = FALSE
  )
}

utils::globalVariables(c(
  ".N", "a", "a_wins", "b", "candidate", "col", "first_a", "first_b",
  "from",
  "i.first", "i.from", "i.n", "i.to", "kind", "label", "n_a", "n_b", "n_to",
  "pos", "reason", "to", "x.to"
))

# For each near-duplicate pair in a categorical column the commoner spelling
# wins. A case-only tie goes to the first seen; an edit-distance tie is refused.
MIN_EDIT_NCHAR <- 4L   # below this, a one-character difference means nothing

.conform_merges <- function(df, near_dups, mode, cat_cols) {
  # data.table syntax in this frame only (data.table >= 1.15.0).
  .datatable.aware <- TRUE
  if (identical(mode, "off") || is.null(near_dups) || !nrow(near_dups)) {
    return(.empty_merges())
  }
  nd <- data.table::as.data.table(near_dups)[col %in% cat_cols]
  # A one-character edit between short labels is not evidence of a typo:
  # "a" and "b" are one edit apart and are plainly different categories.
  nd <- nd[kind == "case" | pmin(nchar(a), nchar(b)) >= MIN_EDIT_NCHAR]
  if (!nrow(nd)) {
    return(.empty_merges())
  }

  # Count and first position of every label in the columns concerned.
  labels <- data.table::rbindlist(lapply(unique(nd$col), function(cc) {
    x <- as.character(df[[cc]])
    data.table::data.table(col = cc, label = x, pos = seq_along(x))
  }))
  counts <- labels[!is.na(label), list(n = .N, first = min(pos)),
    by = c("col", "label")
  ]
  nd[counts, `:=`(n_a = i.n, first_a = i.first), on = c("col", a = "label")]
  nd[counts, `:=`(n_b = i.n, first_b = i.first), on = c("col", b = "label")]

  # The commoner spelling wins; a case-only tie goes to the first seen.
  nd[, candidate := kind == "case" | n_a != n_b]
  nd[, a_wins := n_a > n_b | (n_a == n_b & kind == "case" & first_a < first_b)]
  nd[, `:=`(
    from = data.table::fifelse(a_wins, b, a),
    to = data.table::fifelse(a_wins, a, b)
  )]
  nd[, reason := data.table::fifelse(
    kind == "case",
    sprintf("differs from %s by capitalisation only", to),
    sprintf("differs from %s by a single character", to)
  )]
  nd[candidate == FALSE, reason := paste(
    "the spellings differ by one edit and occur equally",
    "often; masque will not choose between them"
  )]
  out <- nd[, list(
    col, from, to,
    n_from = pmin(n_a, n_b), n_to = pmax(n_a, n_b),
    applied = candidate & identical(mode, "auto"),
    reason, candidate
  )]
  as.data.frame(out)
}

# The effective merge map: each source follows its merges until it reaches a
# label nothing is merged away from. A source that reaches two such labels has
# no single target, so none of its merges is applied.
.resolve_merges <- function(merges) {
  .datatable.aware <- TRUE
  none <- list(
    merges = merges[, setdiff(names(merges), "candidate"), drop = FALSE],
    map = .empty_merge_map(),
    ambiguous = data.frame(
      col = character(), from = character(), to = character(),
      stringsAsFactors = FALSE
    )
  )
  if (!nrow(merges) || !any(merges$candidate)) {
    return(none)
  }

  edges <- unique(data.table::as.data.table(merges)[
    candidate == TRUE, list(col, from, to)
  ])
  paths <- data.table::copy(edges)
  # Each pass moves every path one merge further; the merge graph has no
  # cycles (a merge never goes to a rarer label), so nrow(edges) passes bound it.
  for (i1 in seq_len(nrow(edges))) {
    step <- edges[paths, list(col, from = i.from, to = x.to),
      on = c("col", from = "to"), nomatch = NULL
    ]
    if (!nrow(step)) break
    paths <- unique(data.table::rbindlist(list(
      paths[!edges, on = c("col", to = "from")], step
    )))
  }
  sinks <- paths[, list(
    n_to = data.table::uniqueN(to),
    to = paste(sort(unique(to)), collapse = '", "')
  ), by = c("col", "from")]

  ambiguous <- sinks[n_to > 1L, list(col, from, to)]
  map <- sinks[n_to == 1L, list(col, from, to)]

  report <- data.table::as.data.table(merges)
  if (nrow(ambiguous)) {
    report[ambiguous, `:=`(
      applied = FALSE,
      reason = sprintf(
        paste0(
          "could be merged into more than one label (\"%s\"); masque will ",
          "not choose between them"
        ),
        i.to
      )
    ), on = c("col", "from")]
  }
  report[, candidate := NULL]
  list(
    merges = as.data.frame(report),
    map = as.data.frame(map),
    ambiguous = as.data.frame(ambiguous)
  )
}

.warn_ambiguous_merges <- function(ambiguous) {
  if (!nrow(ambiguous)) {
    return(invisible())
  }
  lines <- sprintf(
    "%s: \"%s\" -> \"%s\"", ambiguous$col, ambiguous$from, ambiguous$to
  )
  # Labels are data: cli inserts them by reference, never parses them.
  bullets <- stats::setNames(
    sprintf("{lines[%d]}", seq_along(lines)), rep("*", length(lines))
  )
  cli::cli_warn(c(
    paste0(
      "{cli::qty(length(lines))}Not merged: {length(lines)} label{?s} with ",
      "more than one candidate target."
    ),
    bullets,
    i = "Merge these by hand if one target is right."
  ), class = "masque_conform_ambiguous_merge")
}

# Apply an effective merge map (`col`, `from`, `to`) to a table.
.apply_merge_map <- function(df, map) {
  if (is.null(map) || !nrow(map)) {
    return(df)
  }
  for (cc in intersect(unique(map$col), names(df))) {
    m <- map[map$col == cc, , drop = FALSE]
    x <- df[[cc]]
    if (is.factor(x)) {
      lv <- levels(x)
      hit <- match(lv, m$from)
      lv[!is.na(hit)] <- m$to[hit[!is.na(hit)]]
      df[[cc]] <- factor(lv[as.integer(x)], levels = unique(lv))
    } else {
      hit <- match(x, m$from)
      x[!is.na(hit)] <- m$to[hit[!is.na(hit)]]
      df[[cc]] <- x
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

# One storage decision per character column. A column converts only if every
# value parses; a single failure blocks it and is reported.
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
        reason = "every value parses as an ISO-8601 date",
        stringsAsFactors = FALSE
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

    # Left as text: the reason names the first of the three cases that holds.
    n_bad <- sum(is.na(num))
    reason <- if (n_bad < length(ok) - n_bad) {
      sprintf(
        paste0(
          "%d of %d values do not parse as a number (first: \"%s\"); ",
          "left as text"
        ),
        n_bad, length(ok), ok[is.na(num)][1L]
      )
    } else if (n_u == length(ok)) {
      sprintf("all %d labels are distinct; left as text", n_u)
    } else {
      sprintf(
        "%d distinct labels is above max_levels = %d; left as text",
        n_u, as.integer(max_levels)
      )
    }
    rows[[length(rows) + 1L]] <- data.frame(
      col = nm, from = "character", to = "character", applied = FALSE,
      reason = reason, stringsAsFactors = FALSE
    )
  }
  if (!length(rows)) return(.empty_types())
  do.call(rbind, rows)
}

.apply_types <- function(df, t) {
  if (is.null(t) || !nrow(t)) return(df)
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

# --- the recipe record -----------------------------------------------------

# What mask() stores from a conformance object: the effective merge map, the
# applied type changes, the modes and max_levels, as plain data frames.
.conform_record <- function(cf) {
  types <- as.data.frame(cf$types)
  types <- types[types$applied, c("col", "from", "to"), drop = FALSE]
  rownames(types) <- NULL
  map <- as.data.frame(cf$merge_map %||% .empty_merge_map())
  rownames(map) <- NULL
  list(
    merges = map[, c("col", "from", "to"), drop = FALSE],
    types = types,
    modes = as.list(cf$modes),
    max_levels = as.integer(cf$max_levels %||% NA_integer_)
  )
}

# Replay a recipe's conform record on a cleaned original: merges, then types,
# in the order conform_table() applied them.
.apply_conform_forward <- function(df, conform) {
  if (is.null(conform)) {
    return(df)
  }
  merges <- conform$merges
  types <- conform$types
  if (!is.null(types)) {
    types <- types[types$col %in% names(df), , drop = FALSE]
  }
  df <- .apply_merge_map(df, merges)
  .apply_types(df, types)
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
        sprintf("stored as %s (was %s): %s",
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
        paste0(
          "Re-run with {.code merge_labels = \"auto\"} / ",
          "{.code types = \"auto\"} to apply."
        )
      )
    }
  }
  invisible(NULL)
}
