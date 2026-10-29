#' Collaborate-mode numeric perturbation: jitter plus integer rounding
#'
#' Layered on top of `synthesise_numeric_local()` in collaborate mode.
#' Takes a synthetic column (drawn from the observed multiset by the
#' local copula path) and perturbs it with uniform jitter inside the
#' observed measurement resolution, then re-clips to the observed range.
#' Whole-numbered columns (integer class, or a double whose observed values
#' are all whole) get bounded stochastic rounding, so the output stays
#' whole-numbered in its original storage class without escaping the
#' observed range. A column with at most two distinct observed values is
#' left as drawn: the local copula draw already returns observed values,
#' and jitter followed by rounding would flip a share of them.
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

  if (length(unique(x_obs[!is.na(x_obs)])) <= 2L) {
    return(x_new)
  }

  is_int <- is.integer(x_obs)
  is_whole <- .is_whole_valued(x_obs)
  res <- .detect_resolution(x_obs)

  if (res > 0) {
    x_new <- x_new + stats::runif(length(x_new), -res / 2, res / 2)
  }

  lo <- suppressWarnings(min(x_obs, na.rm = TRUE))
  hi <- suppressWarnings(max(x_obs, na.rm = TRUE))
  if (is.finite(lo) && is.finite(hi)) {
    x_new <- pmin(pmax(x_new, lo), hi)
  }

  if (is_whole) {
    if (is.finite(lo) && is.finite(hi)) {
      x_new <- .bounded_stochastic_round(x_new, lo, hi, as_int = is_int)
    } else {
      x_new <- round(x_new)
      if (is_int) x_new <- as.integer(x_new)
    }
  }

  x_new
}

# Internal: measurement resolution per column: 1 for whole-valued columns,
# else the smallest gap between sorted unique values, floored at a share of
# the range.
.detect_resolution <- function(x) {
  x_clean <- x[!is.na(x)]
  if (length(x_clean) == 0L) {
    return(0)
  }
  uvals <- unique(x_clean)
  if (length(uvals) <= 1L) {
    return(0)
  }
  if (.is_whole_valued(x_clean)) {
    return(1)
  }

  diffs <- diff(sort(uvals))
  res <- min(diffs[diffs > 0], na.rm = TRUE)
  rng <- diff(range(x_clean))
  if (is.finite(rng) && rng > 0) res <- max(res, rng * 1e-8)
  res
}

# Internal: stochastic rounding to a whole number in [lo, hi]: up with
# probability x - floor(x), else down. Integer class unless `as_int = FALSE`.
.bounded_stochastic_round <- function(x, lo, hi, as_int = TRUE) {
  floor_x <- floor(x)
  frac <- x - floor_x
  rolls <- stats::runif(length(x))
  rounded <- ifelse(rolls < frac, floor_x + 1, floor_x)
  rounded <- pmin(pmax(rounded, lo), hi)
  if (as_int) as.integer(rounded) else rounded
}

# Internal: TRUE for integer class, or a double whose finite non-missing
# values are all whole numbers.
.is_whole_valued <- function(x) {
  if (is.integer(x)) {
    return(TRUE)
  }
  x_fin <- x[is.finite(x)]
  is.double(x) && length(x_fin) > 0L && all(x_fin == round(x_fin))
}
