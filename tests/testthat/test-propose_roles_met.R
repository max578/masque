# MET role/action safety contract.

test_that("site-like county is promoted without scrambling allocation", {
  d <- met_county_fixture()

  roles <- propose_roles(d, mode = "local")
  county <- roles[roles$col == "county", ]
  expect_equal(county$role, "design")
  expect_equal(county$action, "keep")

  roles$role[roles$col == "yield"] <- "outcome"
  masked <- suppressWarnings(mask(d, roles, seed = 101L))
  expect_identical(synthetic(masked)$county, d$county)
  expect_identical(
    table(synthetic(masked)$county, synthetic(masked)$gen),
    table(d$county, d$gen)
  )
})

test_that("categorical environment aliases in collaborate mode", {
  d <- met_complete_fixture()
  roles <- propose_roles(d, mode = "collaborate")
  env_role <- roles[roles$col == "env", ]

  expect_equal(env_role$role, "design")
  expect_equal(env_role$action, "alias")

  roles$role[roles$col == "yield"] <- "outcome"
  masked <- suppressWarnings(mask(d, roles,
    mode = "collaborate", seed = 102L
  ))
  out <- synthetic(masked)

  expect_false(identical(levels(out$env), levels(d$env)))
  expect_identical(as.integer(out$env), as.integer(d$env))
  expect_identical(dim(table(out$env, out$gen)), dim(table(d$env, d$gen)))
})

test_that("numeric environment retention is disclosed in collaborate mode", {
  d <- met_site_year_fixture()

  expect_warning(
    roles <- propose_roles(d, mode = "collaborate"),
    regexp = "numeric environment|year.*keep|disclosure",
    class = "masque_environment_disclosure"
  )
  year_role <- roles[roles$col == "year", ]
  expect_equal(year_role$role, "design")
  expect_equal(year_role$action, "keep")
})

test_that("uncertain candidates are preserved as design/keep, never auto-aliased", {
  d <- ambiguous_site_fixture()
  roles <- propose_roles(d, mode = "collaborate")
  ds <- attr(roles, "design")

  expect_true(is.na(ds@is_met))
  expect_equal(ds@scope_label, "uncertain")
  # A weak or ambiguous environment candidate is preserved as design/keep so a
  # default mask() cannot silently scramble it, but it is never auto-aliased.
  cand <- ds@recommended_roles[
    ds@recommended_roles$col %in% c("site", "location"), , drop = FALSE
  ]
  expect_true(all(cand$auto_apply))
  expect_true(all(cand$role == "design"))
  expect_true(all(cand$action_local == "keep"))
  expect_true(all(cand$action_collaborate == "keep"))
  applied <- roles[roles$col %in% c("site", "location"), , drop = FALSE]
  expect_true(all(applied$role == "design"))
  expect_true(all(applied$action == "keep"))
})

test_that("environment recommendations expose the additive schema", {
  detected <- detect_design(met_complete_fixture())
  expect_named(detected@recommended_roles, c(
    "col", "role", "action_local", "action_collaborate",
    "confidence", "source", "auto_apply", "reason"
  ))
  env_rec <- detected@recommended_roles[
    detected@recommended_roles$col == "env", , drop = FALSE
  ]
  expect_equal(env_rec$role, "design")
  expect_equal(env_rec$action_local, "keep")
  expect_equal(env_rec$action_collaborate, "alias")
  expect_true(env_rec$auto_apply)

  ambiguous <- detect_design(ambiguous_site_fixture())
  ambiguous_env <- ambiguous@recommended_roles[
    ambiguous@recommended_roles$source == "environment_auto", , drop = FALSE
  ]
  expect_setequal(ambiguous_env$col, c("site", "location"))
  expect_true(all(ambiguous_env$auto_apply))
  expect_true(all(ambiguous_env$action_collaborate == "keep"))

  ordinary <- detect_design(iris)
  expect_named(ordinary@recommended_roles, names(.empty_role_recommendations()))
  legacy <- detect_design(iris, env = FALSE)
  expect_named(legacy@recommended_roles, c("col", "role"))
})

test_that("equivalent environment encodings suppress false treatment hints", {
  skip_if_not_installed("agridat")
  ds <- detect_design(agridat::gauch.soy)
  rec <- ds@recommended_roles[
    ds@recommended_roles$col %in% c("env", "loc", "year"), , drop = FALSE
  ]

  expect_setequal(rec$col, c("env", "loc", "year"))
  expect_true(all(rec$role == "design"))
  expect_true(all(rec$auto_apply))
  expect_setequal(ds@evidence$environment$supporting_cols, c("loc", "year"))
})

test_that("explicitly edited actions remain pinned during overlay", {
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

test_that("composite MET structure and recipe round-trip hold in both modes", {
  d <- met_site_year_fixture()
  original_incidence <- table(
    interaction(d$site, d$year, drop = TRUE), d$gen
  )

  for (mode in c("local", "collaborate")) {
    roles <- if (mode == "collaborate") {
      expect_warning(
        roles <- propose_roles(d, mode = mode),
        class = "masque_environment_disclosure"
      )
      roles
    } else {
      propose_roles(d, mode = mode)
    }
    roles$role[roles$col == "yield"] <- "outcome"
    masked <- suppressWarnings(mask(d, roles, mode = mode, seed = 103L))
    out <- synthetic(masked)

    expect_identical(as.integer(out$site), as.integer(d$site), info = mode)
    expect_identical(out$year, d$year, info = mode)
    expect_identical(as.integer(out$gen), as.integer(d$gen), info = mode)
    expect_identical(
      unname(table(
        interaction(out$site, out$year, drop = TRUE), out$gen
      )),
      unname(original_incidence),
      info = mode
    )

    forward <- apply_recipe(d, recipe(masked))
    back <- unmask(forward, recipe(masked))
    expect_identical(as.character(back$site), as.character(d$site),
      info = mode
    )
    expect_identical(back$year, d$year, info = mode)
    expect_identical(as.character(back$gen), as.character(d$gen),
      info = mode
    )
  }
})
