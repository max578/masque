test_that("permute_levels returns same vocabulary, shuffled assignment", {
  set.seed(1)
  x <- factor(rep(LETTERS[1:5], each = 10))
  res <- masque:::permute_levels(x)
  expect_setequal(levels(res$x), levels(x))
  expect_setequal(names(res$map), levels(x))
  expect_setequal(unname(res$map), levels(x))
  # Same per-level frequencies as input mapped through map
  expect_equal(sort(as.vector(table(res$x))), sort(as.vector(table(x))))
})

test_that("permute_levels map is bijective", {
  set.seed(1)
  x <- factor(LETTERS[1:8])
  res <- masque:::permute_levels(x)
  expect_equal(length(unique(unname(res$map))), length(unique(names(res$map))))
})

test_that("permute_levels handles character input", {
  set.seed(1)
  x <- c("alpha", "beta", "gamma", "alpha", "beta")
  res <- masque:::permute_levels(x)
  expect_setequal(names(res$map), unique(x))
  expect_setequal(unname(res$map), unique(x))
})

test_that("permute_levels preserves NAs (character)", {
  x <- c("A", "B", NA, "A", NA)
  res <- masque:::permute_levels(x)
  expect_equal(is.na(res$x), is.na(x))
})

test_that("permute_levels singleton-vocab is identity", {
  x <- factor(c("only", "only", "only"))
  res <- masque:::permute_levels(x)
  expect_identical(res$x, x)
  expect_equal(names(res$map), "only")
  expect_equal(unname(res$map), "only")
})

test_that("permute_levels errors on non-categorical input", {
  expect_error(masque:::permute_levels(1:5), "supports")
})
