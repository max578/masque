test_that("mask() returns an S7 masque object with synthetic + recipe", {
  set.seed(0)
  df <- data.frame(
    Rep = rep(1:4, 25),
    Genotype = factor(rep(LETTERS[1:5], each = 20)),
    yield = rnorm(100, mean = 10, sd = 2),
    cov_n = rnorm(100),
    cov_c = factor(sample(c("X", "Y"), 100, replace = TRUE)),
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

test_that("mask() keeps design + treatment; outcome stays in range", {
  set.seed(0)
  df <- data.frame(
    Rep = rep(1:4, 25),
    Genotype = factor(rep(LETTERS[1:5], each = 20)),
    yield = rnorm(100, mean = 10, sd = 2),
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
    Rep = rep(1:4, 25),
    yield = rnorm(100),
    cat_c = factor(rep(c("L1", "L2", "L3"), length.out = 100)),
    stringsAsFactors = FALSE
  )
  r <- propose_roles(df)
  r$role[r$col == "yield"] <- "outcome"

  m <- suppressWarnings(mask(df, r, seed = 1))
  s <- synthetic(m)
  expect_equal(as.vector(table(s$cat_c)), as.vector(table(df$cat_c)))
  expect_setequal(names(table(s$cat_c)), names(table(df$cat_c)))
})

test_that("Date and datetime covariates are retained with class and NA mask", {
  set.seed(0)
  n <- 60
  df <- data.frame(
    Rep = rep(1:3, length.out = n),
    sowing_date = as.Date("2026-04-01") + rep(0:9, length.out = n),
    measured_at = as.POSIXct("2026-04-01 08:00:00", tz = "UTC") +
      seq_len(n) * 3600,
    yield = rnorm(n),
    stringsAsFactors = FALSE
  )
  df$sowing_date[c(3, 17)] <- NA
  df$measured_at[c(5, 23)] <- NA

  r <- propose_roles(df, detect = FALSE)
  r$role[r$col == "yield"] <- "outcome"

  m <- suppressWarnings(mask(df, r, mode = "collaborate", seed = 1))
  s <- synthetic(m)

  expect_true("sowing_date" %in% names(s))
  expect_true(inherits(s$sowing_date, "Date"))
  expect_true(inherits(s$measured_at, "POSIXct"))
  expect_equal(is.na(s$sowing_date), is.na(df$sowing_date))
  expect_equal(is.na(s$measured_at), is.na(df$measured_at))
  expect_equal(
    sort(as.character(stats::na.omit(s$sowing_date))),
    sort(as.character(stats::na.omit(df$sowing_date)))
  )
  expect_equal(
    sort(as.character(stats::na.omit(s$measured_at))),
    sort(as.character(stats::na.omit(df$measured_at)))
  )
})

test_that("Explicit keep columns pass through collaborate mode unchanged", {
  set.seed(0)
  df <- data.frame(
    Rep = rep(1:4, 10),
    site_label = rep(c("north", "south"), 20),
    yield = rnorm(40),
    stringsAsFactors = FALSE
  )
  r <- propose_roles(df, detect = FALSE)
  r$role[r$col == "yield"] <- "outcome"
  r <- set_role(r, "site_label", action = "keep")

  m <- mask(df, r, mode = "collaborate", seed = 1)
  s <- synthetic(m)
  rec <- recipe(m)
  fwd <- apply_recipe(df, rec)

  expect_identical(s$site_label, df$site_label)
  expect_identical(fwd$site_label, df$site_label)
  expect_match(
    m@audit$notes[m@audit$col == "site_label"],
    "kept as-is"
  )
  expect_equal(
    m@audit$leakage_class[m@audit$col == "site_label"],
    "medium"
  )
})

test_that("mask(mode = 'local') emits no advisory warning (channel separation)", {
  r <- propose_roles(iris)
  r$role[r$col == "Sepal.Length"] <- "outcome"
  expect_no_warning(m <- mask(iris, r, seed = 1))
  # The reminder is recorded on the recipe, not signalled as a warning.
  expect_true(any(grepl("local mode", recipe(m)@warnings)))
})

test_that("mask() errors on non-data-frame input", {
  r <- propose_roles(iris)
  r$role[r$col == "Sepal.Length"] <- "outcome"
  expect_error(mask(list(), r), "must be a data frame")
})

test_that("mask() no longer requires an outcome column", {
  r <- propose_roles(iris)
  expect_true(all(r$role != "outcome"))
  m <- suppressWarnings(mask(iris, r, seed = 1))
  s <- synthetic(m)
  expect_equal(dim(s), dim(iris))
  # All four numerics are covariates: still re-simulated jointly.
  expect_false(identical(s$Sepal.Width, iris$Sepal.Width))
})

test_that("roles_validate errors on non-numeric scrambled outcome", {
  r <- propose_roles(iris)
  r <- set_role(r, "Species", role = "outcome", action = "scramble")
  expect_error(roles_validate(r), "outcomes can be scrambled")
})

# Real MET fixture smoke test (skipped under R CMD check) --------------------

test_that("mask() runs end-to-end on MET tab_04 (skip if fixture absent)", {
  skip_on_cran()
  skip_if_not_installed("fst")
  fpath <- normalizePath("../../../fst_00_dataset_tab_04.fst", mustWork = FALSE)
  skip_if_not(
    file.exists(fpath),
    sprintf("Local-only MET fixture not at %s", fpath)
  )

  df <- fst::read_fst(fpath, as.data.table = FALSE)
  # detect = FALSE: v0.2.x byte-stable role proposal, kept here so this
  # fixture exercises the single-treatment path. With detect = TRUE (the
  # v0.3+ default) the MET fixture's design-detection labels several columns
  # as treatment-like; joint-treatment masking handles that and is covered in
  # test-mask-multi-treatment.R.
  r <- propose_roles(df, detect = FALSE)
  r$role[r$col == "G_Yield_Tn_ha"] <- "outcome"
  r$role[r$col == "Cultivar_Habit"] <- "covariate"

  m <- suppressWarnings(mask(df, r, seed = 1))
  s <- synthetic(m)

  expect_true(inherits(m, "masque::masque"))
  expect_equal(nrow(s), nrow(df))
  # PII-suspected columns are dropped in both modes since the two-axis
  # roles model; everything else survives.
  dropped <- r$col[r$action == "drop"]
  expect_equal(ncol(s), ncol(df) - length(dropped))
  expect_true(all(setdiff(names(df), dropped) %in% names(s)))
  expect_identical(s$Rep, df$Rep)
  expect_identical(s$Row, df$Row)
  expect_identical(s$Column, df$Column)
  expect_equal(is.na(s$G_Yield_Tn_ha), is.na(df$G_Yield_Tn_ha))
})
