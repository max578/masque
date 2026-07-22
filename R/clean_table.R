#' Tidy a dirty table's column names and category labels before masking
#'
#' Real custodian tables arrive with column names that are not valid R
#' names (`"Yield (t/ha)"`, `"Site Name"`), leading or trailing
#' whitespace in names and factor / character values, and the
#' occasional near-duplicate label (`"north"` vs `"North"` vs
#' `" north"`). `clean_table()` makes the safe fixes - legalising names
#' and trimming whitespace - loudly, and *reports* the unsafe ones
#' (near-duplicate labels) without touching them, because merging two
#' labels that only look alike is a judgement call masque must not make
#' silently.
#'
#' The corrections are returned alongside the cleaned data so [mask()]
#' can record them in the recipe and [apply_recipe()] can re-apply the
#' identical cleaning to a fresh copy of the original. Cleaning is
#' therefore part of the round-trip contract, not a destructive
#' pre-step.
#'
#' @param df A data frame.
#' @param clean One of `"auto"` (default - legalise names, trim
#'   whitespace, report near-duplicates), `"report"` (legalise names,
#'   report what whitespace / near-duplicate changes *would* be made but
#'   apply none), or `"off"` (legalise names only, skip all other
#'   hygiene). Column-name legalisation is applied in **every** mode -- an
#'   invalid name silently rewritten downstream corrupts the clone -- and
#'   is surfaced as a `masque_name_repaired` warning; only the whitespace
#'   and near-duplicate handling is governed by the mode.
#' @param quiet Logical. When `FALSE` (default) a `cli` summary of the
#'   fixes and advisories is printed. Set `TRUE` to suppress it (the
#'   report object is returned either way).
#'
#' @return An object of class `masque_cleaning`: a list with
#'   \itemize{
#'     \item `data` - the cleaned (or, under `report` / `off`,
#'       unchanged) data frame;
#'     \item `name_map` - named character `original -> clean` for every
#'       column whose name changed (empty if none);
#'     \item `level_fixes` - named list, one entry per column whose
#'       values were trimmed, each a named character `original -> clean`;
#'     \item `near_duplicates` - a data frame of report-only label pairs
#'       (`col`, `a`, `b`, `kind`) that look like typos but were left
#'       untouched;
#'     \item `mode` - the `clean` mode applied.
#'   }
#'
#' @examples
#' df <- data.frame(
#'   `Site Name` = c("north ", "north", "South"),
#'   `Yield (t/ha)` = c(3.1, 2.9, 5.0),
#'   check.names = FALSE
#' )
#' cl <- clean_table(df, quiet = TRUE)
#' names(cl$data)
#' cl$near_duplicates
#'
#' @seealso [mask()], [propose_roles()].
#' @export
clean_table <- function(df, clean = c("auto", "report", "off"), quiet = FALSE) {
  if (!is.data.frame(df)) {
    cli::cli_abort("`df` must be a data frame; got {.cls {class(df)[1]}}.")
  }
  clean <- match.arg(clean)

  # Column-name legalisation is applied in EVERY mode. An invalid column
  # name silently rewritten during synthesis (via make.names() inside a
  # downstream data.frame build) corrupts the clone and breaks the
  # round-trip, so legalising it is a correctness fix, not optional
  # hygiene. The `clean` mode governs only the whitespace and
  # near-duplicate handling below.
  orig_names <- names(df)
  legal <- .legalise_names(orig_names)
  name_map <- stats::setNames(legal, orig_names)
  name_map <- name_map[orig_names != legal]
  if (length(name_map)) {
    names(df) <- legal
    warning(warningCondition(
      .name_repair_message(name_map),
      class = "masque_name_repaired"
    ))
  }

  apply_fixes <- identical(clean, "auto")
  do_hygiene <- !identical(clean, "off")

  # Trim whitespace (auto only) and detect near-duplicate labels (auto and
  # report). Keyed on the now-legalised column names.
  level_fixes <- list()
  near_dups <- list()
  if (do_hygiene) {
    for (j in seq_along(df)) {
      x <- df[[j]]
      if (!(is.character(x) || is.factor(x))) next
      nm_out <- names(df)[j]
      fix <- .trim_levels(x)
      if (length(fix$map)) {
        level_fixes[[nm_out]] <- fix$map
        if (apply_fixes) df[[j]] <- fix$x
      }
      # Near-duplicate detection runs on the (trimmed) vocabulary.
      vals <- if (apply_fixes) fix$x else x
      nd <- .near_duplicate_pairs(vals)
      if (nrow(nd)) {
        nd$col <- nm_out
        near_dups[[length(near_dups) + 1L]] <- nd
      }
    }
  }

  near_duplicates <- if (length(near_dups)) {
    out <- do.call(rbind, near_dups)
    out[, c("col", "a", "b", "kind")]
  } else {
    .empty_near_dups()
  }

  out <- list(
    data            = df,
    name_map        = name_map,
    level_fixes     = level_fixes,
    near_duplicates = near_duplicates,
    mode            = clean
  )
  class(out) <- "masque_cleaning"

  if (!quiet) .report_cleaning(out)
  out
}

