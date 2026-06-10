#' Resolve the mode argument and look up per-mode defaults
#'
#' Since the two-axis roles model (masque 0.6.0), which columns are
#' aliased, kept, or dropped is decided per column by `roles$action`;
#' the mode now governs only the cross-cutting behaviours that are not
#' per-column choices: numeric jitter, automatic auditing, and print
#' redaction.
#'
#' @param mode Either `"local"` or `"collaborate"`.
#' @return A list of mode-specific defaults consumed by `mask()`.
#' @keywords internal
#' @noRd
mode_defaults <- function(mode = c("local", "collaborate")) {
  mode <- match.arg(mode)
  switch(mode,
    local = list(
      jitter_numeric = FALSE,
      audit_auto     = FALSE,
      redact_print   = FALSE
    ),
    collaborate = list(
      jitter_numeric = TRUE,
      audit_auto     = TRUE,
      redact_print   = TRUE
    )
  )
}
