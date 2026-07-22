# Regression contract for the independent audit closed in 0.9.1.

.farm_block_fixture <- function() {
  out <- expand.grid(
    farm = factor(paste0("F", seq_len(3L))),
    gen = factor(paste0("G", seq_len(5L))),
    KEEP.OUT.ATTRS = FALSE
  )
  out$yield <- seq_len(nrow(out)) / 10
  out
}

.shared_check_fixture <- function() {
  out <- met_disconnected_fixture()
  shared <- out[out$trial == "T2", ][1L, , drop = FALSE]
  shared$gen <- factor("G1", levels = levels(out$gen))
  shared$yield <- max(out$yield) + 0.1
  rbind(out, shared)
}

test_that("unreplicated site-only blocks require review", {
  ds <- detect_design(.farm_block_fixture())

  expect_true(is.na(ds@is_met))
  expect_equal(ds@scope_status, "review_required")
  expect_equal(ds@scope_confidence, "medium")
  expect_equal(ds@env_cols, "farm")
  expect_equal(
    ds@evidence$environment$replicated_level_fraction,
    0
  )
})

test_that("omitted mask mode inherits collaborate role provenance", {
  d <- met_complete_fixture()
  roles <- propose_roles(d, mode = "collaborate")
  roles <- set_role(roles, "yield", role = "outcome")

  masked <- mask(d, roles, seed = 201L)

  expect_equal(recipe(masked)@mode, "collaborate")
  expect_false(identical(levels(synthetic(masked)$env), levels(d$env)))
})

test_that("explicit collaborate-to-local downgrade warns", {
  d <- met_complete_fixture()
  roles <- propose_roles(d, mode = "collaborate")

  expect_warning(
    masked <- mask(d, roles, mode = "local", seed = 202L),
    class = "masque_mode_downgrade"
  )
  expect_equal(recipe(masked)@mode, "local")
})

test_that("mask_set inherits one supplied role mode and rejects mixed modes", {
  tables <- list(trial = met_complete_fixture())
  collaborate <- list(
    trial = propose_roles(tables$trial, mode = "collaborate")
  )

  masked <- mask_set(tables, roles = collaborate, seed = 203L, quiet = TRUE)
  expect_equal(recipe(masked)@mode, "collaborate")

  mixed_tables <- list(a = met_complete_fixture(), b = met_complete_fixture())
  mixed <- list(
    a = propose_roles(mixed_tables$a, mode = "local"),
    b = propose_roles(mixed_tables$b, mode = "collaborate")
  )
  expect_error(
    mask_set(mixed_tables, roles = mixed, seed = 204L, quiet = TRUE),
    "multiple modes"
  )
})

test_that("connectivity guard bounds incidence and adjacency allocations", {
  n <- 2500L
  env_key <- factor(paste0("E", seq_len(n)))
  treatment_key <- factor(paste0("G", seq_len(n)))

  guarded <- masque:::.incidence_connectivity(env_key, treatment_key)

  expect_equal(guarded$status, "not_computed")
  expect_match(guarded$reason, "2500 environments")
  expect_match(guarded$reason, "2500 treatments")
  expect_match(guarded$reason, "limit")

  two_treatments <- factor(rep(c("G1", "G2"), length.out = n))
  adjacency_guarded <- masque:::.incidence_connectivity(
    env_key, two_treatments
  )
  expect_equal(adjacency_guarded$status, "not_computed")
  expect_match(adjacency_guarded$reason, "2500 environments x 2 treatments")
})

test_that("one shared check treatment retains quantified group evidence", {
  ds <- detect_design(.shared_check_fixture(), env = "env")

  expect_equal(ds@group_cols, "trial")
  grouping <- ds@evidence$grouping
  trial <- grouping[grouping$col == "trial", , drop = FALSE]
  expect_equal(trial$shared_treatments, 1L)
  expect_equal(trial$status, "near_partition")
  expect_gt(trial$confined_fraction, 0.8)
})

test_that("interleaved trial labels are not reported as groups", {
  d <- expand.grid(
    trial = factor(c("T1", "T2")),
    env = factor(c("E1", "E2")),
    gen = factor(paste0("G", seq_len(5L))),
    KEEP.OUT.ATTRS = FALSE
  )
  d$yield <- seq_len(nrow(d)) / 10
  ds <- detect_design(d, env = "env")

  expect_length(ds@group_cols, 0L)
  expect_equal(ds@evidence$grouping$status, "interleaved")
})

test_that("a pinned action prevents automatic role promotion", {
  d <- met_county_fixture()
  roles <- propose_roles(d, detect = FALSE)
  roles$action[roles$col == "county"] <- "drop"
  ds <- detect_design(d)

  overlaid <- masque:::.overlay_recommended_roles(
    roles, ds@recommended_roles, "local"
  )

  expect_equal(overlaid$role[overlaid$col == "county"], "covariate")
  expect_equal(overlaid$action[overlaid$col == "county"], "drop")
})

test_that("a suspected but unconfirmed environment is preserved, not scrambled", {
  # Unreplicated MET whose environment column carries a site token outside
  # propose_roles()'s design-name heuristic (county / location / farm). It
  # resolves to review_required; the fail-safe keeps it byte-identical rather
  # than letting it fall through to a covariate row-permutation.
  u <- data.frame(
    county = factor(rep(paste0("C", seq_len(6L)), each = 8L)),
    gen = factor(rep(paste0("G", seq_len(8L)), times = 6L)),
    yield = seq_len(48L) / 10
  )
  ds <- detect_design(u)
  expect_equal(ds@scope_status, "review_required")

  roles <- propose_roles(u)
  expect_equal(roles$role[roles$col == "county"], "design")
  expect_equal(roles$action[roles$col == "county"], "keep")

  masked <- mask(u, roles, seed = 7L)
  expect_identical(
    as.character(synthetic(masked)$county), as.character(u$county)
  )
  expect_true(all(
    (table(u$county, u$gen) > 0) ==
      (table(synthetic(masked)$county, synthetic(masked)$gen) > 0)
  ))
})

test_that("mask warns when mode is unset and roles lost their provenance", {
  d <- met_county_fixture()
  roles <- propose_roles(d, mode = "collaborate")
  stripped <- roles
  attr(stripped, "mode") <- NULL # what a data.table()/saveRDS round-trip does

  # stripped provenance + no explicit mode must warn, not silently mask local
  expect_warning(
    mask(d, stripped, seed = 1L),
    class = "masque_mode_unset"
  )

  # an explicit mode silences the warning and is honoured
  saw_unset <- FALSE
  m2 <- withCallingHandlers(
    mask(d, stripped, mode = "collaborate", seed = 1L),
    masque_mode_unset = function(w) {
      saw_unset <<- TRUE
      invokeRestart("muffleWarning")
    }
  )
  expect_false(saw_unset)
  expect_equal(recipe(m2)@mode, "collaborate")

  # an intact tibble still inherits its mode silently (no false alarm)
  saw_intact <- FALSE
  m3 <- withCallingHandlers(
    mask(d, roles, seed = 1L),
    masque_mode_unset = function(w) {
      saw_intact <<- TRUE
      invokeRestart("muffleWarning")
    }
  )
  expect_false(saw_intact)
  expect_equal(recipe(m3)@mode, "collaborate")
})
