# Fixtures for the control datasets: a small MET with a trial-level numeric,
# categorical and date covariate, a plot-level covariate correlated with
# yield, a whole-plot factor, a whole-valued outcome, and missing cells
# including one trial with no covariate value at all.
.ctl_met <- function(n_trial = 4L, n_rep = 3L, n_gen = 8L, seed = 11L) {
  withr::with_seed(seed, {
    trials <- sprintf("T%d", seq_len(n_trial))
    gens <- sprintf("G%02d", seq_len(n_gen))
    g <- expand.grid(
      gen = gens, rep = seq_len(n_rep), trial = trials,
      stringsAsFactors = FALSE, KEEP.OUT.ATTRS = FALSE
    )
    g$block <- sprintf("B%d", (match(g$gen, gens) - 1L) %/% 4L + 1L)
    g$irrig <- ifelse(g$rep %% 2L == 1L, "dry", "wet")
    trial_eff <- stats::rnorm(n_trial, 0, 0.8)
    gen_eff <- stats::rnorm(n_gen, 0, 0.4)
    g$yield <- round(
      3 + trial_eff[match(g$trial, trials)] + gen_eff[match(g$gen, gens)] +
        ifelse(g$irrig == "wet", 0.5, 0) + stats::rnorm(nrow(g), 0, 0.3),
      2
    )
    g$count <- as.integer(round(g$yield * 3))
    g$aet <- round(300 + 40 * trial_eff, 1)[match(g$trial, trials)]
    g$plot_cov <- round(g$yield * 10 + stats::rnorm(nrow(g), 0, 1), 2)
    g$soil <- rep_len(c("clay", "loam", "sand"), n_trial)[
      match(g$trial, trials)
    ]
    g$sow <- as.Date("2024-05-01") + 7L * match(g$trial, trials)
    g$yield[c(3L, 17L, 40L)] <- NA
    g$plot_cov[c(5L, 6L)] <- NA
    g$aet[g$trial == trials[2L]] <- NA
    g$rep <- sprintf("R%d", g$rep)
    g[, c(
      "trial", "rep", "block", "irrig", "gen", "yield", "count", "aet",
      "plot_cov", "soil", "sow"
    )]
  })
}

.ctl_roles <- function(df) {
  r <- suppressWarnings(propose_roles(df, detect = FALSE))
  r <- set_role(r, c("trial", "rep", "block"), role = "design", action = "keep")
  r <- set_role(r, "gen", role = "treatment", action = "keep")
  r <- set_role(r, "irrig", role = "covariate", action = "scramble")
  r <- set_role(r, c("yield", "count"), role = "outcome", action = "scramble")
  r <- set_role(
    r, c("aet", "plot_cov", "soil"), role = "covariate", action = "scramble"
  )
  set_role(r, "sow", role = "date", action = "scramble")
}

# The standard spec on the MET: genotype permuted within blocks, the
# trial-level covariates declared unit-grained.
.ctl_spec <- function(..., n = 2L, seed = 3L) {
  control_spec(
    on = "gen",
    strata = c("trial", "rep", "block"),
    grain = list(aet = "trial", soil = "trial", sow = "trial"),
    n = n,
    seed = seed,
    ...
  )
}

# Two arms, no design: for effect recovery.
.ctl_two_arm <- function(n = 1000L, seed = 5L) {
  withr::with_seed(seed, data.frame(
    trt = rep(c("A", "B"), each = n / 2L),
    y = round(stats::rnorm(n, 10, 2), 3),
    stringsAsFactors = FALSE
  ))
}

.ctl_two_arm_roles <- function(df) {
  r <- suppressWarnings(propose_roles(df, detect = FALSE))
  r <- set_role(r, "trt", role = "treatment", action = "keep")
  set_role(r, "y", role = "outcome", action = "scramble")
}

# Many levels, no design: for rank recovery.
.ctl_many_levels <- function(k = 20L, m = 30L, seed = 7L) {
  withr::with_seed(seed, data.frame(
    lev = rep(sprintf("L%02d", seq_len(k)), each = m),
    y = round(stats::rnorm(k * m, 10, 2), 3),
    stringsAsFactors = FALSE
  ))
}

.ctl_many_roles <- function(df) {
  r <- suppressWarnings(propose_roles(df, detect = FALSE))
  r <- set_role(r, "lev", role = "treatment", action = "keep")
  set_role(r, "y", role = "outcome", action = "scramble")
}

# The non-missing values of two vectors are the same multiset.
.ctl_same_multiset <- function(a, b) {
  identical(
    sort(as.character(a[!is.na(a)])),
    sort(as.character(b[!is.na(b)]))
  )
}

# A refusal: an error of the given class under the shared marker, no warning.
.ctl_expect_refusal <- function(expr, class) {
  err <- testthat::expect_no_warning(tryCatch(expr, error = function(e) e))
  testthat::expect_s3_class(err, "error")
  testthat::expect_true(inherits(err, class))
  testthat::expect_true(inherits(err, "orchestra_refusal"))
}
