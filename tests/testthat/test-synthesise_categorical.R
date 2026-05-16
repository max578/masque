test_that("Level set and per-level frequencies preserved (factor)", {
  set.seed(1)
  x <- factor(rep(c("A","B","C"), times = c(10, 20, 30)))
  y <- masque:::synthesise_categorical_local(x)
  expect_equal(as.vector(table(y)), as.vector(table(x)))
  expect_setequal(names(table(y)), names(table(x)))
  expect_identical(levels(y), levels(x))
})

test_that("Factor levels preserved even when some are absent in input", {
  x <- factor(c("A","A","B","B","B"), levels = c("A","B","C","D"))
  y <- masque:::synthesise_categorical_local(x)
  expect_identical(levels(y), levels(x))
})

test_that("Character vector type preserved", {
  set.seed(1)
  x <- sample(c("alpha","beta","gamma"), 100, replace = TRUE)
  y <- masque:::synthesise_categorical_local(x)
  expect_true(is.character(y))
  expect_equal(as.vector(table(y)), as.vector(table(x)))
  expect_setequal(names(table(y)), names(table(x)))
})

test_that("Logical vector type preserved", {
  set.seed(1)
  x <- sample(c(TRUE, FALSE), 100, replace = TRUE)
  y <- masque:::synthesise_categorical_local(x)
  expect_true(is.logical(y))
  expect_equal(sum(y), sum(x))
})

test_that("Row correspondence is broken (most rows differ on a balanced fixture)", {
  set.seed(1)
  x <- factor(rep(c("A","B"), each = 100))
  y <- masque:::synthesise_categorical_local(x)
  # With 50/50 split and a random permutation, expected ~50% match. Test < 95%.
  expect_lt(mean(as.character(x) == as.character(y)), 0.95)
})

test_that("Singleton and empty vectors pass through unchanged", {
  x_empty <- character(0)
  expect_identical(masque:::synthesise_categorical_local(x_empty), x_empty)

  x_one <- factor("only")
  expect_identical(masque:::synthesise_categorical_local(x_one), x_one)
})
