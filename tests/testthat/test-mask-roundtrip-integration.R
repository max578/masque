test_that("Round-trip: lm trained on synthetic, applied to original via apply_recipe", {
  set.seed(0)
  n <- 200
  df <- data.frame(
    Rep      = rep(1:4, n / 4),
    Genotype = factor(rep(LETTERS[1:5], each = n / 5)),
    yield    = rnorm(n, mean = 10, sd = 2),
    cov_n    = rnorm(n),
    stringsAsFactors = FALSE
  )
  r <- propose_roles(df)
  r$role[r$col == "yield"] <- "outcome"

  m   <- mask(df, r, mode = "collaborate", seed = 1)
  s   <- synthetic(m)
  rec <- recipe(m)

  # Train a trivial linear model against the synthetic namespace
  fit <- stats::lm(yield ~ Genotype + cov_n, data = s)

  # Apply the model to the original via apply_recipe (renames Genotype levels)
  df_in_synth <- apply_recipe(df, rec)
  preds <- stats::predict(fit, newdata = df_in_synth)

  expect_equal(length(preds), nrow(df))
  expect_false(any(is.na(preds)))
  expect_true(all(is.finite(preds)))
})

test_that("Round-trip: classifier predicts treatment, unmask restores labels", {
  set.seed(0)
  n <- 200
  df <- data.frame(
    Rep      = rep(1:4, n / 4),
    Genotype = factor(rep(LETTERS[1:5], each = n / 5)),
    yield    = rnorm(n, mean = 10, sd = 2),
    stringsAsFactors = FALSE
  )
  r <- propose_roles(df)
  r$role[r$col == "yield"] <- "outcome"

  m   <- mask(df, r, mode = "collaborate", seed = 1)
  s   <- synthetic(m)
  rec <- recipe(m)

  # Mock a "classifier" that emits factor labels in synthetic-namespace
  pred_synth <- s$Genotype[seq_len(20)]
  expect_true(all(grepl("^trt_\\d{3}$", as.character(pred_synth))))

  pred_orig <- unmask(pred_synth, rec, column = "Genotype")
  expect_true(all(as.character(pred_orig) %in% LETTERS[1:5]))
  expect_setequal(levels(pred_orig), LETTERS[1:5])
})

test_that("Round-trip: save_recipe -> read_recipe -> apply still works (cross-process simulation)", {
  set.seed(0)
  df <- data.frame(
    Rep      = rep(1:4, 25),
    Genotype = factor(rep(LETTERS[1:5], each = 20)),
    yield    = rnorm(100),
    stringsAsFactors = FALSE
  )
  r <- propose_roles(df)
  r$role[r$col == "yield"] <- "outcome"

  m <- mask(df, r, mode = "collaborate", seed = 1)

  tmp <- tempfile(fileext = ".rds")
  save_recipe(recipe(m), tmp)
  rec2 <- read_recipe(tmp)

  forward <- apply_recipe(df, rec2)
  back    <- unmask(forward, rec2)
  expect_equal(as.character(back$Genotype), as.character(df$Genotype))
})

test_that("Round-trip on MET tab_04 (skip if .fst fixture absent)", {
  skip_on_cran()
  skip_if_not_installed("fst")
  fpath <- normalizePath("../../../fst_00_dataset_tab_04.fst", mustWork = FALSE)
  skip_if_not(file.exists(fpath), sprintf("Local-only MET fixture not at %s", fpath))

  df <- fst::read_fst(fpath, as.data.table = FALSE)
  # detect = FALSE: see note in test-mask-end-to-end.R; multi-treatment
  # masking is roadmap, not v0.4.x.
  r  <- propose_roles(df, detect = FALSE)
  r$role[r$col == "G_Yield_Tn_ha"]  <- "outcome"
  r$role[r$col == "Cultivar_Habit"] <- "covariate"

  m   <- suppressWarnings(mask(df, r, mode = "collaborate", seed = 1))
  rec <- recipe(m)

  fwd <- apply_recipe(df, rec)
  expect_equal(nrow(fwd), nrow(df))
  expect_true("trt_001" %in% as.character(fwd$Genotype))

  back <- unmask(fwd, rec)
  expect_equal(as.character(back$Genotype), as.character(df$Genotype))
  expect_equal(as.character(back$M_STATE),  as.character(df$M_STATE))
})
