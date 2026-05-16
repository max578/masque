#' Resolve the mode argument and look up per-mode defaults
#'
#' @param mode Either `"local"` or `"collaborate"`.
#' @return A list of mode-specific defaults consumed by `mask()`.
#' @keywords internal
#' @noRd
mode_defaults <- function(mode = c("local", "collaborate")) {
  mode <- match.arg(mode)
  switch(mode,
    local = list(
      alias_treatment_levels  = FALSE,
      alias_covariate_levels  = FALSE,
      drop_ignore             = FALSE,
      jitter_numeric          = FALSE,
      audit_auto              = FALSE,
      redact_print            = FALSE
    ),
    collaborate = list(
      alias_treatment_levels  = TRUE,
      alias_covariate_levels  = TRUE,
      drop_ignore             = TRUE,
      jitter_numeric          = TRUE,
      audit_auto              = TRUE,
      redact_print            = TRUE
    )
  )
}
