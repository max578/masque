#' Local-mode Gaussian-copula synthesis for numeric columns
#'
#' Empirical-quantile marginals + a global Pearson Sigma Gaussian copula.
#' Used for outcome and numeric-covariate columns in `mode = "local"`.
#' Collaborate-mode adds within-resolution jitter and bounded stochastic
#' rounding on top (build-order step 7).
#'
#' Returns observed values directly (`type = 1` empirical quantile), so the
#' marginal distribution is exactly the empirical one. Integer columns are
#' preserved as integers. NA values are not introduced here; `mask()`
#' reapplies the NA mask cell-by-cell after this function returns.
#'
#' @param x_obs A data frame whose columns are all numeric or integer.
#' @param n Number of rows to generate. Defaults to `nrow(x_obs)`.
#' @param regularise Logical; if `TRUE` (default), `Matrix::nearPD()` is
#'   applied to the latent-Z covariance matrix when it is not positive
#'   semi-definite.
#'
#' @return A data frame with the same column names and types as `x_obs`,
#'   containing `n` rows of synthetic values.
#' @keywords internal
#' @noRd
synthesise_numeric_local <- function(
  x_obs, n = nrow(x_obs), regularise = TRUE
) {
  if (!is.data.frame(x_obs)) {
    cli::cli_abort("`x_obs` must be a data frame.")
  }
  p <- ncol(x_obs)
  if (p == 0L) {
    return(x_obs[FALSE, , drop = FALSE])
  }

  num_ok <- vapply(
    x_obs, function(x) is.numeric(x) || is.integer(x), logical(1)
  )
  if (!all(num_ok)) {
    cli::cli_abort(
      paste0(
        "Non-numeric column(s) passed to numeric synthesiser: ",
        "{.field {names(x_obs)[!num_ok]}}."
      )
    )
  }

  # Zero-variance / all-NA columns: pass observed-as-is sample.
  zero_var <- vapply(x_obs, function(x) {
    x_clean <- x[!is.na(x)]
    length(x_clean) == 0L || length(unique(x_clean)) == 1L
  }, logical(1))

  # Build U in (0, 1) via empirical-rank transform per column.
  # NAs propagate as NA in U (handled by `pairwise.complete.obs` in cov()).
  ranks <- vapply(x_obs, function(x) {
    rk <- rank(x, na.last = "keep", ties.method = "average")
    rk / (sum(!is.na(x)) + 1)
  }, numeric(nrow(x_obs)))
  if (is.null(dim(ranks))) {
    ranks <- matrix(ranks, ncol = p, dimnames = list(NULL, names(x_obs)))
  }

  Z <- stats::qnorm(ranks)

  if (p == 1L) {
    # Univariate: skip copula machinery; sample uniform, push through the
    # empirical quantile.
    u_new <- stats::runif(n)
    val <- stats::quantile(
      x_obs[[1L]],
      probs = u_new, na.rm = TRUE, names = FALSE, type = 1L
    )
    out <- data.frame(val, stringsAsFactors = FALSE)
    names(out) <- names(x_obs)
    if (is.integer(x_obs[[1L]])) out[[1L]] <- as.integer(out[[1L]])
    return(out)
  }

  # Latent covariance on Z; pairwise complete to tolerate NAs.
  sigma <- stats::cov(Z, use = "pairwise.complete.obs")
  # Replace any residual NA (column had all NA pairwise overlap) with 0;
  # identity on diagonal.
  sigma[is.na(sigma)] <- 0
  diag_na <- is.na(diag(sigma))
  if (any(diag_na)) diag(sigma)[diag_na] <- 1
  # Zero-variance columns: force corresponding row/col to identity-like
  # (no correlation).
  if (any(zero_var)) {
    sigma[zero_var, ] <- 0
    sigma[, zero_var] <- 0
    diag(sigma)[zero_var] <- 1
  }

  if (regularise) {
    ev <- min(eigen(sigma, symmetric = TRUE, only.values = TRUE)$values)
    if (!is.finite(ev) || ev < sqrt(.Machine$double.eps)) {
      sigma <- as.matrix(
        Matrix::nearPD(sigma, corr = FALSE, ensureSymmetry = TRUE)$mat
      )
    }
  }

  Z_new <- MASS::mvrnorm(n = n, mu = rep(0, p), Sigma = sigma)
  if (n == 1L) Z_new <- matrix(Z_new, nrow = 1L)
  U_new <- stats::pnorm(Z_new)

  # Empirical-quantile inverse (type = 1: discontinuous step; returns
  # observed values).
  out_cols <- lapply(seq_len(p), function(j) {
    obs_j <- x_obs[[j]]
    if (all(is.na(obs_j))) {
      return(rep(NA_real_, n))
    }
    if (zero_var[j]) {
      val <- unique(obs_j[!is.na(obs_j)])[1L]
      return(rep(val, n))
    }
    stats::quantile(
      obs_j,
      probs = U_new[, j], na.rm = TRUE, names = FALSE, type = 1L
    )
  })

  out <- as.data.frame(
    out_cols,
    stringsAsFactors = FALSE, col.names = names(x_obs)
  )

  # Preserve integer class
  for (j in seq_len(p)) {
    if (is.integer(x_obs[[j]])) out[[j]] <- as.integer(out[[j]])
  }

  out
}
