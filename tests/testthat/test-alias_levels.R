test_that("alias_levels produces deterministic NNN aliases on a factor", {
  x <- factor(c("Bravo","Alpha","Charlie","Alpha","Bravo"))
  res <- masque:::alias_levels(x, prefix = "trtX")
  expect_true(is.factor(res$x))
  expect_true(all(grepl("^trtX\\d{3}$", as.character(levels(res$x)))))
  expect_equal(length(levels(res$x)), 3L)
  expect_named(res$map, sort(unique(as.character(x))))
})

test_that("alias_levels preserves per-level frequencies (factor)", {
  set.seed(0)
  x <- factor(sample(c("A","B","C"), 200, replace = TRUE))
  res <- masque:::alias_levels(x, prefix = "trtX")
  expect_equal(sort(as.vector(table(res$x))), sort(as.vector(table(x))))
})

test_that("alias_levels works on character input", {
  x <- c("X","Y","X","Z","Y")
  res <- masque:::alias_levels(x, prefix = "covLX")
  expect_true(is.character(res$x))
  expect_true(all(grepl("^covLX\\d{3}$", res$x)))
  expect_equal(length(unique(res$x)), 3L)
})

test_that("alias_levels preserves NAs", {
  x <- factor(c("A","B",NA,"A",NA,"B"))
  res <- masque:::alias_levels(x, prefix = "trtX")
  expect_equal(is.na(res$x), is.na(x))
})

test_that("alias_levels is invertible via res$map", {
  x <- factor(c("alpha","beta","gamma","alpha","beta"))
  res <- masque:::alias_levels(x, prefix = "trtX")
  inv <- setNames(names(res$map), unname(res$map))
  recon <- factor(inv[as.character(res$x)], levels = unname(inv))
  # Same labels-per-position
  expect_equal(as.character(recon), as.character(x))
})

test_that("alias_levels errors on bad prefix", {
  x <- factor(c("a","b"))
  expect_error(masque:::alias_levels(x, prefix = ""),    "non-empty")
  expect_error(masque:::alias_levels(x, prefix = NULL),  "non-empty")
  expect_error(masque:::alias_levels(x, prefix = c("a","b")), "non-empty")
})

test_that("alias_levels errors on non-categorical input", {
  expect_error(masque:::alias_levels(1:5, prefix = "x"), "supports")
})
