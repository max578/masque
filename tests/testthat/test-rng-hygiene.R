make_outcome_roles <- function(df, outcome_col) {
  r <- propose_roles(df)
  r$role[r$col == outcome_col] <- "outcome"
  r
}

test_that("mask() does not mutate the caller's .Random.seed (seed = NULL)", {
  r <- make_outcome_roles(iris, "Sepal.Length")

  set.seed(123)
  before <- .Random.seed
  m <- mask(iris, r)
  after <- .Random.seed

  expect_identical(before, after)
  expect_s3_class(m, "masque")
})

test_that("mask() does not mutate the caller's .Random.seed (seed = 42)", {
  r <- make_outcome_roles(iris, "Sepal.Length")

  set.seed(456)
  before <- .Random.seed
  m <- mask(iris, r, seed = 42)
  after <- .Random.seed

  expect_identical(before, after)
})

test_that("mask() is reproducible with the same seed", {
  r <- make_outcome_roles(iris, "Sepal.Length")
  m1 <- mask(iris, r, seed = 99)
  m2 <- mask(iris, r, seed = 99)
  expect_identical(m1$synthetic, m2$synthetic)
})

test_that("mask() differs between distinct seeds", {
  r <- make_outcome_roles(iris, "Sepal.Length")
  m1 <- mask(iris, r, seed = 1)
  m2 <- mask(iris, r, seed = 2)
  expect_false(identical(m1$synthetic, m2$synthetic))
})

test_that("with_rng_state errors on bad seed type", {
  # Internal helper; test via mask()
  r <- make_outcome_roles(iris, "Sepal.Length")
  expect_error(mask(iris, r, seed = "not-a-number"), "must be a single integer")
  expect_error(mask(iris, r, seed = c(1, 2)),         "must be a single integer")
  expect_error(mask(iris, r, seed = NA_integer_),     "must be a single integer")
})
