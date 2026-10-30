#' Audit a masque object for leakage and shareability risks
#'
#' Returns a per-column audit data.table and prints a severity-grouped report.
#' Auto-runs in `mode = "collaborate"` at [mask()] time and stores the
#' result on the masque object (`m@audit`); for local-mode audits or
#' explicit re-audits, pass the original data frame via `original`.
#'
#' Each row of the returned data.table holds:
#'
#' \itemize{
#'   \item `col`: column name in the original.
#'   \item `role`: assigned role.
#'   \item `kind`: storage kind.
#'   \item `leakage_class`: `low`, `medium`, or `high`.
#'   \item `n_unique_levels`: distinct non-NA values (categorical only).
#'   \item `freq_min`: minimum per-level frequency (categorical only).
#'   \item `exact_match_pct`: percentage of synthetic cells equal to the
#'     original cell (numeric only; cell-by-cell).
#'   \item `na_pct`: percentage of NA cells in the original column.
#'   \item `na_pattern_uniqueness`: fraction of rows in the original with
#'     a globally unique NA pattern (one number per data frame, repeated
#'     on every row).
#'   \item `alias_status`: `aliased`, `passthrough`, or `dropped`.
#'   \item `notes`: short human summary.
#' }
#'
#' Classification heuristics:
#'
#' \itemize{
#'   \item Retained PII-pattern column -> `high`.
#'   \item Treatment unaliased in collaborate -> `high`.
#'   \item Categorical covariate with a frequency-1 level in collaborate ->
#'     `high`.
#'   \item Outcome with exact-match-pct > 1\% in collaborate -> `medium`.
#'   \item Numeric covariate with exact-match-pct > 5\% in collaborate ->
#'     `medium`.
#'   \item Ignore column retained in local -> `low` (informational).
#' }
#'
#' As a reference point, a collaborate-mode clone of `agridat::besag.met`
#' (yield as the outcome, design columns kept) scores `low` on every
#' column, and none of its yields equals the original value.
#'
#' @param m A `masque` object from [mask()], or a `masque_set` from
#'   [mask_set()].
#' @param original Optional. Required when `m@audit` is NULL (typically
#'   in local mode). Used to recompute exact-match-pct etc. on demand.
#'   The original data frame for a `masque`; for a `masque_set`, a named
#'   list holding the original table of every table in the set.
#' @param print Logical; if TRUE (default), print a styled report.
#'
#' @return The audit data.table, returned invisibly. For a `masque_set`, a
#'   named list of per-table audit data.tables, printed table by table.
#'
#' @examples
#' r <- propose_roles(iris)
#' r$role[r$col == "Sepal.Length"] <- "outcome"
#' r$role[r$col == "Species"] <- "covariate"
#' m <- mask(iris, r, mode = "collaborate", seed = 1)
#' audit_mask(m)
#'
#' @seealso [mask()].
#' @export
audit_mask <- function(m, original = NULL, print = TRUE) {
  if (S7::S7_inherits(m, masque_set)) {
    return(.audit_mask_set(m, original, print))
  }
  if (!S7::S7_inherits(m, masque_obj)) {
    cli::cli_abort(
      paste0(
        "`m` must be a {.cls masque} or {.cls masque_set} object; got ",
        "{.cls {class(m)[1]}}."
      ),
      class = c("masque_bad_masque_obj_refusal", "orchestra_refusal")
    )
  }

  audit <- m@audit
  if (!is.null(audit)) audit <- data.table::copy(audit)
  if (is.null(audit)) {
    if (is.null(original)) {
      cli::cli_abort(c(
        paste0(
          "Audit is not stored on this masque object ",
          "(local mode does not auto-audit)."
        ),
        i = "Supply {.arg original} to recompute."
      ), class = c("masque_audit_missing_refusal", "orchestra_refusal"))
    }
    audit <- .audit_recompute(original, m@synthetic, m@recipe, m@mode)
  }

  if (isTRUE(print)) .print_audit(audit, m@mode)
  invisible(audit)
}

