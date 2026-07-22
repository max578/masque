# Optional agridat acceptance oracle for MET scope.
# Scientific truth and current inner-detector behaviour are kept separate.

test_that("agridat MET fixtures retain their documented structural facts", {
  skip_if_not_installed("agridat")

  besag <- agridat::besag.met
  expect_equal(nlevels(besag$county), 6L)
  expect_equal(nlevels(besag$gen), 64L)
  expect_equal(nlevels(besag$rep), 3L)
  expect_equal(length(unique(besag$row)), 18L)
  expect_equal(length(unique(besag$col)), 11L)
  expect_true(all(table(besag$county, besag$gen) >= 3L))

  gauch <- agridat::gauch.soy
  gauch_composite <- interaction(gauch$loc, gauch$year, drop = TRUE)
  expect_equal(nlevels(gauch$env), 55L)
  expect_equal(nlevels(gauch_composite), 55L)
  expect_equal(
    nlevels(interaction(gauch$env, gauch_composite, drop = TRUE)),
    55L
  )

  australia <- agridat::australia.soybean
  expect_equal(nlevels(australia$env), 8L)
  expect_true(all(table(australia$env, australia$gen) == 1L))

  adugna <- agridat::adugna.sorghum
  adugna_composite <- interaction(adugna$loc, adugna$year, drop = TRUE)
  expect_equal(nlevels(adugna$env), 13L)
  expect_equal(nlevels(adugna_composite), 13L)
  expect_equal(nlevels(adugna$trial), 2L)
  expect_true(all(colSums(table(adugna$trial, adugna$gen) > 0L) == 1L))

  onofri <- agridat::onofri.winterwheat
  expect_equal(length(unique(onofri$year)), 7L)
  expect_equal(nlevels(onofri$gen), 8L)
  expect_true(all(table(onofri$year, onofri$gen) == 3L))
})

test_that("explicit environment paths cover the agridat MET oracle", {
  skip_if_not_installed("agridat")

  cases <- list(
    besag = list(
      data = agridat::besag.met, env = "county", n_env = 6L,
      connectivity = "connected", group_cols = character()
    ),
    gauch = list(
      data = agridat::gauch.soy, env = "env", n_env = 55L,
      connectivity = "connected", group_cols = character()
    ),
    australia = list(
      data = agridat::australia.soybean, env = "env", n_env = 8L,
      connectivity = "connected", group_cols = character()
    ),
    adugna = list(
      data = agridat::adugna.sorghum, env = "env", n_env = 13L,
      connectivity = "connected", group_cols = "trial"
    ),
    onofri = list(
      data = agridat::onofri.winterwheat, env = "year", n_env = 7L,
      connectivity = "connected", group_cols = character()
    )
  )

  for (nm in names(cases)) {
    case <- cases[[nm]]
    ds <- detect_design(case$data, env = case$env)
    expect_true(ds@is_met, info = nm)
    expect_equal(ds@env_cols, case$env, info = nm)
    expect_equal(ds@n_env, case$n_env, info = nm)
    expect_equal(ds@connectivity$status, case$connectivity, info = nm)
    expect_equal(ds@group_cols, case$group_cols, info = nm)
    expect_equal(nrow(ds@per_env), case$n_env, info = nm)
  }
})

test_that("besag.met detects county scope without claiming design recovery", {
  skip_if_not_installed("agridat")
  ds <- detect_design(agridat::besag.met)

  expect_true(ds@is_met)
  expect_equal(ds@env_cols, "county")
  expect_equal(ds@env_method, "site")
  expect_equal(ds@n_env, 6L)
  expect_equal(ds@connectivity$status, "connected")
  expect_equal(nrow(ds@per_env), 6L)
})

test_that("gauch.soy prefers env and supports equivalent loc-year input", {
  skip_if_not_installed("agridat")
  d <- agridat::gauch.soy

  automatic <- detect_design(d)
  explicit_composite <- detect_design(d[, names(d) != "env"],
    env = c("loc", "year")
  )

  expect_true(automatic@is_met)
  expect_equal(automatic@env_cols, "env")
  expect_equal(automatic@env_method, "exact")
  expect_equal(automatic@n_env, 55L)
  expect_true(explicit_composite@is_met)
  expect_equal(explicit_composite@n_env, 55L)
})

test_that("australia.soybean is MET despite unreplicated inner slices", {
  skip_if_not_installed("agridat")
  ds <- detect_design(agridat::australia.soybean)

  expect_true(ds@is_met)
  expect_equal(ds@env_cols, "env")
  expect_equal(ds@n_env, 8L)
  expect_true(ds@within_design_label %in% c("unresolved", "none"))
})

test_that("adugna.sorghum separates environment from trial groups", {
  skip_if_not_installed("agridat")
  ds <- detect_design(agridat::adugna.sorghum)

  expect_true(ds@is_met)
  expect_equal(ds@env_cols, "env")
  expect_equal(ds@n_env, 13L)
  expect_equal(ds@group_cols, "trial")
  expect_equal(ds@connectivity$status, "connected")
  expect_equal(ds@connectivity$components, 1L)
})

test_that("onofri.winterwheat supports an explicit year environment", {
  skip_if_not_installed("agridat")
  ds <- detect_design(agridat::onofri.winterwheat, env = "year")

  expect_true(ds@is_met)
  expect_equal(ds@env_cols, "year")
  expect_equal(ds@n_env, 7L)
})

test_that("single-trial legacy classes remain unchanged when MET is disabled", {
  skip_if_not_installed("agridat")
  fixtures <- list(
    john = agridat::john.alpha,
    yates = agridat::yates.oats,
    gilmour = agridat::gilmour.serpentine
  )
  expected_classes <- c(
    john = "IBD/alpha-lattice",
    yates = "split-plot",
    gilmour = "CRD"
  )

  observed <- vapply(fixtures, function(d) {
    detect_design(d, env = FALSE)@class_label
  }, character(1L))
  expect_identical(observed, expected_classes)
})

test_that("single-trial agridat negatives are not auto-promoted", {
  skip_if_not_installed("agridat")
  fixtures <- list(
    john = agridat::john.alpha,
    yates = agridat::yates.oats,
    gilmour = agridat::gilmour.serpentine
  )

  for (nm in names(fixtures)) {
    ds <- detect_design(fixtures[[nm]])
    expect_true(is.na(ds@is_met), info = nm)
    expect_equal(ds@scope_label, "uncertain", info = nm)
    expect_equal(ds@env_cols, character(), info = nm)
  }
})
