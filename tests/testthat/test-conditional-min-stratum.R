# A stratum smaller than min_stratum is pooled. Within a stratum the synthetic
# mean has expectation equal to the observed mean and SD sigma_hat / sqrt(n).

# Four cells with means 0, 10, 20, 30 and sizes 3, 3, 10, 10. The cell
# sizes straddle min_stratum = 5 and all lie below min_stratum = 20.
straddle_fixture <- function(seed = 424242L) {
  set.seed(seed)
  sizes <- c(a = 3L, b = 3L, c = 10L, d = 10L)
  means <- c(a = 0, b = 10, c = 20, d = 30)
  cell <- factor(rep(names(sizes), times = sizes), levels = names(sizes))
  y <- means[as.character(cell)] + stats::rnorm(sum(sizes), sd = 1)
  list(
    x = data.frame(y = as.numeric(y)),
    cell = cell,
    sizes = sizes
  )
}

.cell_means <- function(y, cell) tapply(y, cell, mean)

# sigma_hat / sqrt(n) per cell -- the exact standard deviation of a
# with-replacement sample mean from that cell.
.cell_se <- function(y, cell) {
  vapply(split(y, cell), function(v) {
    sqrt(mean((v - mean(v))^2) / length(v))
  }, numeric(1))
}

test_that("min_stratum = 2 stratifies every cell in the layout", {
  f <- straddle_fixture()
  expect_true(all(f$sizes >= 2L))

  set.seed(11)
  out <- masque:::synthesise_numeric_conditional(
    f$x, f$cell, min_stratum = 2L
  )
  obs <- .cell_means(f$x$y, f$cell)
  syn <- .cell_means(out$y, f$cell)
  se <- .cell_se(f$x$y, f$cell)
  # Cell means are ten units apart; pooled cells cannot stay inside this band.
  expect_true(all(abs(syn - obs) <= 4 * se))

  expect_equal(
    masque:::.stratum_fallback_frac(f$cell, min_stratum = 2L), 0
  )
})

test_that("min_stratum = 5 pools only the cells below it", {
  f <- straddle_fixture()

  # 6 of 26 rows sit in cells of size 3.
  expect_equal(
    masque:::.stratum_fallback_frac(f$cell, min_stratum = 5L),
    6 / 26
  )

  set.seed(11)
  out <- masque:::synthesise_numeric_conditional(
    f$x, f$cell, min_stratum = 5L
  )
  obs <- .cell_means(f$x$y, f$cell)
  syn <- .cell_means(out$y, f$cell)
  se <- .cell_se(f$x$y, f$cell)

  # The two cells above the threshold are still conditioned on.
  expect_true(all(abs(syn[c("c", "d")] - obs[c("c", "d")]) <=
    4 * se[c("c", "d")]))
  # Cells a and b are pooled (mean about 5), pulling their means out of band.
  expect_true(any(abs(syn[c("a", "b")] - obs[c("a", "b")]) >
    4 * se[c("a", "b")]))
})

test_that("min_stratum = 20 pools the whole layout", {
  f <- straddle_fixture()
  expect_true(all(f$sizes < 20L))
  expect_equal(
    masque:::.stratum_fallback_frac(f$cell, min_stratum = 20L), 1
  )

  set.seed(11)
  out_20 <- masque:::synthesise_numeric_conditional(
    f$x, f$cell, min_stratum = 20L
  )
  set.seed(11)
  out_2 <- masque:::synthesise_numeric_conditional(
    f$x, f$cell, min_stratum = 2L
  )
  obs <- .cell_means(f$x$y, f$cell)
  se <- .cell_se(f$x$y, f$cell)
  mae <- function(y) mean(abs(.cell_means(y, f$cell) - obs))
  # Pooled cells all share the union mean of 20.4, far outside this bound.
  band <- 4 * mean(se)
  expect_lt(mae(out_2$y), band)
  expect_gt(mae(out_20$y), band)
})

test_that("the ladder honours min_stratum when choosing a rung", {
  # Cells of 5, 5, 10, 10 rows, each halved by a second design column, put
  # min_stratum = 2, 5 and 20 on three different rungs.
  sizes <- c(a = 5L, b = 5L, c = 10L, d = 10L)
  cell <- factor(rep(names(sizes), times = sizes), levels = names(sizes))
  half <- factor(unlist(lapply(
    sizes, function(n) rep(c("L", "R"), length.out = n)
  ), use.names = FALSE))
  set.seed(8)
  df <- data.frame(cell = cell, half = half, y = stats::rnorm(sum(sizes)))
  expect_true(all(table(cell, half) >= 2L))
  lad_2 <- masque:::.conditioning_ladder(
    df, c("cell", "half"), protect_cols = "cell", min_stratum = 2L
  )
  expect_identical(lad_2$used, c("cell", "half"))
  expect_identical(lad_2$dropped, character())

  expect_equal(lad_2$fallback_frac, 0)

  lad_5 <- masque:::.conditioning_ladder(
    df, c("cell", "half"), protect_cols = "cell", min_stratum = 5L
  )
  expect_identical(lad_5$used, "cell")
  expect_identical(lad_5$dropped, "half")
  expect_equal(lad_5$fallback_frac, 0)

  # At min_stratum = 20 the ladder stops at the treatment column and reports
  # the residual fallback.
  lad_20 <- masque:::.conditioning_ladder(
    df, c("cell", "half"), protect_cols = "cell", min_stratum = 20L
  )
  expect_identical(lad_20$used, "cell")
  expect_equal(lad_20$fallback_frac, 1)
})

# `regularise` is the other never-exercised argument M-18 names.
test_that("synthesise_numeric_local runs with regularise = FALSE", {
  set.seed(5)
  x <- data.frame(a = stats::rnorm(40))
  x$b <- 2 * x$a # exactly collinear: the latent Sigma is rank-deficient
  x$c <- stats::rnorm(40)

  set.seed(6)
  out_f <- masque:::synthesise_numeric_local(x, regularise = FALSE)
  set.seed(6)
  out_t <- masque:::synthesise_numeric_local(x, regularise = TRUE)

  for (nm in names(x)) {
    expect_true(all(is.finite(out_f[[nm]])))
    expect_true(all(is.finite(out_t[[nm]])))
    # type = 1 empirical-quantile inverse returns observed values only.
    expect_true(all(out_f[[nm]] %in% x[[nm]]))
    expect_true(all(out_t[[nm]] %in% x[[nm]]))
  }
})
