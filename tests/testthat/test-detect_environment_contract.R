# Phase 0 contract for conservative MET-scope detection.
#
# Fixture truth and the explicit-environment API are green in Phase 1.
# Automatic resolution and role integration remain contracts for Phases 2-3.

test_that("hand-built MET fixtures encode the intended scope", {
  complete <- met_complete_fixture()
  complete_incidence <- table(complete$env, complete$gen)
  expect_equal(dim(complete_incidence), c(3L, 4L))
  expect_true(all(complete_incidence == 2L))

  site_year <- met_site_year_fixture()
  env_key <- interaction(site_year$site, site_year$year, drop = TRUE)
  expect_equal(nlevels(env_key), 4L)
  expect_true(all(table(env_key, site_year$gen) == 2L))

  unreplicated <- met_unreplicated_fixture()
  expect_true(all(table(unreplicated$env, unreplicated$gen) == 1L))
})

test_that("disconnected fixture has two experiment populations", {
  d <- met_disconnected_fixture()
  trial_gen <- table(d$trial, d$gen) > 0L
  env_gen <- table(d$env, d$gen) > 0L

  expect_equal(nrow(trial_gen), 2L)
  expect_true(all(colSums(trial_gen) == 1L))
  expect_true(all(rowSums(env_gen) == 3L))
  expect_equal(sum(env_gen[1:2, 4:6]), 0L)
  expect_equal(sum(env_gen[3:4, 1:3]), 0L)
})

test_that("adversarial fixtures encode ambiguity without randomness", {
  repeated <- repeated_measures_fixture()
  expect_equal(length(unique(repeated$subject_id)), 8L)
  expect_true(all(table(repeated$subject_id) == 3L))

  near_unique <- near_unique_site_fixture()
  expect_equal(length(unique(near_unique$site)), nrow(near_unique))

  ambiguous <- ambiguous_site_fixture()
  expect_equal(nlevels(ambiguous$site), 2L)
  expect_equal(nlevels(ambiguous$location), 2L)
  expect_true(all(table(ambiguous$site, ambiguous$gen) == 4L))
  expect_true(all(table(ambiguous$location, ambiguous$gen) == 4L))
})

test_that("explicit env detects multi-environment scope", {
  d <- met_complete_fixture()
  ds <- detect_design(d, env = "env")

  expect_true(ds@is_met)
  expect_equal(ds@scope_label, "multi_environment")
  expect_equal(ds@scope_status, "detected")
  expect_equal(ds@env_cols, "env")
  expect_equal(ds@n_env, 3L)
  expect_equal(ds@connectivity$status, "connected")
})

test_that("explicit site-year basis is composed into one environment", {
  d <- met_site_year_fixture()
  ds <- detect_design(d, env = c("site", "year"))

  expect_true(ds@is_met)
  expect_equal(ds@env_cols, c("site", "year"))
  expect_equal(ds@env_method, "user_composite")
  expect_equal(ds@n_env, 4L)
})

test_that("disconnectedness is diagnostic and does not veto MET status", {
  d <- met_disconnected_fixture()
  ds <- detect_design(d, env = "env")

  expect_true(ds@is_met)
  expect_equal(ds@n_env, 4L)
  expect_equal(ds@connectivity$status, "disconnected")
  expect_equal(ds@connectivity$components, 2L)
  expect_equal(ds@group_cols, "trial")
})

test_that("unreplicated MET does not require an inner design class", {
  d <- met_unreplicated_fixture()
  ds <- detect_design(d, env = "env")

  expect_true(ds@is_met)
  expect_equal(ds@n_env, 3L)
  expect_true(ds@within_design_label %in% c("unresolved", "none"))
})

test_that("automatic inference abstains on repeated measures and ambiguity", {
  repeated <- detect_design(repeated_measures_fixture())
  expect_true(is.na(repeated@is_met))
  expect_equal(repeated@scope_label, "uncertain")

  ambiguous <- detect_design(ambiguous_site_fixture())
  expect_true(is.na(ambiguous@is_met))
  expect_equal(ambiguous@scope_label, "uncertain")

  near_unique <- detect_design(near_unique_site_fixture())
  expect_true(is.na(near_unique@is_met))
  expect_equal(near_unique@scope_label, "uncertain")
})