#' @export
print.masque_cleaning <- function(x, ...) {
  .report_cleaning(x)
  invisible(x)
}

.empty_near_dups <- function() {
  data.frame(
    col = character(), a = character(), b = character(),
    kind = character(), stringsAsFactors = FALSE
  )
}

# Trim, make.names, then uniquify. make.names handles the illegal-name
# and reserved-word cases; make.unique resolves collisions the trimming
# or legalisation introduced.
.legalise_names <- function(nms) {
  trimmed <- trimws(nms)
  legal <- make.names(trimmed)
  make.unique(legal, sep = "_")
}

# Human-readable summary of a column-name legalisation, shared by the
# clean_table() warning and mask()'s recipe record so the two never drift.
.name_repair_message <- function(name_map) {
  pairs <- paste(
    sprintf("`%s` -> `%s`", names(name_map), unname(name_map)),
    collapse = ", "
  )
  sprintf(
    paste0(
      "Renamed %d column name(s) that are not valid R names: %s. ",
      "The map is recorded in the recipe and reversed on the round-trip."
    ),
    length(name_map), pairs
  )
}

# Trim leading / trailing whitespace from a character or factor vector.
# Returns the cleaned vector and a map of only the values that changed.
.trim_levels <- function(x) {
  if (is.factor(x)) {
    lv <- levels(x)
    lv_trim <- trimws(lv)
    changed <- lv != lv_trim
    if (!any(changed)) {
      return(list(x = x, map = stats::setNames(character(), character())))
    }
    # Trimming may collapse levels (" a" and "a"); rebuild the factor on
    # the trimmed vocabulary.
    new_lv <- unique(lv_trim)
    x_new <- factor(lv_trim[match(as.character(x), lv)], levels = new_lv)
    map <- stats::setNames(lv_trim[changed], lv[changed])
    list(x = x_new, map = map)
  } else {
    x_trim <- trimws(x)
    changed <- !is.na(x) & x != x_trim
    if (!any(changed)) {
      return(list(x = x, map = stats::setNames(character(), character())))
    }
    map <- stats::setNames(
      x_trim[changed], x[changed]
    )
    map <- map[!duplicated(names(map))]
    list(x = x_trim, map = map)
  }
}

# Report-only near-duplicate detection: pairs of distinct labels that
# differ by case only, or by a single edit (insertion / deletion /
# substitution). Uses base utils::adist - no dependency.
.near_duplicate_pairs <- function(x) {
  vals <- sort(unique(stats::na.omit(as.character(x))))
  if (length(vals) < 2L) {
    return(.empty_near_dups())
  }
  pairs <- list()
  lower <- tolower(vals)
  d <- utils::adist(vals)
  for (i in seq_along(vals)) {
    for (k in seq_len(i - 1L)) {
      kind <- if (lower[i] == lower[k]) {
        "case"
      } else if (d[i, k] == 1L) {
        "edit1"
      } else {
        next
      }
      pairs[[length(pairs) + 1L]] <- data.frame(
        a = vals[k], b = vals[i], kind = kind,
        stringsAsFactors = FALSE
      )
    }
  }
  if (!length(pairs)) {
    return(.empty_near_dups())
  }
  out <- do.call(rbind, pairs)
  out$col <- NA_character_
  out
}