# Internal: audit_mask() for a masque_set; one audit per table, in set order.
.audit_mask_set <- function(m, original, print) {
  tables <- names(m@synthetic)
  audits <- m@audit
  if (is.null(audits)) {
    if (is.null(original)) {
      cli::cli_abort(c(
        paste0(
          "Audits are not stored on this masque_set ",
          "(local mode does not auto-audit)."
        ),
        i = "Supply {.arg original} as a named list of the original tables."
      ), class = c("masque_audit_missing_refusal", "orchestra_refusal"))
    }
    if (!is.list(original) || is.data.frame(original) ||
      is.null(names(original))) {
      cli::cli_abort(
        "`original` must be a named list of tables for a masque_set.",
        class = c("masque_bad_original_refusal", "orchestra_refusal")
      )
    }
    missing <- setdiff(tables, names(original))
    if (length(missing)) {
      cli::cli_abort(
        c(
          "`original` is missing table{?s}: {.val {missing}}.",
          i = "Set tables: {.val {tables}}."
        ),
        class = c("masque_bad_original_refusal", "orchestra_refusal")
      )
    }
    audits <- lapply(tables, function(nm) {
      .audit_recompute(
        original[[nm]], m@synthetic[[nm]], m@recipe@recipes[[nm]], m@mode
      )
    })
    names(audits) <- tables
  } else {
    audits <- lapply(audits, data.table::copy)
  }

  if (isTRUE(print)) {
    for (nm in tables) .print_audit(audits[[nm]], m@mode, table = nm)
  }
  invisible(audits)
}

# Internal: recompute an audit from the caller's original. The recipe's
# cleaning renames the original as mask() did, and aliased column names in
# the clone are read back to the names the recipe's roles use.
.audit_recompute <- function(original, synth, rec, mode) {
  if (!is.data.frame(original)) {
    cli::cli_abort(
      "`original` must be a data frame; got {.cls {class(original)[1]}}.",
      class = c("masque_bad_original_refusal", "orchestra_refusal")
    )
  }
  original <- .apply_cleaning_forward(original, rec@cleaning)
  cmap <- rec@column_name_map
  if (!is.null(cmap) && length(cmap)) {
    inv <- stats::setNames(names(cmap), unlist(cmap, use.names = FALSE))
    nm <- names(synth)
    hits <- nm %in% names(inv)
    nm[hits] <- unname(inv[nm[hits]])
    synth <- data.table::copy(synth)
    data.table::setnames(synth, nm)
  }
  .compute_audit(original, synth, rec, mode)
}

.print_audit <- function(audit, mode, table = NULL) {
  cli::cli_h1(if (is.null(table)) {
    sprintf("masque audit (mode = %s)", mode)
  } else {
    sprintf("masque audit: table %s (mode = %s)", table, mode)
  })

  n_high <- sum(audit$leakage_class == "high")
  n_med <- sum(audit$leakage_class == "medium")
  n_low <- sum(audit$leakage_class == "low")

  cli::cli_bullets(c(
    "*" = sprintf(
      "%d HIGH, %d medium, %d low across %d columns",
      n_high, n_med, n_low, nrow(audit)
    )
  ))

  if (!is.na(audit$na_pattern_uniqueness[1L])) {
    pct <- 100 * audit$na_pattern_uniqueness[1L]
    cli::cli_bullets(c(
      "*" = sprintf("Rows with a globally unique NA pattern: %.1f%%", pct)
    ))
  }

  for (cls in c("high", "medium", "low")) {
    rows <- audit[audit$leakage_class == cls, , drop = FALSE]
    if (!nrow(rows)) next
    cli::cli_h2(sprintf("%s (%d)", toupper(cls), nrow(rows)))
    for (i in seq_len(nrow(rows))) {
      line <- sprintf(
        "  %-9s %-32s  %s",
        rows$role[i], rows$col[i], rows$notes[i]
      )
      switch(cls,
        high   = cli::cli_alert_danger(line),
        medium = cli::cli_alert_warning(line),
        low    = cli::cli_alert_info(line)
      )
    }
  }
  invisible(NULL)
}
