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
  .check_seed(seed)
  withr::with_seed(as.integer(seed), expr)
}

# A seed is a whole, finite number within the integer range; set.seed()
# would truncate 1.5 to 1 and reject 2^31 with a bare error.
.check_seed <- function(seed) {
  ok <- is.numeric(seed) && length(seed) == 1L && !is.na(seed) &&
    is.finite(seed) && seed == round(seed) &&
    abs(seed) <= .Machine$integer.max
  if (ok) {
    return(invisible(seed))
  }
  got <- if (is.numeric(seed) && length(seed) == 1L) {
    format(seed, digits = 15L)
  } else {
    sprintf("<%s> of length %d", class(seed)[1L], length(seed))
  }
  cli::cli_abort(
    c(
      paste0(
        "`seed` must be a single integer (or NULL): a whole, finite number ",
        "within the integer range."
      ),
      x = "Got {got}."
    ),
    class = c("masque_bad_seed_refusal", "orchestra_refusal")
  )
}
