make_recipe <- function(mode = "collaborate", seed = 1) {
  r <- propose_roles(iris)
  r$role[r$col == "Sepal.Length"] <- "outcome"
  r$role[r$col == "Species"] <- "covariate"
  m <- if (mode == "local") {
    suppressWarnings(mask(iris, r, mode = "local", seed = seed))
  } else {
    mask(iris, r, mode = "collaborate", seed = seed)
  }
  recipe(m)
}

test_that("save_recipe + read_recipe round-trip is identity", {
  rec <- make_recipe()
  tmp <- tempfile(fileext = ".rds")
  save_recipe(rec, tmp)
  rec2 <- read_recipe(tmp)

  expect_identical(rec@masque_version, rec2@masque_version)
  expect_identical(rec@mode, rec2@mode)
  expect_identical(rec@seed, rec2@seed)
  expect_equal(rec@roles, rec2@roles)
  expect_identical(rec@level_maps, rec2@level_maps)
  expect_identical(rec@storage_classes, rec2@storage_classes)
  expect_identical(rec@factor_meta, rec2@factor_meta)
  expect_identical(rec@warnings, rec2@warnings)
  expect_identical(rec@integrity_fp, rec2@integrity_fp)
})

test_that("save_recipe file is much smaller than the raw data (1000x20 fixture)", {
  set.seed(0)
  df <- data.frame(
    Rep = rep(1:4, 250),
    block = rep(1:5, each = 200),
    Genotype = factor(rep(LETTERS[1:10], 100)),
    yield = rnorm(1000)
  )
  for (i in 1:16) df[[paste0("cov_", i)]] <- rnorm(1000)
  r <- propose_roles(df)
  r$role[r$col == "yield"] <- "outcome"
  m <- mask(df, r, mode = "collaborate", seed = 1)

  tmp <- tempfile(fileext = ".rds")
  save_recipe(recipe(m), tmp)
  sz <- file.info(tmp)$size
  # The recipe is metadata, not the data: it must serialize much smaller than the
  # raw data. Comparing against the data via the SAME serializer keeps this
  # robust to the absolute serialization-size changes that differ across R
  # versions (R-devel serialises this object several times larger than release R).
  data_rds <- tempfile(fileext = ".rds")
  saveRDS(df, data_rds)
  expect_lt(sz, file.info(data_rds)$size)
})

test_that("save_recipe errors on invalid inputs", {
  rec <- make_recipe()
  expect_error(save_recipe(list(), tempfile()), "must be a")
  expect_error(save_recipe(rec, ""), "non-empty")
  expect_error(save_recipe(rec, c("a", "b")), "single non-empty")
  expect_error(
    save_recipe(rec, tempfile(), include_simulator = "yes"),
    "single logical"
  )
})

test_that("read_recipe errors on missing file", {
  expect_error(read_recipe(tempfile(fileext = ".rds")), "not found")
})

test_that("read_recipe errors when file does not contain a masque_recipe", {
  tmp <- tempfile(fileext = ".rds")
  saveRDS(list(not_a_recipe = TRUE), tmp)
  expect_error(read_recipe(tmp), "does not contain")
})

test_that("read_recipe informs on version mismatch (not an error)", {
  rec <- make_recipe()
  # Tamper the recorded version to simulate an older write
  rec_old <- masque:::masque_recipe(
    masque_version  = "0.0.0.fakeold",
    created_at      = rec@created_at,
    mode            = rec@mode,
    seed            = rec@seed,
    roles           = rec@roles,
    column_name_map = rec@column_name_map,
    level_maps      = rec@level_maps,
    storage_classes = rec@storage_classes,
    factor_meta     = rec@factor_meta,
    warnings        = rec@warnings,
    integrity_fp    = rec@integrity_fp
  )
  tmp <- tempfile(fileext = ".rds")
  saveRDS(rec_old, tmp)
  expect_message(read_recipe(tmp), "0.0.0.fakeold")
})

test_that("include_simulator = TRUE is accepted (v0.2 no-op)", {
  rec <- make_recipe()
  tmp <- tempfile(fileext = ".rds")
  expect_no_error(save_recipe(rec, tmp, include_simulator = TRUE))
})
