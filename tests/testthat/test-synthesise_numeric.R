test_that("synthesise_numeric_local returns observed-only values (type = 1)", {
  set.seed(1)
  x <- data.frame(a = rnorm(500))
  y <- masque:::synthesise_numeric_local(x)
  expect_true(all(y$a %in% x$a))
})

test_that("synthesise_numeric_local preserves range bounds", {
  set.seed(1)
  x <- data.frame(a = rgamma(500, 2, 1), b = rnorm(500))
  y <- masque:::synthesise_numeric_local(x)
  expect_true(min(y$a) >= min(x$a) && max(y$a) <= max(x$a))
  expect_true(min(y$b) >= min(x$b) && max(y$b) <= max(x$b))
})

test_that("Spearman correlation roughly preserved on multivariate input", {
  set.seed(1)
  n <- 2000
  z <- rnorm(n)
  x <- data.frame(
    a = z + rnorm(n, sd = 0.3),
    b = 2 * z + rnorm(n, sd = 0.7),
    c = rnorm(n)
  )
  y <- masque:::synthesise_numeric_local(x)

  cor_x <- stats::cor(x, method = "spearman")
  cor_y <- stats::cor(y, method = "spearman")
  expect_lt(max(abs(cor_x - cor_y)), 0.15)
})

test_that("Single-column path returns correct dimensions and values", {
  set.seed(1)
  x <- data.frame(z = 1:50)
  y <- masque:::synthesise_numeric_local(x)
  expect_equal(dim(y), c(50, 1))
  expect_identical(names(y), "z")
  expect_true(all(y$z %in% x$z))
})

test_that("Integer columns stay integer through synthesis", {
  set.seed(1)
  x <- data.frame(
    a = sample(1:20, 200, replace = TRUE),
    b = rnorm(200)
  )
  expect_true(is.integer(x$a))
  y <- masque:::synthesise_numeric_local(x)
  expect_true(is.integer(y$a))
  expect_true(is.double(y$b))
})

test_that("Rank-deficient Σ is regularised, no error", {
  set.seed(1)
  z <- rnorm(200)
  x <- data.frame(a = z, b = 2 * z, c = rnorm(200))
  expect_no_error(y <- masque:::synthesise_numeric_local(x))
  expect_equal(nrow(y), 200)
  expect_equal(ncol(y), 3)
})

test_that("Zero-variance column passes through (no synthesis)", {
  set.seed(1)
  x <- data.frame(constant = rep(5, 100), v = rnorm(100))
  y <- masque:::synthesise_numeric_local(x)
  expect_true(all(y$constant == 5))
  expect_equal(length(unique(y$v)) > 1, TRUE)
})

test_that("Non-numeric input errors", {
  bad <- data.frame(a = letters[1:5], b = 1:5, stringsAsFactors = FALSE)
  expect_error(masque:::synthesise_numeric_local(bad), "Non-numeric")
})

test_that("Empty data frame returns empty", {
  out <- masque:::synthesise_numeric_local(data.frame())
  expect_equal(nrow(out), 0L)
  expect_equal(ncol(out), 0L)
})
