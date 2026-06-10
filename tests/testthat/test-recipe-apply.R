make_collab_fixture_for_apply <- function() {
  set.seed(0)
  df <- data.frame(
    Rep = rep(1:4, 25),
    Genotype = factor(rep(LETTERS[1:5], each = 20)),
    yield = rnorm(100, mean = 10, sd = 2),
    cov_n = rnorm(100),
    cov_c = factor(sample(c("alpha", "beta", "gamma"), 100, replace = TRUE)),
    note = paste0("n_", seq_len(100)), # -> ignore
    stringsAsFactors = FALSE
  )
  r <- propose_roles(df)
  r$role[r$col == "yield"] <- "outcome"
  m <- mask(df, r, mode = "collaborate", seed = 1)
  list(df = df, m = m, rec = recipe(m))
}

test_that("apply_recipe renames treatment levels to opaque aliases", {
  f <- make_collab_fixture_for_apply()
  out <- apply_recipe(f$df, f$rec)

  expect_true(inherits(out, "tbl_df"))
  expect_true(all(grepl("^trt_\\d{3}$", as.character(out$Genotype))))
  # Should match the synthetic namespace's columns
  expect_setequal(names(out), names(synthetic(f$m)))
})

test_that("apply_recipe drops ignore columns under collaborate mode", {
  f <- make_collab_fixture_for_apply()
  out <- apply_recipe(f$df, f$rec)
  expect_false("note" %in% names(out))
})

test_that("apply_recipe leaves numeric columns unchanged in value", {
  f <- make_collab_fixture_for_apply()
  out <- apply_recipe(f$df, f$rec)
  expect_equal(out$yield, f$df$yield)
  expect_equal(out$cov_n, f$df$cov_n)
})

test_that("logical covariate aliases round-trip back to logical values", {
  set.seed(0)
  n <- 90
  df <- data.frame(
    Rep = rep(1:3, length.out = n),
    sprayed = rep(c(TRUE, FALSE, NA), length.out = n),
    yield = rnorm(n),
    stringsAsFactors = FALSE
  )
  r <- propose_roles(df, detect = FALSE)
  r$role[r$col == "yield"] <- "outcome"
  r$role[r$col == "sprayed"] <- "covariate"

  m <- mask(df, r, mode = "collaborate", seed = 1)
  s <- synthetic(m)
  fwd <- apply_recipe(df, recipe(m))
  back <- unmask(fwd, recipe(m))

  expect_type(s$sprayed, "character")
  expect_true(all(grepl("^sprayed_L\\d{3}$", stats::na.omit(s$sprayed))))
  expect_type(fwd$sprayed, "character")
  expect_identical(back$sprayed, df$sprayed)
})

test_that("apply_recipe errors when original misses a required column", {
  f <- make_collab_fixture_for_apply()
  df_short <- f$df[, setdiff(names(f$df), "Genotype")]
  expect_error(apply_recipe(df_short, f$rec), "missing column")
})

test_that("unmask on a data frame reverses apply_recipe (round-trip)", {
  f <- make_collab_fixture_for_apply()
  forward <- apply_recipe(f$df, f$rec)
  back <- unmask(forward, f$rec)

  # Treatment + categorical levels restored
  expect_equal(as.character(back$Genotype), as.character(f$df$Genotype))
  expect_equal(as.character(back$cov_c), as.character(f$df$cov_c))
  # Numerics unchanged
  expect_equal(back$yield, f$df$yield)
  expect_equal(back$cov_n, f$df$cov_n)
})

test_that("unmask on an atomic factor (single map) restores original labels", {
  f <- make_collab_fixture_for_apply()
  s <- synthetic(f$m)
  # Take treatment predictions in synthetic-space
  preds_synth <- s$Genotype[1:5]
  expect_true(all(grepl("^trt_\\d{3}$", as.character(preds_synth))))

  preds_orig <- unmask(preds_synth, f$rec, column = "Genotype")
  expect_true(all(as.character(preds_orig) %in% LETTERS[1:5]))
})

test_that("unmask on atomic vector errors when column is ambiguous", {
  f <- make_collab_fixture_for_apply()
  # f$rec has multiple level maps (Genotype + cov_c)
  preds <- factor(c("trt_001", "trt_002"))
  expect_error(unmask(preds, f$rec), "supply.*column")
})

