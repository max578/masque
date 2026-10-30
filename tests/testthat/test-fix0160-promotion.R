# A treatment by name, or by structure only beside a crossed design column.

# 80 patients, eight ICD-10 codes of ten patients each, no design column.
.f18_clinical <- function() {
  set.seed(80)
  n <- 80L
  dx <- c("C18.7", "C25.9", "C34.1", "C50.9", "C61", "C64.9", "C67.9", "C71.9")
  data.frame(
    patient_id = sprintf("P%03d", seq_len(n)),
    age = round(rnorm(n, 64, 10)),
    sex = factor(sample(c("F", "M"), n, replace = TRUE)),
    diagnosis = factor(rep(dx, each = 10L)[sample(n)]),
    stage = factor(sample(c("I", "II", "III", "IV"), n, replace = TRUE)),
    biomarker = round(rlnorm(n, 2, 0.6), 2),
    stringsAsFactors = FALSE
  )
}

# Augmented trial: 3 blocks of 10 plots; 18 test entries once each and two
# checks twice in every block, so 18 of 20 genotypes are seen once.
.f18_augmented <- function(integer_yield = FALSE) {
  set.seed(30)
  tests <- sprintf("E%02d", 1:18)
  blocks <- lapply(1:3, function(b) {
    data.frame(
      block = b,
      genotype = sample(
        c(tests[(b - 1L) * 6L + 1:6], rep(c("CHK1", "CHK2"), 2))
      ),
      stringsAsFactors = FALSE
    )
  })
  d <- do.call(rbind, blocks)
  d$yield <- if (integer_yield) {
    round(rnorm(30L, 5, 1))
  } else {
    round(rnorm(30L, 5, 1), 2)
  }
  d
}

# One site, 20 genotypes in 20 plots, no replication.
.f18_single_site_unreplicated <- function() {
  set.seed(21)
  data.frame(
    row = 1:20, genotype = sprintf("G%02d", sample(20)),
    yield = round(rnorm(20, 4, 0.5), 2), stringsAsFactors = FALSE
  )
}

# Four sites, each of 15 genotypes once per site.
.f18_multi_site_unreplicated <- function() {
  set.seed(22)
  d <- expand.grid(
    genotype = sprintf("G%02d", 1:15), site = sprintf("S%d", 1:4),
    stringsAsFactors = FALSE, KEEP.OUT.ATTRS = FALSE
  )
  d$yield <- round(rnorm(nrow(d), 4, 0.5), 2)
  d[, c("site", "genotype", "yield")]
}

# Three sites x 3 reps x 10 genotypes, the site column under a given name.
.f18_site_named <- function(site_col) {
  set.seed(23)
  d <- expand.grid(
    genotype = sprintf("G%02d", 1:10), rep = 1:3,
    site = c("Roseworthy", "Minnipa", "Loxton"),
    stringsAsFactors = FALSE, KEEP.OUT.ATTRS = FALSE
  )
  d$yield <- round(rnorm(nrow(d), 3, 0.5), 2)
  d <- d[, c("site", "rep", "genotype", "yield")]
  names(d)[1L] <- site_col
  d
}

# 6 trials x 20 genotypes x 3 reps, four blocks of five in each rep with
# labels restarted; aet (numeric) and soil (categorical) constant within trial.
.n5_trials <- function() {
  set.seed(1)
  trials <- sprintf("T%d", 1:6)
  gens <- sprintf("G%02d", 1:20)
  g <- expand.grid(
    genotype = gens, rep = 1:3, trial = trials,
    stringsAsFactors = FALSE, KEEP.OUT.ATTRS = FALSE
  )
  g$block <- NA_character_
  for (t in trials) for (r in 1:3) {
    idx <- which(g$trial == t & g$rep == r)
    g$block[idx] <- sprintf("B%d", sample(rep(1:4, each = 5)))
  }
  trial_eff <- c(0.8, -0.5, 0.3, 1.1, -0.2, 0.0)
  g$yield <- round(
    3 + trial_eff[match(g$trial, trials)] + rnorm(nrow(g), 0, 0.35), 2
  )
  g$aet <- c(312.456, 287.901, 401.233, 355.678, 298.112, 376.543)[
    match(g$trial, trials)
  ]
  g$plot_cov <- round(rnorm(nrow(g), 50, 8), 2)
  g$soil <- c("clay", "loam", "sand", "clay", "loam", "sand")[
    match(g$trial, trials)
  ]
  g[, c(
    "trial", "rep", "block", "genotype", "yield", "aet", "plot_cov", "soil"
  )]
}

.role_of <- function(roles, col) roles$role[roles$col == col]
.action_of <- function(roles, col) roles$action[roles$col == col]

