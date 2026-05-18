test_that("mask() returns an S7 masque object with synthetic + recipe", {
  set.seed(0)
  df <- data.frame(
    Rep      = rep(1:4, 25),
    Genotype = factor(rep(LETTERS[1:5], each = 20)),
    yield    = rnorm(100, mean = 10, sd = 2),
    cov_n    = rnorm(100),
    cov_c    = factor(sample(c("X","Y"), 100, replace = TRUE)),
    stringsAsFactors = FALSE
  )
  r <- propose_roles(df)
  r$role[r$col == "yield"] <- "outcome"

  m <- suppressWarnings(mask(df, r, seed = 42))

  expect_true(inherits(m, "masque::masque"))
  expect_true(inherits(synthetic(m), "tbl_df"))
  expect_true(inherits(recipe(m), "masque::masque_recipe"))
  expect_equal(m@mode, "local")
  expect_null(m@audit)
  expect_equal(recipe(m)@seed, 42L)
})

test_that("mask() preserves design, treatment pass-through; outcome stays in observed range", {
  set.seed(0)
  df <- data.frame(
    Rep      = rep(1:4, 25),
    Genotype = factor(rep(LETTERS[1:5], each = 20)),
    yield    = rnorm(100, mean = 10, sd = 2),
    stringsAsFactors = FALSE
  )
  r <- propose_roles(df)
  r$role[r$col == "yield"] <- "outcome"

  m <- suppressWarnings(mask(df, r, seed = 42))
  s <- synthetic(m)

  expect_identical(s$Rep, df$Rep)
  expect_identical(s$Genotype, df$Genotype)
  expect_true(min(s$yield, na.rm = TRUE) >= min(df$yield, na.rm = TRUE))
  expect_true(max(s$yield, na.rm = TRUE) <= max(df$yield, na.rm = TRUE))
})

test_that("Categorical covariate frequencies are preserved", {
  set.seed(0)
  df <- data.frame(
    Rep   = rep(1:4, 25),
    yield = rnorm(100),
    cat_c = factor(rep(c("L1","L2","L3"), length.out = 100)),
    stringsAsFactors = FALSE
  )
  r <- propose_roles(df)
  r$role[r$col == "yield"] <- "outcome"

  m <- suppressWarnings(mask(df, r, seed = 1))
  s <- synthetic(m)
  expect_equal(as.vector(table(s$cat_c)), as.vector(table(df$cat_c)))
  expect_setequal(names(table(s$cat_c)), names(table(df$cat_c)))
})

test_that("mask(mode = 'local') prints the not-for-sharing warning", {
  r <- propose_roles(iris)
  r$role[r$col == "Sepal.Length"] <- "outcome"
  expect_warning(mask(iris, r), "local mode")
})

test_that("mask() errors on non-data-frame input", {
  r <- propose_roles(iris)
  r$role[r$col == "Sepal.Length"] <- "outcome"
  expect_error(mask(list(), r), "must be a data frame")
})

test_that("mask() errors propagated from roles_validate (no outcome)", {
  r <- propose_roles(iris)
  expect_error(mask(iris, r), "outcome")
})

test_that("roles_validate errors on non-numeric outcome (semantic check)", {
  r <- propose_roles(iris)
  r$role[r$col == "Species"] <- "outcome"
  expect_error(roles_validate(r), "Non-numeric")
})

# Real MET fixture smoke test (skipped under R CMD check) --------------------

test_that("mask() runs end-to-end on MET tab_04 (skip if .fst fixture absent)", {
  skip_on_cran()
  skip_if_not_installed("fst")
  fpath <- normalizePath("../../../fst_00_dataset_tab_04.fst", mustWork = FALSE)
  skip_if_not(file.exists(fpath), sprintf("Local-only MET fixture not at %s", fpath))

  df <- fst::read_fst(fpath, as.data.table = FALSE)
  # detect = FALSE: v0.2.x byte-stable role proposal. With detect = TRUE
  # (the v0.3+ default), the MET fixture's design-detection legitimately
  # labels multiple columns as treatment-like, which hits the single-
  # treatment guard in roles_validate(). Multi-treatment masking is on
  # the roadmap (see vignette("roadmap")).
  r  <- propose_roles(df, detect = FALSE)
  r$role[r$col == "G_Yield_Tn_ha"]  <- "outcome"
  r$role[r$col == "Cultivar_Habit"] <- "covariate"

  m <- suppressWarnings(mask(df, r, seed = 1))
  s <- synthetic(m)

  expect_true(inherits(m, "masque::masque"))
  expect_equal(nrow(s), nrow(df))
  expect_equal(ncol(s), ncol(df))
  expect_identical(s$Rep,    df$Rep)
  expect_identical(s$Row,    df$Row)
  expect_identical(s$Column, df$Column)
  expect_equal(is.na(s$G_Yield_Tn_ha), is.na(df$G_Yield_Tn_ha))
})
