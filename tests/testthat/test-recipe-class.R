test_that("recipe() returns a masque_recipe with required properties", {
  r <- propose_roles(iris)
  r$role[r$col == "Sepal.Length"] <- "outcome"
  m <- suppressWarnings(mask(iris, r, seed = 1))

  rec <- recipe(m)

  expect_true(inherits(rec, "masque::masque_recipe"))
  expect_true(nzchar(rec@masque_version))
  expect_true(inherits(rec@created_at, "POSIXct"))
  expect_equal(rec@mode, "local")
  expect_equal(rec@seed, 1L)
  expect_s3_class(rec@roles, "data.frame")
  expect_equal(nrow(rec@roles), ncol(iris))
  expect_true(is.list(rec@level_maps))
  expect_true(is.list(rec@storage_classes))
  expect_true(is.list(rec@factor_meta))
  expect_match(rec@integrity_fp, "^[0-9a-f]{64}$") # SHA-256 hex
})

test_that("integrity_fp matches digest of the original NA mask", {
  r <- propose_roles(iris)
  r$role[r$col == "Sepal.Length"] <- "outcome"
  m <- suppressWarnings(mask(iris, r, seed = 1))

  expected <- digest::digest(is.na(iris), algo = "sha256")
  expect_equal(recipe(m)@integrity_fp, expected)
})

test_that("factor_meta records levels and ordered status", {
  r <- propose_roles(iris)
  r$role[r$col == "Sepal.Length"] <- "outcome"
  m <- suppressWarnings(mask(iris, r, seed = 1))

  fm <- recipe(m)@factor_meta
  expect_true("Species" %in% names(fm))
  expect_equal(fm$Species$levels, levels(iris$Species))
  expect_false(fm$Species$ordered)
})

test_that("Local mode keeps level_maps empty by default", {
  r <- propose_roles(iris)
  r$role[r$col == "Sepal.Length"] <- "outcome"
  m <- suppressWarnings(mask(iris, r, seed = 1, mode = "local"))
  expect_length(recipe(m)@level_maps, 0L)
})

test_that("Local mode warning is captured into recipe@warnings", {
  r <- propose_roles(iris)
  r$role[r$col == "Sepal.Length"] <- "outcome"
  m <- suppressWarnings(mask(iris, r, seed = 1, mode = "local"))
  expect_true(any(grepl("local mode", recipe(m)@warnings)))
})

test_that("synthetic() and recipe() reject non-masque inputs", {
  expect_error(synthetic(list(synthetic = iris)), "must be a")
  expect_error(recipe(list()), "must be a")
})
