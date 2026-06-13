# Conditional clone mode: the synthetic must preserve the
# treatment -> outcome relationship, where the default (marginal /
# structural) clone provably does not.

# A two-arm trial with a strong, known treatment effect on a numeric
# outcome, plus a numeric covariate that is genuinely unrelated to the
# arm. Returns the frame, a roles table, and the true OLS effect.
make_effect_fixture <- function(n = 600, effect = 5, sd = 2, seed = 42) {
  set.seed(seed)
  trt <- factor(rep(c("ctrl", "treat"), each = n / 2))
  yield <- 10 + effect * (trt == "treat") + stats::rnorm(n, sd = sd)
  cov_n <- stats::rnorm(n) # unrelated to the arm
  df <- data.frame(
    Genotype = trt,
    yield = yield,
    cov_n = cov_n,
    stringsAsFactors = FALSE
  )
  r <- propose_roles(df, detect = FALSE)
  r$role[r$col == "Genotype"] <- "treatment"
  r$role[r$col == "yield"] <- "outcome"
  r$role[r$col == "cov_n"] <- "covariate"
  r <- set_role(r, "Genotype", action = "scramble")
  true_eff <- stats::coef(stats::lm(yield ~ Genotype, df))[["Genotypetreat"]]
  list(df = df, roles = r, true_eff = true_eff)
}

.arm_effect <- function(synth) {
  stats::coef(stats::lm(yield ~ Genotype, synth))[["Genotypetreat"]]
}

test_that("conditional clone preserves the treatment -> outcome effect", {
  f <- make_effect_fixture()
  m <- suppressWarnings(
    mask(f$df, f$roles, mode = "local", seed = 1, conditional = TRUE)
  )
  eff <- .arm_effect(synthetic(m))
  # Within sampling tolerance of the real effect (true ~ 5).
  expect_equal(eff, f$true_eff, tolerance = 0.4)
})

test_that("marginal-only clone destroys the treatment -> outcome effect", {
  f <- make_effect_fixture()
  m <- suppressWarnings(
    mask(f$df, f$roles, mode = "local", seed = 1, conditional = FALSE)
  )
  eff <- .arm_effect(synthetic(m))
  # The pooled copula severs the relationship: the estimated effect
  # collapses toward zero, far from the true ~ 5.
  expect_lt(abs(eff), abs(f$true_eff) / 2)
})

test_that("conditional beats marginal on the same fixture and seed", {
  f <- make_effect_fixture()
  m_marg <- suppressWarnings(
    mask(f$df, f$roles, mode = "local", seed = 1, conditional = FALSE)
  )
  m_cond <- suppressWarnings(
    mask(f$df, f$roles, mode = "local", seed = 1, conditional = TRUE)
  )
  err_marg <- abs(.arm_effect(synthetic(m_marg)) - f$true_eff)
  err_cond <- abs(.arm_effect(synthetic(m_cond)) - f$true_eff)
  expect_lt(err_cond, err_marg)
})

test_that("conditional clone still preserves the global marginal", {
  f <- make_effect_fixture()
  m <- suppressWarnings(
    mask(f$df, f$roles, mode = "local", seed = 1, conditional = TRUE)
  )
  s <- synthetic(m)
  # Pooled mean and spread of the outcome are still recovered closely.
  expect_equal(mean(s$yield), mean(f$df$yield), tolerance = 0.3)
  expect_equal(stats::sd(s$yield), stats::sd(f$df$yield), tolerance = 0.3)
})

test_that("conditional flag and conditioning columns are recorded on the recipe", {
  f <- make_effect_fixture()
  m <- suppressWarnings(
    mask(f$df, f$roles, mode = "local", seed = 1, conditional = TRUE)
  )
  rec <- recipe(m)
  expect_true(rec@conditional)
  expect_identical(rec@conditioning_cols, "Genotype")

  m0 <- suppressWarnings(
    mask(f$df, f$roles, mode = "local", seed = 1, conditional = FALSE)
  )
  rec0 <- recipe(m0)
  expect_false(rec0@conditional)
  expect_identical(rec0@conditioning_cols, character())
})

test_that("conditional default is FALSE and leaves existing output unchanged", {
  f <- make_effect_fixture()
  m_default <- suppressWarnings(mask(f$df, f$roles, mode = "local", seed = 1))
  m_explicit <- suppressWarnings(
    mask(f$df, f$roles, mode = "local", seed = 1, conditional = FALSE)
  )
  expect_identical(synthetic(m_default), synthetic(m_explicit))
  expect_false(recipe(m_default)@conditional)
})

