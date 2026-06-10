#' Propose role and action classifications for the columns of a data frame
#'
#' Generates a heuristic two-axis classification for every column of
#' `df`: a `role` (what the column *is*) and an `action` (what [mask()]
#' will *do* to it). The user is expected to inspect this table and edit
#' it - directly or via [set_role()] - before passing it to [mask()].
#' Heuristics are seeds, not law.
#'
#' @section The two axes:
#'
#' `role` describes the column and determines the *mechanics* of any
#' synthesis:
#'
#' \describe{
#'   \item{`design`}{Experimental / structural columns (site, block,
#'     rep, plot, year). Mechanics of `alias`: labels are substituted in
#'     place, structure intact.}
#'   \item{`treatment`}{Assignment columns (variety, genotype, dose).
#'     Labels are remapped in place - the assignment structure never
#'     moves. `scramble` = seeded label permutation; `alias` = opaque
#'     labels (`trt_001`).}
#'   \item{`outcome`}{Numeric response columns. `scramble` re-simulates
#'     via the Gaussian copula, jointly with scrambled numeric
#'     covariates. Multiple outcomes are supported.}
#'   \item{`covariate`}{Everything measured alongside. Numeric:
#'     copula re-simulation. Categorical: row permutation, plus opaque
#'     label aliasing under `alias`.}
#'   \item{`date`}{Date / POSIX / difftime columns. `scramble` row-
#'     permutes within the observed values; class and NA pattern are
#'     preserved.}
#'   \item{`id`}{Identifier columns. Never scrambled (that would break
#'     row linkage); `alias` substitutes opaque per-value labels in
#'     place, preserving linkage.}
#'   \item{`text`}{Free-text columns. `scramble` row-permutes; `alias`
#'     tokenises each distinct string.}
#'   \item{`other`}{Classes masque cannot synthesise (list columns,
#'     exotic S4, ...). Keep or drop only.}
#' }
#'
#' `action` sets the masking depth per column:
#'
#' \describe{
#'   \item{`keep`}{Byte-identical pass-through, both modes.}
#'   \item{`scramble`}{Re-simulate (numeric) or row-permute
#'     (categorical / date / text); original label vocabulary remains
#'     visible.}
#'   \item{`alias`}{Scramble where applicable, plus opaque label
#'     substitution - the vocabulary itself is hidden.}
#'   \item{`drop`}{Column excluded from the synthetic, both modes.}
#' }
#'
#' The proposed `action` column is resolved for `mode`, so the table you
#' edit shows the actual masking plan. Re-assigning a column's role
#' with [set_role()] re-resolves its default action; a direct
#' `roles$role[...] <- ...` edit leaves `action` untouched (set it to
#' `NA` to have [mask()] re-resolve the default).
#'
#' @section Default classification rules, applied in order:
#'
#' 1. PII-pattern column names (`contact`, `email`, `phone`, `gps`,
#'    `latitude` / `longitude`, `postcode`, `ssn`, `password`, `owner`,
#'    `farmer`, `operator`, etc., case-insensitive substring) ->
#'    `pii_suspected = TRUE` and action `drop` in **both** modes.
#'    Re-role deliberately if the column must survive.
#' 2. Date / POSIXct / POSIXlt / difftime columns -> role `date`,
#'    action `scramble` (row permutation).
#' 3. ID-pattern names (`\\bid\\b`, `_id$`, `^id_`) -> role `id`; kept
#'    in local mode, dropped in collaborate mode.
#' 4. Design-pattern names (`rep`, `block`, `row`, `col(umn)?`,
#'    `range`, `plot(no)?`, `site`, `env(ironment)?`, `trial`, `year`,
#'    `season`, `colrep`, `tos`) -> role `design`, action `keep`.
#' 5. Treatment-pattern names (`treatment`, `variety`, `cultivar`,
#'    `genotype`, `^trt`, `^dose`) -> role `treatment`; kept in local
#'    mode, aliased in collaborate mode.
#' 6. Character columns with > 50% unique values on non-NA -> role
#'    `text`; kept in local mode, dropped in collaborate mode.
#' 7. Unsupported classes -> role `other`, action `keep`, with a note.
#' 8. Everything else -> role `covariate`, action `scramble`. Re-role
#'    response variables as `outcome`.
#'
#' No outcome is required: with no column roled `outcome`, the copula
#' simply re-simulates all scrambled numeric columns jointly.
#'
#' Since masque 0.3.0, [propose_roles()] also calls [detect_design()] by
#' default (`detect = TRUE`) and applies the detected design's
#' `recommended_roles` on top of the name-based heuristic, re-resolving
#' the default action for any promoted column. The design summary is
#' stashed as `attr(roles, "design")`. Pass `detect = FALSE` for the
#' name-only heuristic.
#'
#' @param df A data frame. Must have at least one column.
#' @param mode The masking mode the table is being prepared for:
#'   `"local"` (default) or `"collaborate"`. Stored as
#'   `attr(roles, "mode")` and used to resolve default actions.
#' @param detect Logical scalar (default `TRUE`). When `TRUE`, run
#'   [detect_design()] and overlay its recommended role hints.
#'
#' @return A tibble with one row per column: `col`, `role`, `action`,
#'   `kind` (storage kind: `numeric`, `integer`, `factor`, `character`,
#'   `logical`, `date`, `datetime`, `other`), `freq_or_range`,
#'   `pii_suspected`, and `notes`. The target mode is stored as
#'   `attr(roles, "mode")`.
#'
#' @examples
#' propose_roles(iris)
#' propose_roles(iris, mode = "collaborate")
#'
#' @seealso [set_role()] to edit; [roles_validate()] for the fail-closed
#'   validation applied at `mask()` time.
#'
#' @export
propose_roles <- function(df, mode = c("local", "collaborate"),
                          detect = TRUE) {
  if (!is.data.frame(df)) {
    cli::cli_abort("`df` must be a data frame; got {.cls {class(df)[1]}}.")
  }
  if (ncol(df) == 0L) {
    cli::cli_abort("`df` has no columns.")
  }
  mode <- match.arg(mode)

  rows <- lapply(names(df), function(nm) {
    classify_one_column(nm, df[[nm]], mode)
  })
  roles <- tibble::as_tibble(do.call(
    rbind.data.frame,
    c(rows, list(stringsAsFactors = FALSE))
  ))
  attr(roles, "mode") <- mode
  attr(roles, "proposed_actions") <- stats::setNames(roles$action, roles$col)

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
    roles <- .overlay_recommended_roles(roles, ds@recommended_roles, mode)
  }
  attr(roles, "design") <- ds
  roles
}

