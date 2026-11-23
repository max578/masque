# The noise action: replace a column with independent draws that use nothing
# from its values beyond a coarse summary. The missing-value mask and the
# storage class are kept; rows are not linked to the original in any way.

# Knots of the summary quantile function: the 1st percentile, the deciles and
# the 99th percentile, read as the quantile function at 0, 0.1, ..., 1.
.NOISE_PROBS <- c(0.01, seq(0.1, 0.9, by = 0.1), 0.99)

# Fewest finite values a summary draw reads. Eleven or fewer are recovered
# exactly from the eleven knots, so a shorter column takes the standard draw.
.NOISE_MIN_FINITE <- 12L

# Internal: draw one column as noise. `x` is the original column; `noise` is
# "summary" or "standard"; `prefix` names coded categorical levels; `name`
# and `what` word the warnings. Returns list(x = column, map = original ->
# code map or NULL, note = warning text or NULL). Only the non-missing cells
# are drawn, so the draw count depends on the NA mask alone.
.noise_column <- function(x, noise, prefix, name = prefix,
                          what = c("finite value", "finite values")) {
  obs <- !is.na(x)
  n_obs <- sum(obs)
  if (inherits(x, "POSIXlt")) {
    x <- as.POSIXct(x)
  }

  if (is.logical(x)) {
    lv <- sort(unique(x[obs]))
    out <- x
    note <- NULL
    if (n_obs && n_obs < .NOISE_MIN_FINITE) {
      note <- .noise_small_warning(name, n_obs, what)
      lv <- c(FALSE, TRUE)
    } else if (length(lv) == 1L) {
      note <- .noise_single_warning(name)
    }
    out[obs] <- if (length(lv)) lv[.noise_index(length(lv), n_obs)] else x[obs]
    return(list(x = out, map = NULL, note = note))
  }

  if (is.factor(x) || is.character(x)) {
    res <- alias_levels(x, prefix = prefix)
    codes <- .alias_pool(prefix, length(res$map))
    if (!length(codes)) {
      return(list(x = x, map = NULL))
    }
    drawn <- rep(NA_character_, length(x))
    drawn[obs] <- codes[.noise_index(length(codes), n_obs)]
    out <- if (is.factor(x)) {
      factor(drawn, levels = codes, ordered = is.ordered(x))
    } else {
      drawn
    }
    return(list(x = out, map = res$map))
  }

  # Non-finite cells (NA, NaN, Inf) are kept as they are, like the NA mask.
  v <- as.double(unclass(x))
  fin <- is.finite(v)
  n_fin <- sum(fin)
  if (!n_fin) {
    return(list(x = x, map = NULL))
  }
  note <- NULL
  if (!identical(noise, "standard") && n_fin < .NOISE_MIN_FINITE) {
    note <- .noise_small_warning(name, n_fin, what)
    noise <- "standard"
  } else if (!identical(noise, "standard") &&
    data.table::uniqueN(v[fin]) == 1L) {
    note <- .noise_single_warning(name)
  }
  new <- if (identical(noise, "standard")) {
    .noise_standard(v[fin], x)
  } else {
    .noise_from_summary(.noise_summary(v[fin]), n_fin)
  }
  whole <- is.integer(x) || .is_whole_valued(v)
  if (whole) {
    new <- round(new)
  }
  out <- v
  out[fin] <- new
  if (is.integer(x)) {
    out <- as.integer(out)
  }
  attributes(out) <- attributes(x)
  list(x = out, map = NULL, note = note)
}

# Internal: warn that a short column took the standard draw; returns the text.
.noise_small_warning <- function(name, n, what) {
  msg <- sprintf(
    paste0(
      "%s has %d %s, fewer than %d. A summary of so few gives the values ",
      "back, so it was drawn as standard noise."
    ),
    name, n, what[[if (n == 1L) 1L else 2L]], .NOISE_MIN_FINITE
  )
  warning(warningCondition(msg, class = "masque_noise_small_sample"))
  msg
}

# Internal: warn that a one-value column is that value in the clone.
.noise_single_warning <- function(name) {
  msg <- sprintf(
    "%s holds one observed value, so the clone holds that value too.", name
  )
  warning(warningCondition(msg, class = "masque_noise_single_value"))
  msg
}

# Internal: `n` uniform draws over 1..k. A single level takes no draw, so it
# does not shift later columns of the seeded stream.
.noise_index <- function(k, n) {
  if (k <= 1L) {
    return(rep.int(1L, n))
  }
  sample.int(k, n, replace = TRUE)
}

# Internal: the eleven-number summary of the observed values.
.noise_summary <- function(v) {
  stats::quantile(v, .NOISE_PROBS, names = FALSE, type = 7L)
}

# Internal: `n` draws from the piecewise-linear quantile function through the
# eleven knots; every draw lies in [p1, p99].
.noise_from_summary <- function(knots, n) {
  u <- stats::runif(n)
  stats::approx(seq(0, 1, by = 0.1), knots, xout = u, ties = "ordered")$y
}

# Internal: type-aware standard draws that read only type flags from the
# observed values `v` (the original column `x` gives the class).
.noise_standard <- function(v, x) {
  n <- length(v)
  if (inherits(x, c("Date", "POSIXct"))) {
    lo <- as.double(as.Date("2000-01-01"))
    hi <- as.double(as.Date("2000-12-31"))
    if (inherits(x, "POSIXct")) {
      lo <- lo * 86400
      hi <- hi * 86400
    }
    return(stats::runif(n, lo, hi))
  }
  whole <- is.integer(x) || .is_whole_valued(v)
  if (whole) {
    if (all(v %in% c(0, 1))) {
      return(stats::rbinom(n, 1L, 0.5))
    }
    if (all(v >= 0)) {
      return(stats::rpois(n, 5))
    }
    return(stats::rnorm(n, 0, 5))
  }
  if (all(v >= 0 & v <= 1)) {
    return(stats::rbeta(n, 2, 2))
  }
  if (all(v >= 0)) {
    return(stats::rgamma(n, shape = 2, rate = 1))
  }
  stats::rnorm(n)
}
