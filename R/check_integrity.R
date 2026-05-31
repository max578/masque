#' Internal: verify the recipe's recorded NA-mask fingerprint against
#' the candidate `original` data frame.
#'
#' Called from [apply_recipe()] when `check_integrity = TRUE` (the
#' default). Aborts with guidance if the fingerprint does not match.
#'
#' @keywords internal
#' @noRd
.check_recipe_integrity <- function(original, rec) {
  expected <- rec@integrity_fp
  if (!is.character(expected) || length(expected) != 1L || !nzchar(expected)) {
    # Recipe was built without a fingerprint (defensive: should not happen
    # in normal flows). Surface a quiet inform and proceed.
    cli::cli_inform(c(
      i = "Recipe has no integrity fingerprint; skipping NA-mask check."
    ))
    return(invisible(TRUE))
  }
  actual <- digest::digest(is.na(original), algo = "sha256")
  if (!identical(expected, actual)) {
    cli::cli_abort(c(
      paste0(
        "Recipe integrity check failed: the NA mask of {.arg original} ",
        "does not match the recipe's recorded fingerprint."
      ),
      i = paste0(
        "The recipe was built against a data frame with a different ",
        "missingness pattern (or a different schema)."
      ),
      "*" = paste0(
        "If this is intentional (the missingness has legitimately ",
        "changed since the recipe was built), pass ",
        "{.code check_integrity = FALSE} to {.fun apply_recipe}."
      )
    ))
  }
  invisible(TRUE)
}