test_that("conditional preserves treatment vocabulary and frequencies", {
  f <- make_effect_fixture()
  m <- suppressWarnings(
    mask(f$df, f$roles, mode = "local", seed = 1, conditional = TRUE)
  )
  s <- synthetic(m)
  expect_setequal(levels(s$Genotype), levels(f$df$Genotype))
  expect_equal(
    sort(as.vector(table(s$Genotype))),
    sort(as.vector(table(f$df$Genotype)))
  )
})

test_that("conditional warns and degrades when nothing is left to condition on", {
  set.seed(7)
  df <- data.frame(
    y = stats::rnorm(80),
    z = stats::rnorm(80)
  )
  r <- propose_roles(df, detect = FALSE)
  r$role[r$col == "y"] <- "outcome"
  r$role[r$col == "z"] <- "covariate"
  # The conditional-degrade advisory fires alongside the routine
  # local-mode notice; collect every warning, then assert the advisory
  # is among them (without tripping testthat on the expected second one).
  warned <- character()
  m <- withCallingHandlers(
    mask(df, r, mode = "local", seed = 1, conditional = TRUE),
    warning = function(w) {
      warned <<- c(warned, conditionMessage(w))
      invokeRestart("muffleWarning")
    }
  )
  expect_true(any(grepl("no treatment or design column", warned)))
  rec <- recipe(m)
  expect_true(rec@conditional)
  expect_identical(rec@conditioning_cols, character())
  # Output is still produced (pooled fallback).
  expect_equal(nrow(synthetic(m)), nrow(df))
})

test_that("conditional clone works through the masque() guided verb", {
  f <- make_effect_fixture()
  m <- masque(
    f$df, roles = f$roles, mode = "local", seed = 1,
    conditional = TRUE, ask = FALSE, quiet = TRUE
  )
  eff <- .arm_effect(synthetic(m))
  expect_equal(eff, f$true_eff, tolerance = 0.4)
  expect_true(recipe(m)@conditional)
})

test_that("conditional conditions on design strata, not only treatment", {
  set.seed(11)
  n <- 480
  site <- factor(rep(c("S1", "S2", "S3", "S4"), each = n / 4))
  # Strong site main effect; no treatment column at all.
  site_mean <- c(S1 = 5, S2 = 15, S3 = 25, S4 = 35)
  yield <- site_mean[as.character(site)] + stats::rnorm(n, sd = 2)
  df <- data.frame(site = site, yield = as.numeric(yield))
  r <- propose_roles(df, detect = FALSE)
  r$role[r$col == "site"] <- "design"
  r$action[r$col == "site"] <- "keep"
  r$role[r$col == "yield"] <- "outcome"

  m_cond <- suppressWarnings(
    mask(df, r, mode = "local", seed = 1, conditional = TRUE)
  )
  m_marg <- suppressWarnings(
    mask(df, r, mode = "local", seed = 1, conditional = FALSE)
  )
  # Per-site mean separation should survive under conditional but be
  # washed out under marginal (every site drawn from the pooled margin).
  spread <- function(s) {
    mu <- tapply(s$yield, s$site, mean)
    diff(range(mu))
  }
  true_spread <- spread(df)
  expect_gt(spread(synthetic(m_cond)), 0.7 * true_spread)
  expect_lt(spread(synthetic(m_marg)), 0.3 * true_spread)
})

test_that("conditional clone preserves an N-rate effect on public agridat data", {
  skip_if_not_installed("agridat")
  data("lasrosas.corn", package = "agridat", envir = environment())
  dat <- get("lasrosas.corn", envir = environment())
  # A real Argentine corn N-rate trial. nf is the nitrogen-rate factor
  # (N0 .. N5); yield is the response. nf has a strong, real effect.
  df <- data.frame(
    rep = dat$rep,
    nf = dat$nf,
    yield = dat$yield,
    bv = dat$bv,
    stringsAsFactors = FALSE
  )
  r <- propose_roles(df, detect = FALSE)
  r$role[r$col == "rep"] <- "design"
  r$action[r$col == "rep"] <- "keep"
  r$role[r$col == "nf"] <- "treatment"
  r <- set_role(r, "nf", action = "scramble")
  r$role[r$col == "yield"] <- "outcome"
  r$role[r$col == "bv"] <- "covariate"

  arm_means <- function(d) tapply(d$yield, d$nf, mean)
  true_means <- arm_means(df)

  m_cond <- suppressWarnings(
    mask(df, r, mode = "local", seed = 3, conditional = TRUE)
  )
  m_marg <- suppressWarnings(
    mask(df, r, mode = "local", seed = 3, conditional = FALSE)
  )

  # Correlation of per-arm synthetic means with the real per-arm means:
  # the conditional clone tracks them; the marginal clone does not.
  cor_cond <- stats::cor(arm_means(synthetic(m_cond)), true_means)
  cor_marg <- stats::cor(arm_means(synthetic(m_marg)), true_means)
  expect_gt(cor_cond, 0.9)
  expect_lt(cor_marg, 0.5)
})
