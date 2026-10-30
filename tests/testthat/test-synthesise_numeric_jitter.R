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

  # Rep stays a kept design column (graded low), so no HIGH warning.
  m <- mask(df, r, mode = "collaborate", seed = 1)
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

  # Capture seed AFTER setup (propose_roles and table setup may have
  # initialised internal state); the test is specifically about mask().
  set.seed(999)
  before <- .Random.seed
  m <- mask(df, r, mode = "collaborate", seed = 42)
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

  m <- mask(df, r, mode = "collaborate", seed = 1)
  expect_type(synthetic(m)$grain_count, "integer")
  rng <- range(synthetic(m)$grain_count, na.rm = TRUE)
  expect_gte(rng[1], min(df$grain_count))
  expect_lte(rng[2], max(df$grain_count))
})

test_that("collaborate keeps a 0/1 double column on its two values", {
  set.seed(1)
  x_obs <- as.numeric(rbinom(300, 1, 0.3))
  expect_type(x_obs, "double")
  x_new <- masque:::synthesise_numeric_local(data.frame(z = x_obs))$z
  out <- masque:::synthesise_numeric_collaborate(x_obs, x_new)
  expect_type(out, "double")
  expect_setequal(unique(out), c(0, 1))
  expect_identical(out, x_new)
})

test_that("collaborate does not flip a two-valued integer column", {
  set.seed(1)
  x_obs <- rbinom(300, 1, 0.3)
  x_new <- masque:::synthesise_numeric_local(data.frame(z = x_obs))$z
  out <- masque:::synthesise_numeric_collaborate(x_obs, x_new)
  expect_type(out, "integer")
  expect_identical(out, x_new)
})

test_that("collaborate keeps a whole-valued double column whole", {
  set.seed(1)
  x_obs <- c(as.numeric(sample(1:2000, 400, replace = TRUE)), NA)
  x_new <- masque:::synthesise_numeric_local(data.frame(z = x_obs))$z
  out <- masque:::synthesise_numeric_collaborate(x_obs, x_new)
  expect_type(out, "double")
  kept <- out[!is.na(out)]
  expect_true(all(kept == round(kept)))
  expect_true(all(kept >= 1 & kept <= 2000))
  expect_identical(is.na(out), is.na(x_new))
  # Still perturbed, not a copy of the local draw
  expect_lt(mean(out == x_new, na.rm = TRUE), 0.9)
})

test_that("collaborate mask() keeps whole-day and 0/1 double outcomes whole", {
  set.seed(1)
  n <- 400
  df <- data.frame(
    Rep = rep(1:4, n / 4),
    days = as.numeric(sample(10:3000, n, replace = TRUE)),
    flag = as.numeric(rbinom(n, 1, 0.4)),
    cov_n = rnorm(n),
    stringsAsFactors = FALSE
  )
  r <- propose_roles(df)
  r$role[r$col %in% c("days", "flag")] <- "outcome"
  m <- suppressWarnings(mask(df, r, mode = "collaborate", seed = 1))
  s <- synthetic(m)
  expect_type(s$days, "double")
  expect_true(all(s$days == round(s$days)))
  expect_setequal(unique(s$flag), c(0, 1))
})
