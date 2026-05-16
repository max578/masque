#' Collaborate-mode numeric perturbation: within-resolution jitter + integer rounding
#'
#' Layered on top of `synthesise_numeric_local()` in collaborate mode.
#' Takes a synthetic column (drawn from the observed multiset by the
#' local copula path) and perturbs it with uniform jitter inside the
#' observed measurement resolution, then re-clips to the observed range.
#' Integer columns get bounded stochastic rounding so the output stays
#' integer-class without escaping the observed range.
#'
#' Used to push `exact_match_pct` below the audit thresholds (< 1% on
#' continuous outcomes; < 5% on continuous covariates) while keeping
#' the distribution shape and integer storage class intact.
#'
#' @param x_obs Original observed numeric vector (used to determine
#'   resolution and clipping bounds).
#' @param x_new Synthetic vector to perturb (same length as `x_obs`).
#'
#' @return A numeric vector of the same length and storage class as
#'   `x_obs`.
#' @keywords internal
#' @noRd
synthesise_numeric_collaborate <- function(x_obs, x_new) {
  if (length(x_obs) != length(x_new)) {
    cli::cli_abort("`x_obs` and `x_new` must have the same length.")
  }

  is_int <- is.integer(x_obs)
  res    <- .detect_resolution(x_obs)

  if (res > 0) {
    x_new <- x_new + stats::runif(length(x_new), -res / 2, res / 2)
  }

  lo <- suppressWarnings(min(x_obs, na.rm = TRUE))
  hi <- suppressWarnings(max(x_obs, na.rm = TRUE))
  if (is.finite(lo) && is.finite(hi)) {
    x_new <- pmin(pmax(x_new, lo), hi)
  }

  if (is_int) {
    if (is.finite(lo) && is.finite(hi)) {
      x_new <- .bounded_stochastic_round(x_new, lo, hi)
    } else {
      x_new <- as.integer(round(x_new))
    }
  }

  x_new
}

# Internal: per-column measurement resolution.
#
# For integer columns: 1.
# For numeric: the minimum positive gap between sorted unique observed
# values, floored at a small fraction of the data range to avoid
# degenerate near-zero values from floating-point representation.
.detect_resolution <- function(x) {
  x_clean <- x[!is.na(x)]
  if (length(x_clean) == 0L) return(0)
  uvals <- unique(x_clean)
  if (length(uvals) <= 1L) return(0)
  if (is.integer(x_clean)) return(1)

  diffs <- diff(sort(uvals))
  res   <- min(diffs[diffs > 0], na.rm = TRUE)
  rng   <- diff(range(x_clean))
  if (is.finite(rng) && rng > 0) res <- max(res, rng * 1e-8)
  res
}

# Internal: round to integer in [lo, hi], stochastically.
#
# For each x_i:
#   floor(x_i)     with probability 1 - frac
#   floor(x_i) + 1 with probability frac
# where frac = x_i - floor(x_i). Result is clipped to [lo, hi]
# and cast to integer.
.bounded_stochastic_round <- function(x, lo, hi) {
  floor_x <- floor(x)
  frac    <- x - floor_x
  rolls   <- stats::runif(length(x))
  rounded <- ifelse(rolls < frac, floor_x + 1, floor_x)
  as.integer(pmin(pmax(rounded, lo), hi))
}
