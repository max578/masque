#' Propose role classifications for the columns of a data frame
#'
#' Generates a heuristic role tibble for every column of `df`. The user is
#' expected to inspect this tibble and edit it before passing it to `mask()`.
#' Heuristics are seeds, not law.
#'
#' Roles are exactly one of:
#'
#' \describe{
#'   \item{`design`}{Byte-identical pass-through. Trial / site / replicate /
#'     block / plot / row / column / year etc.}
#'   \item{`treatment`}{Same factor cardinality and per-level frequency;
#'     optional label aliasing or seeded permutation.}
#'   \item{`outcome`}{Re-simulated via Gaussian copula. Multiple allowed.}
#'   \item{`covariate`}{Numeric: Gaussian copula (joint with outcomes).
#'     Categorical: row-permuted, levels preserved (local) or aliased
#'     (collaborate).}
#'   \item{`ignore`}{Dropped or passed through depending on `mask()` options;
#'     auto-assigned for date/time, free text, and PII-pattern names.}
#' }
#'
#' Default classification rules, applied in order:
#'
#' 1. PII-pattern column names (`contact`, `email`, `phone`, `gps`,
#'    `latitude`/`longitude`, `postcode`, `ssn`, `password`, `owner`,
#'    `farmer`, `operator`, etc., case-insensitive substring) -> `ignore`
#'    with `pii_suspected = TRUE`.
#' 2. Date / POSIXct / POSIXlt / difftime columns -> `ignore`.
#' 3. ID-pattern names (`\\bid\\b`, `_id$`, `^id_`) -> `ignore`.
#' 4. Design-pattern names (`rep`, `block`, `row`, `col(umn)?`, `range`,
#'    `plot(no)?`, `site`, `env(ironment)?`, `trial`, `year`, `season`,
#'    `colrep`, `tos`) -> `design`.
#' 5. Treatment-pattern names (`treatment`, `variety`, `cultivar`,
#'    `genotype`, `^trt`, `^dose`) -> `treatment`.
#' 6. Character columns with > 50% unique values on non-NA -> `ignore`
#'    (likely free text).
#' 7. Everything else -> `covariate`. The user re-classifies one or more
#'    columns as `outcome`.
#'
#' Failing to designate at least one `outcome` is a hard error at `mask()`
#' time (via [roles_validate()]).
#'
#' Since masque 0.3.0, [propose_roles()] also calls [detect_design()] by
#' default (`detect = TRUE`) and applies the detected design's
#' `recommended_roles` on top of the name-based heuristic. This promotes
#' structurally-identified block / treatment columns even when the
#' column names do not match the design / treatment regexes. The
#' resulting design summary is stashed as `attr(roles, "design")` so the
#' user can [plot()] it or inspect alternates. Pass `detect = FALSE` to
#' recover the v0.2.x name-only behaviour byte-for-byte.
#'
#' @param df A data frame. Must have at least one column.
#' @param detect Logical scalar (default `TRUE`). When `TRUE`, run
#'   [detect_design()] and overlay its recommended role hints on the
#'   name-based heuristic. Stash the `design_summary` as `attr(roles,
#'   "design")`. When `FALSE`, only the v0.2.x name-based heuristic
#'   runs.
#'
#' @return A tibble with one row per column, containing:
#'   \itemize{
#'     \item `col`: column name.
#'     \item `role`: one of `design`, `treatment`, `outcome`, `covariate`,
#'       `ignore`.
#'     \item `kind`: storage kind (`numeric`, `integer`, `factor`,
#'       `character`, `logical`, `date`, `datetime`, `other`).
#'     \item `freq_or_range`: brief summary string (range for numeric,
#'       level count for factor, etc.).
#'     \item `pii_suspected`: `TRUE` if column name matches a PII pattern.
#'     \item `notes`: short explanation of the auto-classification.
#'   }
#'
#' @examples
#' propose_roles(iris)
#'
#' @seealso [roles_validate()] for the fail-closed validation applied at
#'   `mask()` time.
#'
#' @export
propose_roles <- function(df, detect = TRUE) {
  if (!is.data.frame(df)) {
    cli::cli_abort("`df` must be a data frame; got {.cls {class(df)[1]}}.")
  }
  if (ncol(df) == 0L) {
    cli::cli_abort("`df` has no columns.")
  }

  rows <- lapply(names(df), function(nm) classify_one_column(nm, df[[nm]]))
  roles <- tibble::as_tibble(do.call(
    rbind.data.frame,
    c(rows, list(stringsAsFactors = FALSE))
  ))

  if (!isTRUE(detect)) {
    return(roles)
  }

  # Structural overlay: detect_design() consumes the name-based proposal.
  # Need at least 2 rows for detection to be meaningful.
  if (nrow(df) < 2L) {
    return(roles)
  }

  ds <- detect_design(df, roles = roles)
  if (ds@class_label != "none" && nrow(ds@recommended_roles) > 0L) {
    roles <- .overlay_recommended_roles(roles, ds@recommended_roles)
  }
  attr(roles, "design") <- ds
  roles
}