test_that("automatic precedence covers exact, precomposed and site-year", {
  exact <- detect_design(met_complete_fixture())
  expect_true(exact@is_met)
  expect_equal(exact@env_cols, "env")
  expect_equal(exact@env_method, "exact")
  expect_equal(exact@scope_confidence, "high")

  precomposed <- detect_design(met_precomposed_fixture())
  expect_true(precomposed@is_met)
  expect_equal(precomposed@env_cols, "site_year")
  expect_equal(precomposed@env_method, "precomposed")

  site_year <- detect_design(met_site_year_fixture())
  expect_true(site_year@is_met)
  expect_equal(site_year@env_cols, c("site", "year"))
  expect_equal(site_year@env_method, "site_year")
  expect_equal(
    site_year@evidence$environment$competition_margin,
    1L
  )
  expect_equal(site_year@evidence$environment$coverage, 1)
  expect_equal(site_year@evidence$environment$n_env, 4L)
  expect_equal(
    site_year@evidence$environment$max_env_per_treatment,
    4L
  )
})

test_that("one unambiguous site-like field is promoted", {
  ds <- detect_design(met_county_fixture())

  expect_true(ds@is_met)
  expect_equal(ds@env_cols, "county")
  expect_equal(ds@env_method, "site")
  expect_equal(ds@n_env, 6L)
})

test_that("year-only evidence requires explicit review", {
  skip_if_not_installed("agridat")
  ds <- detect_design(agridat::onofri.winterwheat)

  expect_true(is.na(ds@is_met))
  expect_equal(ds@scope_label, "uncertain")
  expect_equal(ds@scope_status, "review_required")
  expect_equal(ds@scope_confidence, "medium")
  expect_equal(ds@env_cols, "year")
  expect_equal(ds@env_method, "year")
  expect_equal(ds@n_env, 7L)
  expect_equal(ds@connectivity$status, "not_computed")
  expect_equal(nrow(ds@per_env), 0L)
})

test_that("same-tier site candidates abstain explicitly", {
  ds <- detect_design(ambiguous_site_fixture())

  expect_true(is.na(ds@is_met))
  expect_equal(ds@scope_status, "ambiguous")
  expect_length(ds@env_cols, 0L)
  expect_match(ds@warnings, "site, location")
  expect_equal(ds@evidence$environment$competition_margin, 0L)
})

test_that("trial alone is grouping evidence, not environment evidence", {
  d <- met_disconnected_fixture()
  d$env <- NULL
  ds <- detect_design(d)

  expect_true(is.na(ds@is_met))
  expect_equal(ds@scope_label, "uncertain")
  expect_length(ds@env_cols, 0L)
})

test_that("exact scope survives ambiguous treatment evidence honestly", {
  d <- expand.grid(
    env = factor(c("E1", "E2", "E3")),
    arm_a = factor(c("A1", "A2")),
    arm_b = factor(c("B1", "B2")),
    KEEP.OUT.ATTRS = FALSE
  )
  d$yield <- seq_len(nrow(d)) / 10
  ds <- detect_design(d)

  expect_true(ds@is_met)
  expect_equal(ds@env_cols, "env")
  expect_equal(ds@connectivity$status, "not_computed")
})

test_that("automatic scope is invariant to row and label permutations", {
  d <- met_site_year_fixture()
  permuted <- d[rev(seq_len(nrow(d))), , drop = FALSE]
  permuted$site <- factor(
    permuted$site,
    levels = rev(levels(permuted$site)),
    labels = c("S2", "S1")
  )
  permuted$year <- ifelse(permuted$year == 2024L, 2034L, 2033L)

  original <- detect_design(d)
  changed <- detect_design(permuted)
  expect_equal(changed@scope_label, original@scope_label)
  expect_equal(changed@env_cols, original@env_cols)
  expect_equal(changed@env_method, original@env_method)
  expect_equal(changed@n_env, original@n_env)
  expect_equal(changed@connectivity$status, original@connectivity$status)
  expect_equal(changed@connectivity$components,
    original@connectivity$components
  )
})

test_that("automatic scope does not depend on outcome values", {
  d <- met_complete_fixture()
  changed <- d
  changed$yield <- rev(seq_len(nrow(changed)))^2

  original_ds <- detect_design(d)
  changed_ds <- detect_design(changed)
  expect_equal(changed_ds@scope_label, original_ds@scope_label)
  expect_equal(changed_ds@env_cols, original_ds@env_cols)
  expect_equal(changed_ds@n_env, original_ds@n_env)
  expect_equal(
    changed_ds@connectivity$status,
    original_ds@connectivity$status
  )
})

