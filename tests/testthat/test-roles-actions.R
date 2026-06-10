# Two-axis roles model: set_role(), default actions, mode re-resolution,
# v1 upgrade, the new roles, and the design + alias opt-out.

test_that("set_role re-roling re-resolves the default action", {
  r <- propose_roles(iris)
  expect_equal(r$action[r$col == "Sepal.Length"], "scramble")
  r <- set_role(r, "Sepal.Length", role = "outcome")
  expect_equal(r$role[r$col == "Sepal.Length"], "outcome")
  expect_equal(r$action[r$col == "Sepal.Length"], "scramble")
})

test_that("set_role with an explicit action pins the column", {
  r <- propose_roles(iris)
  r <- set_role(r, "Sepal.Width", action = "keep")
  expect_equal(r$action[r$col == "Sepal.Width"], "keep")
  # Pinned: re-validating for collaborate must not move it back.
  rv <- suppressMessages(roles_validate(r, iris, mode = "collaborate"))
  expect_equal(rv$action[rv$col == "Sepal.Width"], "keep")
})

test_that("set_role validates inputs", {
  r <- propose_roles(iris)
  expect_error(set_role(r, "nope", role = "outcome"), "not in")
  expect_error(set_role(r, "Species", role = "bogus"), "must be one of")
  expect_error(set_role(r, "Species", action = "bogus"), "must be one of")
  expect_error(set_role(r, "Species"), "at least one")
})

test_that("default actions differ between local and collaborate", {
  rl <- propose_roles(iris, mode = "local")
  rc <- propose_roles(iris, mode = "collaborate")
  # Species detects as a CRD treatment: kept in local, aliased in collaborate.
  expect_equal(rl$action[rl$col == "Species"], "keep")
  expect_equal(rc$action[rc$col == "Species"], "alias")
})

test_that("validating a local table for collaborate re-resolves defaults", {
  r <- propose_roles(iris, mode = "local") # Species -> treatment/keep
  rv <- suppressMessages(roles_validate(r, iris, mode = "collaborate"))
  expect_equal(rv$action[rv$col == "Species"], "alias")
})

test_that("mask(mode=) re-resolves a default-action table to that mode", {
  r <- propose_roles(iris, mode = "local")
  r <- set_role(r, "Sepal.Length", role = "outcome")
  m <- suppressMessages(suppressWarnings(
    mask(iris, r, mode = "collaborate", seed = 1)
  ))
  # Species followed the collaborate default and was aliased.
  expect_true("Species" %in% names(recipe(m)@level_maps))
  expect_true(all(grepl("^trt_", as.character(synthetic(m)$Species))))
})

test_that("no outcome is required: numeric covariates still scramble", {
  r <- propose_roles(mtcars, detect = FALSE)
  expect_true(all(r$role == "covariate"))
  m <- suppressWarnings(mask(mtcars, r, seed = 1))
  s <- synthetic(m)
  expect_equal(dim(s), dim(mtcars))
  expect_false(identical(s$mpg, mtcars$mpg))
})

test_that("design + alias hides labels but keeps structure (opt-out)", {
  set.seed(1)
  df <- data.frame(
    site = factor(rep(c("Roseworthy", "Minnipa", "Turretfield"), each = 6)),
    rep = rep(1:3, 6),
    yield = rnorm(18)
  )
  r <- propose_roles(df, detect = FALSE)
  r <- set_role(r, "site", role = "design", action = "alias")
  m <- suppressWarnings(mask(df, r, seed = 1))
  s <- synthetic(m)
  # Real site names are gone...
  expect_false(any(c("Roseworthy", "Minnipa") %in% as.character(s$site)))
  # ...but the design structure (3 sites, 6 rows each) is intact...
  expect_equal(unname(table(s$site)), unname(table(df$site)))
  # ...and unmask restores the real labels.
  back <- unmask(apply_recipe(df, recipe(m)), recipe(m))
  expect_equal(as.character(back$site), as.character(df$site))
})

test_that("id + alias preserves row linkage across two columns", {
  df <- data.frame(
    plot_id = c("p1", "p2", "p3", "p1", "p2", "p3"),
    rep = rep(1:2, each = 3),
    yield = rnorm(6),
    stringsAsFactors = FALSE
  )
  r <- propose_roles(df, detect = FALSE)
  r <- set_role(r, "plot_id", action = "alias")
  m <- suppressWarnings(mask(df, r, seed = 1))
  s <- synthetic(m)
  # Same value in original rows 1 and 4 -> same alias in the synthetic.
  expect_equal(as.character(s$plot_id)[1], as.character(s$plot_id)[4])
  expect_false(any(c("p1", "p2", "p3") %in% as.character(s$plot_id)))
})

test_that("a numeric id aliased in place round-trips to numeric", {
  df <- data.frame(
    sample_id = c(101L, 102L, 103L, 101L),
    rep = c(1L, 1L, 2L, 2L),
    yield = c(1.1, 2.2, 3.3, 4.4)
  )
  r <- propose_roles(df, detect = FALSE)
  r <- set_role(r, "sample_id", role = "id", action = "alias")
  m <- suppressWarnings(mask(df, r, seed = 1))
  back <- unmask(apply_recipe(df, recipe(m)), recipe(m))
  expect_equal(back$sample_id, df$sample_id)
  expect_type(back$sample_id, "integer")
})

test_that("an all-keep table warns that nothing is masked", {
  r <- propose_roles(iris, detect = FALSE)
  r <- set_role(r, names(iris), action = "keep")
  expect_warning(roles_validate(r, iris), "nothing will be masked")
})

test_that("incompatible role/action combinations are rejected", {
  r <- propose_roles(iris, detect = FALSE)
  # design columns cannot be scrambled
  r2 <- set_role(r, "Species", role = "design", action = "scramble")
  expect_error(roles_validate(r2, iris), "cannot be scrambled")
  # ids cannot be scrambled
  r3 <- set_role(r, "Species", role = "id", action = "scramble")
  expect_error(roles_validate(r3, iris), "cannot be scrambled")
})

test_that("a v1 roles tibble upgrades with a deprecation warning", {
  v1 <- data.frame(
    col = c("Rep", "Genotype", "yield", "note"),
    role = c("design", "treatment", "outcome", "ignore"),
    kind = c("integer", "factor", "numeric", "character"),
    freq_or_range = c("[1,4]", "n=3", "[0,1]", "n=4 unique"),
    pii_suspected = FALSE,
    notes = "v1",
    stringsAsFactors = FALSE
  )
  expect_warning(
    up <- roles_validate(v1, mode = "collaborate"),
    "two-axis"
  )
  expect_true("action" %in% names(up))
  # v1 ignore -> dropped under collaborate; v1 design -> keep.
  expect_equal(up$action[up$col == "note"], "drop")
  expect_equal(up$action[up$col == "Rep"], "keep")
  expect_equal(up$action[up$col == "Genotype"], "alias")
})

test_that("v1 mask_levels = permute upgrades to treatment scramble", {
  v1 <- data.frame(
    col = c("Genotype", "yield"),
    role = c("treatment", "outcome"),
    kind = c("factor", "numeric"),
    freq_or_range = c("n=3", "[0,1]"),
    pii_suspected = FALSE,
    notes = "v1",
    mask_levels = c("permute", "off"),
    stringsAsFactors = FALSE
  )
  up <- suppressWarnings(roles_validate(v1, mode = "local"))
  expect_equal(up$action[up$col == "Genotype"], "scramble")
  expect_false("mask_levels" %in% names(up))
})
