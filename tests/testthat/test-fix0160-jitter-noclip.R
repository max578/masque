# Collaborate jitter does not clip onto the real minimum and maximum.

test_that("jittered draws at the extremes do not land on the real extremes", {
  x_obs <- withr::with_seed(1L, round(stats::rgamma(200, 2, 1), 3))
  lo <- min(x_obs)
  hi <- max(x_obs)
  x_new <- c(rep(lo, 100), rep(hi, 100))
  out <- withr::with_seed(2L, {
    masque:::synthesise_numeric_collaborate(x_obs, x_new)
  })
  expect_false(any(out == lo))
  expect_false(any(out == hi))
  expect_true(any(out < lo))
  expect_true(any(out > hi))
})

test_that("whole-valued jitter rounds without a clip to the observed range", {
  x_obs <- withr::with_seed(1L, sample(1L:20L, 400, replace = TRUE))
  out <- withr::with_seed(2L, {
    masque:::synthesise_numeric_collaborate(x_obs, rep(20L, 400))
  })
  expect_type(out, "integer")
  expect_true(any(out > 20L))
})

test_that("a lower bound, when given, is still respected", {
  x_obs <- withr::with_seed(1L, c(0, round(stats::rexp(199), 2)))
  out <- withr::with_seed(2L, {
    masque:::synthesise_numeric_collaborate(x_obs, rep(0, 200), lower = 0)
  })
  expect_true(all(out >= 0))
  xi <- withr::with_seed(1L, sample(0L:9L, 200, replace = TRUE))
  oi <- withr::with_seed(2L, {
    masque:::synthesise_numeric_collaborate(xi, rep(0L, 200), lower = 0)
  })
  expect_true(all(oi >= 0L))
})

test_that("no grained unit value of the E3 fixture is a real extreme", {
  df <- withr::with_seed(1L, {
    g <- expand.grid(
      gen = sprintf("G%02d", 1:10), rep = 1:3, trial = sprintf("T%d", 1:6),
      stringsAsFactors = FALSE, KEEP.OUT.ATTRS = FALSE
    )
    g$yield <- round(stats::rnorm(nrow(g), 3, 0.4), 2)
    g$aet <- c(312.456, 287.901, 401.233, 355.678, 298.112, 376.543)[
      match(g$trial, sprintf("T%d", 1:6))
    ]
    g
  })
  r <- suppressWarnings(propose_roles(df, mode = "collaborate", detect = FALSE))
  r <- set_role(r, c("trial", "rep"), role = "design", action = "keep")
  r <- set_role(r, "gen", role = "treatment", action = "alias")
  r <- set_role(r, "yield", role = "outcome", action = "scramble")
  r <- set_role(r, "aet", role = "covariate", action = "scramble")
  for (s in 1:5) {
    m <- suppressWarnings(mask(df, r, mode = "collaborate", seed = s))
    aet <- synthetic(m)$aet
    expect_false(any(aet %in% range(df$aet)))
    expect_false(any(synthetic(m)$yield %in% range(df$yield)))
  }
})