# Distil a masque_cleaning object to the reversible record stored on the
# recipe (the data frame itself is not kept).
.cleaning_record <- function(cl) {
  list(
    name_map        = cl$name_map,
    level_fixes     = cl$level_fixes,
    near_duplicates = cl$near_duplicates,
    mode            = cl$mode
  )
}

# Re-apply a recipe's cleaning record to a fresh copy of the original so
# a pipeline written against the (cleaned) synthetic can run against the
# original. Idempotent: cleaning an already-clean frame is a no-op.
.apply_cleaning_forward <- function(df, cleaning) {
  if (is.null(cleaning)) {
    return(df)
  }
  name_map <- cleaning$name_map
  level_fixes <- cleaning$level_fixes

  # Trim levels first (keyed on the post-rename column names), but the
  # incoming `original` still carries the dirty names, so trim by mapping
  # through name_map where present.
  for (clean_nm in names(level_fixes)) {
    orig_nm <- names(name_map)[match(clean_nm, unname(name_map))]
    src_nm <- if (!is.na(orig_nm) && length(orig_nm)) orig_nm else clean_nm
    if (!(src_nm %in% names(df))) next
    df[[src_nm]] <- trimws_keep_class(df[[src_nm]])
  }

  if (length(name_map)) {
    nm <- names(df)
    hits <- match(names(name_map), nm)
    ok <- !is.na(hits)
    nm[hits[ok]] <- unname(name_map)[ok]
    names(df) <- nm
  }
  df
}

# Trim a character / factor vector, preserving its class; pass anything
# else through.
trimws_keep_class <- function(x) {
  if (is.factor(x)) {
    return(.trim_levels(x)$x)
  }
  if (is.character(x)) {
    return(trimws(x))
  }
  x
}

# Remap a roles table's `col` column through a name map (original ->
# clean). Preserves all attributes (mode, proposed_actions, design).
.remap_roles_cols <- function(roles, name_map) {
  if (!length(name_map) || !("col" %in% names(roles))) {
    return(roles)
  }
  hits <- match(roles$col, names(name_map))
  ok <- !is.na(hits)
  roles$col[ok] <- unname(name_map)[hits[ok]]

  pa <- attr(roles, "proposed_actions")
  if (!is.null(pa) && length(pa)) {
    nm <- names(pa)
    h <- match(nm, names(name_map))
    o <- !is.na(h)
    nm[o] <- unname(name_map)[h[o]]
    names(pa) <- nm
    attr(roles, "proposed_actions") <- pa
  }
  roles
}

.report_cleaning <- function(cl) {
  n_names <- length(cl$name_map)
  n_levels <- length(cl$level_fixes)
  n_dups <- nrow(cl$near_duplicates)

  if (n_names == 0L && n_levels == 0L && n_dups == 0L) {
    cli::cli_alert_success("Table is clean: no name or label fixes needed.")
    return(invisible(cl))
  }

  verb <- if (identical(cl$mode, "report")) "would fix" else "fixed"
  cli::cli_h2("masque hygiene report")

  if (n_names) {
    # Names are legalised in every mode, so they are always already fixed.
    cli::cli_alert_info("Column names legalised ({n_names}):")
    for (i in seq_len(n_names)) {
      cli::cli_li("{.val {names(cl$name_map)[i]}} -> {.val {cl$name_map[[i]]}}")
    }
  }
  if (n_levels) {
    total <- sum(vapply(cl$level_fixes, length, integer(1L)))
    cli::cli_alert_info(
      "Whitespace {verb} in {n_levels} column(s) ({total} label(s))."
    )
  }
  if (n_dups) {
    cli::cli_alert_warning(
      "{n_dups} near-duplicate label pair(s) found - NOT changed:"
    )
    for (i in seq_len(n_dups)) {
      row <- cl$near_duplicates[i, ]
      cli::cli_li(
        "{.field {row$col}}: {.val {row$a}} ~ {.val {row$b}} ({row$kind})"
      )
    }
    cli::cli_text(
      "Resolve these by hand if they are typos; masque will not merge them."
    )
  }
  invisible(cl)
}