test_that("unmask on atomic vector with a single-map recipe auto-selects", {
  set.seed(0)
  df <- data.frame(
    Rep = rep(1:4, 5),
    Genotype = factor(rep(LETTERS[1:5], 4)),
    yield = rnorm(20),
    stringsAsFactors = FALSE
  )
  r <- propose_roles(df)
  r$role[r$col == "yield"] <- "outcome"
  m <- mask(df, r, mode = "collaborate", seed = 1)
  rec <- recipe(m)
  # Only one level map (Genotype) since no categorical covariate, no ignore drop
  expect_length(rec@level_maps, 1L)
  pred <- factor(c("trt_001", "trt_002"))
  out <- unmask(pred, rec)
  expect_true(all(as.character(out) %in% LETTERS[1:5]))
})

test_that("unmask errors on unsupported type", {
  f <- make_collab_fixture_for_apply()
  expect_error(unmask(matrix(1:4, 2, 2), f$rec), "data frame or atomic")
})

test_that("apply_recipe + unmask is identity on local-mode recipe (no maps)", {
  set.seed(0)
  df <- data.frame(
    Rep = rep(1:4, 5),
    Genotype = factor(rep(LETTERS[1:5], 4)),
    yield = rnorm(20),
    stringsAsFactors = FALSE
  )
  r <- propose_roles(df)
  r$role[r$col == "yield"] <- "outcome"
  m <- suppressWarnings(mask(df, r, mode = "local", seed = 1))
  rec <- recipe(m)

  forward <- apply_recipe(df, rec)
  back <- unmask(forward, rec)

  expect_equal(as.data.frame(back), df)
})

# v0.4.1 contract tests: atomic pass-through, fail-closed unknown levels,
# NA-mask integrity check.

test_that("unmask passes through atomic numeric vectors unchanged", {
  f <- make_collab_fixture_for_apply()
  preds <- runif(20)
  expect_identical(unmask(preds, f$rec), preds)
})

test_that("unmask passes through atomic integer vectors unchanged", {
  f <- make_collab_fixture_for_apply()
  preds <- 1L:20L
  expect_identical(unmask(preds, f$rec), preds)
})

test_that("unmask passes through atomic logical vectors unchanged", {
  f <- make_collab_fixture_for_apply()
  preds <- c(TRUE, FALSE, NA, TRUE)
  expect_identical(unmask(preds, f$rec), preds)
})

test_that("unmask passes atomic numeric through with no level maps", {
  set.seed(0)
  df <- data.frame(
    Rep = rep(1:4, 25),
    yield = rnorm(100),
    stringsAsFactors = FALSE
  )
  r <- propose_roles(df, detect = FALSE)
  r$role[r$col == "yield"] <- "outcome"
  m <- suppressWarnings(mask(df, r, mode = "local", seed = 1))
  rec <- recipe(m)
  expect_length(rec@level_maps, 0L)
  preds <- runif(10)
  expect_identical(unmask(preds, rec), preds)
})

test_that("unmask errors when column argument is unknown to the recipe", {
  f <- make_collab_fixture_for_apply()
  expect_error(
    unmask(runif(5), f$rec, column = "definitely_not_a_column"),
    "not known"
  )
})

test_that("apply_recipe fail-closed on unknown original-namespace level", {
  f <- make_collab_fixture_for_apply()
  df2 <- f$df
  df2$Genotype <- as.character(df2$Genotype)
  df2$Genotype[1L] <- "UNSEEN_LEVEL"
  df2$Genotype <- factor(df2$Genotype)
  expect_error(
    apply_recipe(df2, f$rec, check_integrity = FALSE),
    "level map"
  )
})

test_that("unmask data frame: fail-closed on unknown synthetic alias", {
  f <- make_collab_fixture_for_apply()
  fwd <- apply_recipe(f$df, f$rec)
  fwd$Genotype <- as.character(fwd$Genotype)
  fwd$Genotype[1L] <- "trt_NOT_REAL"
  fwd$Genotype <- factor(fwd$Genotype)
  expect_error(unmask(fwd, f$rec), "level map")
})

test_that("apply_recipe enforces NA-mask integrity by default", {
  f <- make_collab_fixture_for_apply()
  df2 <- f$df
  df2$yield[1L] <- NA # flips the NA mask
  expect_error(
    apply_recipe(df2, f$rec),
    "integrity check failed"
  )
})

test_that("apply_recipe(check_integrity = FALSE) bypasses the check", {
  f <- make_collab_fixture_for_apply()
  df2 <- f$df
  df2$yield[1L] <- NA
  expect_silent(apply_recipe(df2, f$rec, check_integrity = FALSE))
})

test_that("apply_recipe integrity check passes on the unmodified original df", {
  f <- make_collab_fixture_for_apply()
  expect_silent(apply_recipe(f$df, f$rec)) # default check_integrity = TRUE
})
