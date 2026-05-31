#' Run an expression under a temporary RNG state
#'
#' Wraps `withr::with_seed()` / `withr::with_preserve_seed()` so that
#' `mask()` and friends never mutate the caller's `.Random.seed`. Used as
#' the only stochastic-call boundary inside the package.
#'
#' @param seed Single integer or `NULL`. When `NULL`, the current RNG state
#'   is preserved (stochasticity happens, but `.Random.seed` is restored
#'   after `expr` returns). When numeric, the seed is set for the duration
#'   of `expr`.
#' @param expr Expression to evaluate.
#'
#' @return The value of `expr`.
#' @keywords internal
#' @noRd
with_rng_state <- function(seed, expr) {
  if (is.null(seed)) {
    return(withr::with_preserve_seed(expr))
  }
  if (!is.numeric(seed) || length(seed) != 1L || is.na(seed)) {
    cli::cli_abort(
      paste0(
        "`seed` must be a single integer (or NULL); got ",
        "{.cls {class(seed)[1]}} of length {length(seed)}."
      )
    )
  }
  withr::with_seed(as.integer(seed), expr)
}