# Apply detect_design()'s recommended_roles on top of the name-based
# tibble. Overrides role, re-resolves the default action for the new
# role, and extends the notes string. Never introduces or drops rows.
.overlay_recommended_roles <- function(roles, rec, mode) {
  for (i in seq_len(nrow(rec))) {
    col_i <- rec$col[i]
    role_i <- rec$role[i]
    row_idx <- which(roles$col == col_i)
    if (length(row_idx) != 1L) next
    if (identical(roles$role[row_idx], role_i)) next
    old_role <- roles$role[row_idx]
    roles$role[row_idx] <- role_i
    roles$action[row_idx] <- .default_action(
      role_i, roles$kind[row_idx], mode
    )
    pa <- attr(roles, "proposed_actions")
    if (!is.null(pa)) {
      pa[[col_i]] <- roles$action[row_idx]
      attr(roles, "proposed_actions") <- pa
    }
    roles$notes[row_idx] <- sprintf(
      "detect_design: %s -> %s (was: %s)",
      old_role, role_i, roles$notes[row_idx]
    )
  }
  roles
}

# Internal: classify a single column and return a single-row data.frame.
classify_one_column <- function(nm, x, mode = "local") {
  kind <- col_kind(x)
  is_pii <- matches_pattern(nm, PII_PATTERN)
  collab <- identical(mode, "collaborate")

  if (is_pii) {
    role <- if (kind %in% c("character", "factor")) {
      "text"
    } else if (kind %in% .date_kinds()) {
      "date"
    } else if (kind == "other") {
      "other"
    } else {
      "covariate"
    }
    action <- "drop"
    notes <- paste0(
      "PII pattern in column name -> drop in both modes (flagged); ",
      "re-role deliberately to retain."
    )
  } else if (kind %in% .date_kinds()) {
    role <- "date"
    action <- .default_action(role, kind, mode)
    notes <- paste0(
      "Date/time column -> row-permuted; class and NA pattern ",
      "preserved. Use keep to leave untouched."
    )
  } else if (matches_pattern(nm, ID_PATTERN)) {
    role <- "id"
    action <- .default_action(role, kind, mode)
    notes <- if (collab) {
      "ID-pattern name -> dropped in collaborate; alias to keep linkage."
    } else {
      "ID-pattern name -> kept in local mode; alias to hide values."
    }
  } else if (matches_pattern(nm, DESIGN_PATTERN)) {
    role <- "design"
    action <- "keep"
    notes <- "Design-pattern name -> design (byte-identical)."
  } else if (matches_pattern(nm, TREATMENT_PATTERN)) {
    role <- "treatment"
    action <- .default_action(role, kind, mode)
    notes <- if (collab) {
      "Treatment-pattern name -> labels aliased in collaborate mode."
    } else {
      "Treatment-pattern name -> passes through in local mode."
    }
  } else if (kind == "character" && is_free_text(x)) {
    role <- "text"
    action <- .default_action(role, kind, mode)
    notes <- if (collab) {
      "High-cardinality character (likely free text) -> dropped."
    } else {
      "High-cardinality character (likely free text) -> kept in local."
    }
  } else if (kind == "other") {
    role <- "other"
    action <- "keep"
    notes <- "Unsupported class -> kept as-is; set action drop to remove."
  } else {
    role <- "covariate"
    action <- .default_action(role, kind, mode)
    notes <- paste0(
      "Default -> covariate; re-role to outcome if response variable, ",
      "or set action keep to leave untouched."
    )
  }

  data.frame(
    col = nm,
    role = role,
    action = action,
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
