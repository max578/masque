test_that(".detect_resolution returns 1 for integer columns", {
  expect_equal(masque:::.detect_resolution(1:20), 1)
  expect_equal(masque:::.detect_resolution(c(NA_integer_, 2L, 5L, 9L)), 1)
})

test_that(".detect_resolution returns the minimum positive gap for floats", {
  x <- c(0.1, 0.2, 0.5, 1.0)
  expect_equal(masque:::.detect_resolution(x), 0.1, tolerance = 1e-8)
})

test_that(".detect_resolution returns 0 on zero-variance or empty", {
  expect_equal(masque:::.detect_resolution(rep(5, 10)), 0)
  expect_equal(masque:::.detect_resolution(numeric(0)), 0)
  expect_equal(masque:::.detect_resolution(c(NA_real_, NA_real_)), 0)
})

test_that(".bounded_stochastic_round produces integers in [lo, hi]", {
  set.seed(1)
  x <- runif(100, 1, 10)
  out <- masque:::.bounded_stochastic_round(x, lo = 1, hi = 10)
  expect_type(out, "integer")
  expect_true(all(out >= 1 & out <= 10))
})

test_that(".bounded_stochastic_round preserves average (expectation)", {
  set.seed(1)
  x <- rep(3.5, 10000)
  out <- masque:::.bounded_stochastic_round(x, lo = 0L, hi = 10L)
  # Expectation: mean near 3.5 (half round to 3, half to 4)
  expect_equal(mean(out), 3.5, tolerance = 0.05)
})

test_that("synthesise_numeric_collaborate stays within observed range", {
  set.seed(1)
  x_obs <- rgamma(200, 2, 1)
  x_new <- masque:::synthesise_numeric_local(data.frame(z = x_obs))$z
  out <- masque:::synthesise_numeric_collaborate(x_obs, x_new)
  expect_true(all(out >= min(x_obs)) && all(out <= max(x_obs)))
})

test_that("synthesise_numeric_collaborate preserves integer class", {
  set.seed(1)
  x_obs <- sample(1L:20L, 200, replace = TRUE)
  expect_type(x_obs, "integer")
  x_new <- masque:::synthesise_numeric_local(data.frame(z = x_obs))$z
  out <- masque:::synthesise_numeric_collaborate(x_obs, x_new)
  expect_type(out, "integer")
  expect_true(all(out >= min(x_obs)) && all(out <= max(x_obs)))
})

test_that("synthesise_numeric_collaborate drops exact-match below local", {
  set.seed(1)
  x_obs <- rnorm(500)
  x_new_local <- masque:::synthesise_numeric_local(data.frame(z = x_obs))$z
  x_new_coll <- masque:::synthesise_numeric_collaborate(x_obs, x_new_local)

  exact_local <- mean(x_new_local == x_obs)
  exact_coll <- mean(x_new_coll == x_obs)
  # Collaborate should be effectively zero exact-match on continuous data
  expect_lt(exact_coll, exact_local + 1e-10)
  expect_lt(exact_coll, 0.01)
})

test_that("Collaborate mode lowers numeric exact-match in mask()", {
  set.seed(1)
  n <- 1000
  df <- data.frame(
    Rep = rep(1:4, n / 4),
    yield = rnorm(n, mean = 10, sd = 2),
    cov_n = rnorm(n),
    stringsAsFactors = FALSE
  )
  r <- propose_roles(df)
  r$role[r$col == "yield"] <- "outcome"

  # Rep is a numeric design-like covariate that audit_mask() flags HIGH
  # by design (collaborate-mode integer pass-through). The warning is
  # expected here; the assignment lives *inside* expect_warning() so
  # that testthat 3e returns the warning condition (rather than the
  # masque object) without breaking the downstream code.
  expect_warning(
    m <- mask(df, r, mode = "collaborate", seed = 1),
    "HIGH leakage"
  )
  audit <- audit_mask(m, print = FALSE)

  # Continuous outcome: exact_match_pct < 1
  yield_row <- audit[audit$col == "yield", ]
  expect_lt(yield_row$exact_match_pct, 1)
  expect_equal(yield_row$leakage_class, "low")

  # Continuous covariate: exact_match_pct < 5
  cov_row <- audit[audit$col == "cov_n", ]
  expect_lt(cov_row$exact_match_pct, 5)
})

test_that("Local mode is untouched by jitter (collaborate-only behaviour)", {
  set.seed(1)
  df <- data.frame(
    Rep = rep(1:4, 25),
    yield = rnorm(100),
    stringsAsFactors = FALSE
  )
  r <- propose_roles(df)
  r$role[r$col == "yield"] <- "outcome"

  m1 <- suppressWarnings(mask(df, r, mode = "local", seed = 1))
  m2 <- suppressWarnings(mask(df, r, mode = "local", seed = 1))
  expect_identical(synthetic(m1), synthetic(m2))
  # Local-mode yields come from the observed multiset
  expect_true(all(synthetic(m1)$yield %in% df$yield))
})

test_that("Mask() RNG hygiene holds with jitter in collaborate", {
  df <- data.frame(
    Rep = rep(1:4, 25),
    yield = rnorm(100),
    cov_n = rnorm(100),
    stringsAsFactors = FALSE
  )
  r <- propose_roles(df)
  r$role[r$col == "yield"] <- "outcome"

  # Capture seed AFTER setup (propose_roles and tibble setup may have
  # initialised internal state); the test is specifically about mask().
  set.seed(999)
  before <- .Random.seed
  # Expected HIGH-leakage warning on Rep; see jitter test above.
  expect_warning(
    m <- mask(df, r, mode = "collaborate", seed = 42),
    "HIGH leakage"
  )
  after <- .Random.seed
  expect_identical(before, after)
})

test_that("Collaborate mode preserves integer storage on int outcome columns", {
  set.seed(1)
  n <- 200
  df <- data.frame(
    Rep = rep(1:4, n / 4),
    grain_count = sample(50L:500L, n, replace = TRUE), # integer outcome
    cov_n = rnorm(n),
    stringsAsFactors = FALSE
  )
  expect_type(df$grain_count, "integer")
  r <- propose_roles(df)
  r$role[r$col == "grain_count"] <- "outcome"

  # Expected HIGH-leakage warning on Rep; see jitter test above.
  expect_warning(
    m <- mask(df, r, mode = "collaborate", seed = 1),
    "HIGH leakage"
  )
  expect_type(synthetic(m)$grain_count, "integer")
  rng <- range(synthetic(m)$grain_count, na.rm = TRUE)
  expect_gte(rng[1], min(df$grain_count))
  expect_lte(rng[2], max(df$grain_count))
})