# Apply detect_design()'s recommended_roles on top of the name-based
# tibble. Override role + extend the notes string. Never introduces or
# drops rows.
.overlay_recommended_roles <- function(roles, rec) {
  for (i in seq_len(nrow(rec))) {
    col_i <- rec$col[i]
    role_i <- rec$role[i]
    row_idx <- which(roles$col == col_i)
    if (length(row_idx) != 1L) next
    if (identical(roles$role[row_idx], role_i)) next
    old_role <- roles$role[row_idx]
    roles$role[row_idx] <- role_i
    roles$notes[row_idx] <- sprintf(
      "detect_design: %s -> %s (was: %s)",
      old_role, role_i, roles$notes[row_idx]
    )
  }
  roles
}

# Internal: classify a single column and return a single-row data.frame.
classify_one_column <- function(nm, x) {
  kind <- col_kind(x)
  is_pii <- matches_pattern(nm, PII_PATTERN)

  if (is_pii) {
    role <- "ignore"
    notes <- "PII pattern in column name -> ignore (flagged)."
  } else if (kind %in% c("date", "datetime")) {
    role <- "ignore"
    notes <- "Date/time column -> ignore by default."
  } else if (matches_pattern(nm, ID_PATTERN)) {
    role <- "ignore"
    notes <- "ID-pattern name -> ignore."
  } else if (matches_pattern(nm, DESIGN_PATTERN)) {
    role <- "design"
    notes <- "Design-pattern name -> design (byte-identical)."
  } else if (matches_pattern(nm, TREATMENT_PATTERN)) {
    role <- "treatment"
    notes <- "Treatment-pattern name -> treatment."
  } else if (kind == "character" && is_free_text(x)) {
    role <- "ignore"
    notes <- "High-cardinality character (likely free text) -> ignore."
  } else {
    role <- "covariate"
    notes <- "Default -> covariate; re-role to outcome if response variable."
  }

  data.frame(
    col = nm,
    role = role,
    kind = kind,
    freq_or_range = summarise_kind(x, kind),
    pii_suspected = is_pii,
    notes = notes,
    stringsAsFactors = FALSE
  )
}

col_kind <- function(x) {
  if (inherits(x, c("POSIXct", "POSIXlt"))) {
    return("datetime")
  }
  if (inherits(x, "Date")) {
    return("date")
  }
  if (inherits(x, "difftime")) {
    return("datetime")
  }
  if (is.logical(x)) {
    return("logical")
  }
  if (is.factor(x)) {
    return("factor")
  }
  if (is.integer(x)) {
    return("integer")
  }
  if (is.numeric(x)) {
    return("numeric")
  }
  if (is.character(x)) {
    return("character")
  }
  "other"
}

is_free_text <- function(x, threshold = 0.5) {
  n <- length(x)
  if (n == 0L) {
    return(FALSE)
  }
  k <- length(unique(stats::na.omit(x)))
  k / n > threshold
}

# Pattern constants. Tested in test-propose_roles.R.
ID_PATTERN <- "(\\bid\\b|_id$|^id_)"
DESIGN_PATTERN <- paste0(
  "(^rep[0-9]*$|^block$|^row$|^col(umn)?$|^range$|^plot(no)?$|^site$|",
  "^env(ironment)?$|^trial(_?acronym)?$|^year$|^season$|^colrep$|^tos$)"
)
TREATMENT_PATTERN <- "(treatment|^variety|^cultivar|genotype|^trt|^dose$)"
PII_PATTERN <- paste0(
  "(contact|email|phone|address|gps|latitude|longitude|\\blat\\b|",
  "\\blon\\b|postcode|postal|^zip|ssn|dob|birthdate|password|secret|",
  "api[_-]?key|owner|farmer|operator|customer)"
)

matches_pattern <- function(nm, pat) {
  grepl(pat, nm, ignore.case = TRUE, perl = TRUE)
}

summarise_kind <- function(x, kind) {
  switch(kind,
    "numeric" = ,
    "integer" = {
      r <- suppressWarnings(range(x, na.rm = TRUE))
      if (any(!is.finite(r))) "[all NA]" else sprintf("[%g, %g]", r[1], r[2])
    },
    "factor" = sprintf("n=%d levels", length(levels(x))),
    "character" = sprintf("n=%d unique", length(unique(stats::na.omit(x)))),
    "logical" = {
      tbl <- table(x, useNA = "no")
      paste(names(tbl), tbl, sep = "=", collapse = ", ")
    },
    "date" = ,
    "datetime" = {
      r <- suppressWarnings(range(x, na.rm = TRUE))
      if (any(!is.finite(unclass(r)))) {
        "[all NA]"
      } else {
        sprintf("[%s, %s]", format(r[1]), format(r[2]))
      }
    },
    "other" = paste(class(x), collapse = "/")
  )
}