test_that("a design-free clinical code is not promoted to treatment", {
  d <- .f18_clinical()
  for (mode in c("local", "collaborate")) {
    r <- propose_roles(d, mode = mode)
    expect_equal(.role_of(r, "diagnosis"), "covariate", info = mode)
    expect_false("diagnosis" %in% masque:::.conditioning_cols(r), info = mode)
  }
  ds <- detect_design(d)
  rec <- ds@recommended_roles
  hint <- rec[rec$col == "diagnosis" & rec$role == "treatment", ]
  expect_equal(nrow(hint), 1L)
  expect_false(hint$auto_apply)
  expect_match(hint$reason, "no design column")
  printed <- paste(capture.output(print(ds), type = "message"), collapse = "\n")
  expect_match(printed, "Not applied: diagnosis")
})

test_that("an augmented trial keeps genotype and never treats yield", {
  for (integer_yield in c(FALSE, TRUE)) {
    d <- .f18_augmented(integer_yield)
    info <- paste("integer_yield =", integer_yield)
    expect_equal(sum(table(d$genotype) == 1L), 18L, info = info)
    r <- propose_roles(d)
    expect_equal(.role_of(r, "genotype"), "treatment", info = info)
    expect_equal(.role_of(r, "block"), "design", info = info)
    expect_equal(.role_of(r, "yield"), "outcome", info = info)
    ds <- detect_design(d)
    # No rule models an augmented design; whatever it names, it is genotype.
    expect_true(all(ds@treatment_col %in% "genotype"), info = info)
    expect_false(any(c("yield", "block") %in% ds@treatment_col), info = info)
    treatment_hints <- ds@recommended_roles$col[
      ds@recommended_roles$role == "treatment"
    ]
    expect_false("yield" %in% treatment_hints, info = info)
    expect_false("block" %in% treatment_hints, info = info)
  }
})

test_that("unreplicated genotypes found by name stay treatments", {
  single <- propose_roles(.f18_single_site_unreplicated())
  expect_equal(.role_of(single, "genotype"), "treatment")
  expect_equal(.role_of(single, "row"), "design")

  multi <- propose_roles(.f18_multi_site_unreplicated())
  expect_equal(.role_of(multi, "genotype"), "treatment")
  expect_equal(.role_of(multi, "site"), "design")
})

test_that("site-name spellings are design columns, raw and legalised", {
  spellings <- c(
    "site_name", "Site Name", "Site.Name", "site.name",
    "trial_site", "Trial Site", "Trial.Site"
  )
  for (nm in spellings) {
    d <- .f18_site_named(nm)
    expect_identical(names(d)[1L], nm)
    expect_equal(.role_of(propose_roles(d, detect = FALSE), nm), "design",
      info = nm
    )
    r <- propose_roles(d)
    expect_equal(.role_of(r, nm), "design", info = nm)
    expect_equal(.role_of(r, "genotype"), "treatment", info = nm)
  }
})

test_that("yates.oats: varieties on whole plots, nitrogen on sub-plots", {
  skip_if_not_installed("agridat")
  # ?agridat::yates.oats: "Varieties were applied to the main plots.
  # Manurial (nitrogen) treatments were applied to the sub-plots." 6 blocks.
  d <- agridat::yates.oats
  ds <- detect_design(d)
  expect_identical(ds@class_label, "split-plot")
  expect_identical(ds@whole_plot_col, "gen")
  expect_identical(ds@sub_plot_col, "nitro")
  expect_setequal(ds@treatment_col, c("gen", "nitro"))
  expect_identical(ds@block_cols, "block")

  r <- propose_roles(d)
  expect_equal(.role_of(r, "gen"), "treatment")
  expect_equal(.role_of(r, "nitro"), "treatment")
  expect_equal(.role_of(r, "block"), "design")
  expect_equal(.role_of(r, "yield"), "outcome")
})

test_that("a trial-constant covariate is never a kept treatment (N5)", {
  d <- .n5_trials()
  # Construction: one aet and one soil value per trial.
  expect_true(all(tapply(d$aet, d$trial, data.table::uniqueN) == 1L))
  expect_true(all(tapply(d$soil, d$trial, data.table::uniqueN) == 1L))

  expected <- c(
    trial = "design", rep = "design", block = "design",
    genotype = "treatment", yield = "outcome", aet = "covariate",
    plot_cov = "covariate", soil = "covariate"
  )
  for (mode in c("local", "collaborate")) {
    r <- propose_roles(d, mode = mode)
    expect_identical(
      stats::setNames(r$role, r$col)[names(expected)], expected,
      info = mode
    )
    expect_equal(.action_of(r, "aet"), "scramble", info = mode)
  }
})

test_that("the trial table reads as a blocked MET, not a split-plot (N5)", {
  d <- .n5_trials()
  ds <- detect_design(d)
  # Construction: every genotype three times in every trial and six times in
  # every rep, so trials are complete blocks of the pooled table.
  expect_identical(ds@class_label, "RCBD")
  expect_identical(ds@treatment_col, "genotype")
  expect_false("aet" %in% c(ds@whole_plot_col, ds@treatment_col))

  # With trial as the environment, each trial is a resolvable incomplete
  # block design: four blocks of five nested in each of three reps.
  met <- detect_design(d, env = "trial")
  expect_true(isTRUE(met@is_met))
  expect_identical(unique(met@per_env$class_label), "IBD/alpha-lattice")
  expect_setequal(met@block_cols, c("rep", "block"))
})
