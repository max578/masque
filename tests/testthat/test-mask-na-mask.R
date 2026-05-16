test_that("NA mask is preserved cell-by-cell on numeric outcomes/covariates", {
  set.seed(0)
  n <- 100
  df <- data.frame(
    Rep   = rep(1:4, 25),
    yield = rnorm(n),
    cov1  = rnorm(n),
    cov2  = rnorm(n),
    stringsAsFactors = FALSE
  )
  # Deliberate NA pattern
  df$yield[c(1, 13, 50, 88)]  <- NA
  df$cov1 [c(2, 25, 75)]      <- NA
  df$cov2 [c(7, 33, 60, 99)]  <- NA

  r <- propose_roles(df)
  r$role[r$col == "yield"] <- "outcome"

  m <- suppressWarnings(mask(df, r, seed = 1))
  expect_equal(is.na(synthetic(m)), is.na(df), ignore_attr = TRUE)
})

test_that("NA mask preserved on categorical covariates too", {
  set.seed(0)
  df <- data.frame(
    Rep   = rep(1:4, 25),
    yield = rnorm(100),
    cat1  = factor(sample(letters[1:3], 100, replace = TRUE)),
    stringsAsFactors = FALSE
  )
  df$cat1[c(5, 15, 50, 99)] <- NA

  r <- propose_roles(df)
  r$role[r$col == "yield"] <- "outcome"

  m <- suppressWarnings(mask(df, r, seed = 1))
  expect_equal(is.na(synthetic(m)$cat1), is.na(df$cat1))
})

test_that("All-NA column survives mask without error", {
  set.seed(0)
  df <- data.frame(
    Rep    = rep(1:4, 5),
    yield  = rnorm(20),
    all_na = NA_real_,
    stringsAsFactors = FALSE
  )
  r <- propose_roles(df)
  r$role[r$col == "yield"] <- "outcome"

  expect_no_error(m <- suppressWarnings(mask(df, r, seed = 1)))
  expect_true(all(is.na(synthetic(m)$all_na)))
})
