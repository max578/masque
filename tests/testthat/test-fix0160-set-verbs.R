# F15: save_recipe(), read_recipe(), reveal_maps() and audit_mask() accept the
# recipe bundle and the masque_set that masque() and mask_set() return.

.verbs_tables <- function() {
  set.seed(15L)
  plots <- data.frame(
    site = factor(rep(c("Alpha", "Bravo", "Charlie"), each = 24L)),
    rep = rep(rep(1:3, each = 8L), 3L),
    gen = factor(rep(sprintf("Line%02d", 1:8), 9L)),
    yield = round(rnorm(72L, 5, 0.6), 2)
  )
  sites <- data.frame(
    site = factor(rep(c("Alpha", "Bravo", "Charlie"), 3L)),
    year = rep(2018:2020, each = 3L),
    rain = round(rnorm(9L, 450, 60))
  )
  list(plots = plots, sites = sites)
}

.verbs_roles <- function(df, mode) {
  r <- propose_roles(df, mode = mode)
  for (col in names(df)) {
    spec <- switch(col,
      site = list(role = "design", action = "alias"),
      rep = list(role = "design", action = "keep"),
      year = list(role = "design", action = "keep"),
      gen = list(role = "treatment", action = "alias"),
      yield = list(role = "outcome", action = "scramble"),
      rain = list(role = "covariate", action = "scramble")
    )
    r <- set_role(r, col, role = spec$role, action = spec$action)
  }
  r
}

.verbs_set <- function(mode = "collaborate") {
  tables <- .verbs_tables()
  roles <- lapply(tables, .verbs_roles, mode = mode)
  mask_set(tables, roles = roles, mode = mode, seed = 15L, quiet = TRUE)
}

test_that("save_recipe() and read_recipe() round-trip a recipe bundle", {
  bundle <- recipe(.verbs_set())
  path <- withr::local_tempfile(fileext = ".rds")
  expect_identical(save_recipe(bundle, path), path)
  back <- read_recipe(path)
  expect_true(S7::S7_inherits(back, masque:::masque_recipe_set))
  expect_equal(back, bundle)
  expect_identical(names(back@recipes), names(bundle@recipes))
  expect_identical(back@links, bundle@links)
  for (nm in names(bundle@recipes)) {
    expect_identical(
      back@recipes[[nm]]@level_maps, bundle@recipes[[nm]]@level_maps
    )
    expect_identical(back@recipes[[nm]]@seed, bundle@recipes[[nm]]@seed)
  }
})

test_that("a read bundle retargets the original tables as the live one does", {
  ms <- .verbs_set()
  path <- withr::local_tempfile(fileext = ".rds")
  save_recipe(recipe(ms), path)
  tables <- .verbs_tables()
  expect_equal(
    apply_recipe(tables, read_recipe(path)),
    apply_recipe(tables, recipe(ms))
  )
})

test_that("read_recipe() names the class it found in a wrong file", {
  path <- withr::local_tempfile(fileext = ".rds")
  saveRDS(iris, path)
  err <- expect_error(read_recipe(path), class = "orchestra_refusal")
  expect_s3_class(err, "masque_bad_recipe_file_refusal")
  msg <- conditionMessage(err)
  expect_match(msg, "data.frame", fixed = TRUE)
  expect_match(msg, "masque_recipe_set", fixed = TRUE)
  expect_match(msg, "0.16.0", fixed = TRUE)
})

test_that("read_recipe() names the class and both versions on a mismatch", {
  bundle <- recipe(.verbs_set())
  bundle@masque_version <- "0.0.9"
  path <- withr::local_tempfile(fileext = ".rds")
  saveRDS(bundle, path)
  msgs <- testthat::capture_messages(back <- read_recipe(path))
  joined <- paste(msgs, collapse = "\n")
  expect_match(joined, "masque_recipe_set", fixed = TRUE)
  expect_match(joined, "0.0.9", fixed = TRUE)
  expect_match(
    joined, as.character(utils::packageVersion("masque")), fixed = TRUE
  )
  expect_true(S7::S7_inherits(back, masque:::masque_recipe_set))
})

