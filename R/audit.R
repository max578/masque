#' Audit a masque object for leakage and shareability risks
#'
#' Returns a per-column audit tibble and prints a severity-grouped report.
#' Auto-runs in `mode = "collaborate"` at [mask()] time and stores the
#' result on the masque object (`m@audit`); for local-mode audits or
#' explicit re-audits, pass the original data frame via `original`.
#'
#' Each row of the returned tibble holds:
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
#' Classification heuristics (CODEX-aligned):
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
#' Step 7 will lower numeric exact-match-pct under collaborate by adding
#' within-resolution jitter; until then, expect `medium` leakage on
#' collaborate-mode numerics.
#'
#' @param m A `masque` object from [mask()].
#' @param original Optional. Required when `m@audit` is NULL (typically
#'   in local mode). Used to recompute exact-match-pct etc. on demand.
#' @param print Logical; if TRUE (default), print a styled report.
#'
#' @return The audit tibble, returned invisibly.
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
  if (!S7::S7_inherits(m, masque)) {
    cli::cli_abort(
      "`m` must be a {.cls masque} object; got {.cls {class(m)[1]}}."
    )
  }

  audit <- m@audit
  if (is.null(audit)) {
    if (is.null(original)) {
      cli::cli_abort(c(
        paste0(
          "Audit is not stored on this masque object ",
          "(local mode does not auto-audit)."
        ),
        i = "Supply {.arg original} to recompute."
      ))
    }
    audit <- .compute_audit(original, m@synthetic, m@recipe, m@mode)
  }

  if (isTRUE(print)) .print_audit(audit, m@mode)
  invisible(audit)
}

.print_audit <- function(audit, mode) {
  cli::cli_h1(sprintf("masque audit (mode = %s)", mode))

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
