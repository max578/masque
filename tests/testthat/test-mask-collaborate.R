make_collab_fixture <- function(n = 100, seed = 0) {
  set.seed(seed)
  df <- data.frame(
    Rep = rep(1:4, n / 4),
    Genotype = factor(rep(LETTERS[1:5], each = n / 5)),
    yield = rnorm(n, mean = 10, sd = 2),
    cov_n = rnorm(n),
    cov_cat = factor(sample(c("alpha", "beta", "gamma"), n, replace = TRUE)),
    notes_id = paste0("note_", seq_len(n)), # auto-ignored (free-text)
    stringsAsFactors = FALSE
  )
  r <- propose_roles(df)
  r$role[r$col == "yield"] <- "outcome"
  list(df = df, roles = r)
}

test_that("Collaborate mode runs end-to-end without error", {
  f <- make_collab_fixture()
  expect_no_error(m <- mask(f$df, f$roles, mode = "collaborate", seed = 1))
  expect_true(inherits(m, "masque::masque"))
})

test_that("Treatment column is opaque-aliased in collaborate mode", {
  f <- make_collab_fixture()
  m <- mask(f$df, f$roles, mode = "collaborate", seed = 1)
  s <- synthetic(m)

  # Original Genotype was A-E. After aliasing, levels are trt_NNN.
  expect_true(all(grepl("^trt_\\d{3}$", as.character(levels(s$Genotype)))))
  expect_equal(length(levels(s$Genotype)), length(levels(f$df$Genotype)))
  # No original label leaks into synthetic
  expect_false(any(as.character(s$Genotype) %in% LETTERS[1:5]))
  # Recipe holds the map
  rec <- recipe(m)
  expect_true("Genotype" %in% names(rec@level_maps))
  map <- rec@level_maps$Genotype
  expect_setequal(names(map), LETTERS[1:5])
  expect_true(all(grepl("^trt_\\d{3}$", unname(map))))
})

test_that("Categorical covariate is opaque-aliased in collaborate mode", {
  f <- make_collab_fixture()
  m <- mask(f$df, f$roles, mode = "collaborate", seed = 1)
  s <- synthetic(m)

  expect_true(all(grepl("^cov_cat_L\\d{3}$", as.character(levels(s$cov_cat)))))
  expect_false(any(as.character(s$cov_cat) %in% c("alpha", "beta", "gamma")))
  rec <- recipe(m)
  expect_true("cov_cat" %in% names(rec@level_maps))
  expect_setequal(names(rec@level_maps$cov_cat), c("alpha", "beta", "gamma"))
})

test_that("Treatment + categorical level frequencies survive aliasing", {
  f <- make_collab_fixture()
  m <- mask(f$df, f$roles, mode = "collaborate", seed = 1)
  s <- synthetic(m)
  expect_equal(
    sort(as.vector(table(s$Genotype))),
    sort(as.vector(table(f$df$Genotype)))
  )
  expect_equal(
    sort(as.vector(table(s$cov_cat))),
    sort(as.vector(table(f$df$cov_cat)))
  )
})

test_that("Design columns remain byte-identical in collaborate mode", {
  f <- make_collab_fixture()
  m <- mask(f$df, f$roles, mode = "collaborate", seed = 1)
  expect_identical(synthetic(m)$Rep, f$df$Rep)
})

test_that("Ignore columns are dropped in collaborate mode", {
  f <- make_collab_fixture()
  m <- mask(f$df, f$roles, mode = "collaborate", seed = 1)
  s <- synthetic(m)
  expect_false("notes_id" %in% names(s))
  expect_equal(ncol(s), ncol(f$df) - 1L)
  expect_true(any(grepl("Dropped", recipe(m)@warnings)))
})

test_that("Collaborate mode does NOT emit the local-mode warning", {
  f <- make_collab_fixture()
  expect_no_warning(mask(f$df, f$roles, mode = "collaborate", seed = 1))
})

test_that("Local-mode optional permute via roles$mask_levels = 'permute'", {
  set.seed(0)
  df <- data.frame(
    Rep = rep(1:4, 5),
    Genotype = factor(rep(LETTERS[1:5], 4)),
    yield = rnorm(20),
    stringsAsFactors = FALSE
  )
  r <- propose_roles(df)
  r$role[r$col == "yield"] <- "outcome"
  r$mask_levels <- "off"
  r$mask_levels[r$col == "Genotype"] <- "permute"

  m <- suppressWarnings(mask(df, r, mode = "local", seed = 1))
  rec <- recipe(m)
  expect_true("Genotype" %in% names(rec@level_maps))
  # Permutation keeps the same vocabulary (just shuffled assignment)
  map <- rec@level_maps$Genotype
  expect_setequal(names(map), LETTERS[1:5])
  expect_setequal(unname(map), LETTERS[1:5])
})