test_that("reveal_maps() on a bundle reveals each table, or the one named", {
  bundle <- recipe(.verbs_set())
  all_tables <- capture_full(reveal_maps(bundle))
  expect_match(all_tables, "Revealing sensitive")
  expect_match(all_tables, "plots", fixed = TRUE)
  expect_match(all_tables, "sites", fixed = TRUE)
  expect_match(all_tables, "Alpha", fixed = TRUE)
  expect_match(all_tables, "Line03", fixed = TRUE)

  # The genotype map lives on the plots table only.
  one <- capture_full(reveal_maps(bundle, table = "sites"))
  expect_match(one, "Alpha", fixed = TRUE)
  expect_false(grepl("Line03", one, fixed = TRUE))

  expect_invisible(reveal_maps(bundle, table = "plots"))
  expect_error(
    reveal_maps(bundle, table = "nope"),
    class = "masque_bad_table_refusal"
  )
  expect_error(
    reveal_maps(bundle@recipes$plots, table = "plots"),
    class = "masque_bad_table_refusal"
  )
})

test_that("audit_mask() on a collaborate set returns and prints one audit per table", {
  ms <- .verbs_set()
  out <- audit_mask(ms, print = FALSE)
  expect_type(out, "list")
  expect_identical(names(out), c("plots", "sites"))
  for (nm in names(out)) {
    expect_s3_class(out[[nm]], "data.table")
    expect_identical(out[[nm]]$col, names(.verbs_tables()[[nm]]))
  }
  printed <- capture_full(audit_mask(ms))
  expect_match(printed, "masque audit", fixed = TRUE)
  expect_match(printed, "plots", fixed = TRUE)
  expect_match(printed, "sites", fixed = TRUE)
})

test_that("audit_mask() on a local set takes the originals as a named list", {
  ms <- .verbs_set(mode = "local")
  expect_error(audit_mask(ms), class = "masque_audit_missing_refusal")
  tables <- .verbs_tables()
  out <- audit_mask(ms, original = tables, print = FALSE)
  expect_identical(names(out), names(tables))
  expect_s3_class(out$plots, "data.table")
  # Each table's audit equals the single-table audit of that table's clone.
  single <- masque:::.compute_audit(
    tables$sites, synthetic(ms)$sites, recipe(ms)@recipes$sites, "local"
  )
  expect_equal(out$sites, single, ignore_attr = TRUE)

  expect_error(
    audit_mask(ms, original = tables$plots),
    class = "masque_bad_original_refusal"
  )
  expect_error(
    audit_mask(ms, original = tables["plots"]),
    class = "masque_bad_original_refusal"
  )
})

test_that("audit_mask(original =) reads through aliased and repaired column names", {
  r <- propose_roles(iris)
  r <- set_role(r, "Sepal.Length", role = "outcome")
  m <- mask(iris, r, mode = "local", seed = 1L, alias_names = TRUE)
  a <- audit_mask(m, original = iris, print = FALSE)
  expect_false(any(a$alias_status == "dropped"))
  expect_true(is.finite(a$exact_match_pct[a$col == "Sepal.Length"]))

  d <- data.frame(
    `Site Name` = rep(c("north", "south"), 10L),
    y = seq_len(20L) / 4,
    check.names = FALSE
  )
  r2 <- propose_roles(d)
  r2 <- set_role(r2, "Site Name", role = "design", action = "keep")
  r2 <- set_role(r2, "y", role = "outcome", action = "scramble")
  m2 <- suppressWarnings(mask(d, r2, mode = "local", seed = 1L))
  a2 <- audit_mask(m2, original = d, print = FALSE)
  expect_identical(a2$n_unique_levels[a2$col == "Site.Name"], 2L)
})

test_that("audit_mask(original =) refuses an original that is not a table", {
  r <- propose_roles(iris)
  r <- set_role(r, "Sepal.Length", role = "outcome")
  m <- mask(iris, r, mode = "local", seed = 1L)
  expect_error(
    audit_mask(m, original = list(iris)),
    class = "masque_bad_original_refusal"
  )
})