test_that("explicit user roles can exclude a name-matched candidate", {
  d <- met_complete_fixture()
  roles <- propose_roles(d, detect = FALSE)
  roles$role[roles$col == "env"] <- "outcome"
  roles$action[roles$col == "env"] <- "scramble"
  ds <- detect_design(d, roles = roles)

  expect_true(is.na(ds@is_met))
  expect_equal(ds@scope_label, "uncertain")
  expect_length(ds@env_cols, 0L)
})

test_that("near-unique exact environment names fail the validity gate", {
  d <- near_unique_site_fixture()
  names(d)[names(d) == "site"] <- "env"
  ds <- detect_design(d)

  expect_true(is.na(ds@is_met))
  expect_equal(ds@scope_label, "uncertain")
  expect_length(ds@env_cols, 0L)
})

test_that("multiple user-roled treatments support incidence diagnostics", {
  d <- met_multiple_treatment_fixture()
  roles <- propose_roles(d, detect = FALSE)
  roles$role[roles$col %in% c("genotype", "dose")] <- "treatment"
  ds <- detect_design(d, roles = roles, env = "env")

  expect_true(ds@is_met)
  expect_setequal(ds@treatment_col, c("genotype", "dose"))
  expect_equal(ds@connectivity$status, "connected")
})

test_that("legacy base-fixture signatures are frozen before MET work", {
  fixtures <- list(iris = iris, tooth = ToothGrowth, mtcars = mtcars)
  oracle <- legacy_base_oracle()

  for (nm in names(fixtures)) {
    observed <- legacy_design_fields(detect_design(fixtures[[nm]]))
    observed <- observed[names(oracle[[nm]])]
    expect_equal(observed, oracle[[nm]], tolerance = 1e-12, info = nm)
  }
})

test_that("env = FALSE freezes legacy public fields", {
  fixtures <- list(iris = iris, tooth = ToothGrowth, mtcars = mtcars)
  expected <- legacy_base_oracle()

  observed <- lapply(fixtures, function(d) {
    legacy_design_fields(detect_design(d, env = FALSE))
  })
  observed <- Map(function(x, y) x[names(y)], observed, expected)
  expect_equal(observed, expected, tolerance = 1e-12)
})

test_that("legacy positional arguments retain their meaning", {
  positional <- detect_design(iris, NULL, FALSE, 0.5, 0.02)
  named <- detect_design(
    iris,
    roles = NULL,
    interactive = FALSE,
    threshold = 0.5,
    tie_delta = 0.02
  )

  expect_equal(
    legacy_design_fields(positional),
    legacy_design_fields(named),
    tolerance = 1e-12
  )
})

test_that("explicit environment validation fails closed", {
  d <- met_complete_fixture()
  expect_error(
    detect_design(d, env = "missing_col"),
    "missing_col",
    class = "masque_invalid_environment"
  )
  expect_error(
    detect_design(d, env = c("env", "env")),
    "duplicate",
    class = "masque_invalid_environment"
  )

  d$empty_env <- NA_character_
  expect_error(
    detect_design(d, env = "empty_env"),
    "all-missing",
    class = "masque_invalid_environment"
  )
  expect_error(
    detect_design(d, env = TRUE),
    "must be",
    class = "masque_invalid_environment"
  )
})

test_that("explicit scope handles missingness without mutating input", {
  d <- met_missing_fixture()
  before <- d
  ds <- detect_design(d, env = "env")

  expect_identical(d, before)
  expect_true(ds@is_met)
  expect_equal(ds@n_env, 3L)
  expect_equal(nrow(ds@per_env), 3L)
  expect_equal(ds@connectivity$status, "connected")
})

test_that("a one-level explicit environment reports single scope", {
  d <- single_rcbd_fixture()
  d$env <- factor("E1")
  ds <- detect_design(d, env = "env")

  expect_false(ds@is_met)
  expect_equal(ds@scope_label, "single_environment")
  expect_equal(ds@n_env, 1L)
  expect_equal(nrow(ds@per_env), 1L)
})
