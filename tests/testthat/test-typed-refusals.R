# Typed-refusal completion (2026-08-25 fleet audit, D1 abstention finding).
#
# Every orchestra-facing decline in mask(), mask_set(), unmask() and
# audit_mask() that used to be a bare cli::cli_abort() without a class now
# carries a class ending in `_refusal` plus the shared `orchestra_refusal`
# marker (the naming convention +  opt-in marker defined by
# `ORCHESTRA_dev/integration/refusal_contract.R`), so a conductoR node -- or
# any cross-member caller -- can catch the decline programmatically instead
# of string-matching the message. `masque_unmasked_coords` and
# `masque_conditional_degraded` were already classed and are untouched here.

.expect_refusal <- function(expr, class) {
  err <- tryCatch(expr, error = function(e) e)
  expect_s3_class(err, "error")
  expect_true(inherits(err, class))
  expect_true(inherits(err, "orchestra_refusal"))
  expect_true(any(grepl("_refusal$", class(err))))
}

# --- mask() ------------------------------------------------------------

test_that("mask() refuses an unused/misspelled argument", {
  r <- propose_roles(iris, detect = FALSE)
  .expect_refusal(
    mask(iris, r, seed = 1, boggle = TRUE),
    "masque_unused_arg_refusal"
  )
})

test_that("mask() refuses a non-data-frame `df`", {
  r <- propose_roles(iris, detect = FALSE)
  .expect_refusal(mask(list(), r), "masque_bad_df_refusal")
})

test_that("mask() refuses a non-scalar-logical `conditional`", {
  r <- propose_roles(iris, detect = FALSE)
  .expect_refusal(
    mask(iris, r, seed = 1, conditional = c(TRUE, FALSE)),
    "masque_bad_conditional_refusal"
  )
})

test_that("mask() refuses a non-scalar-logical `allow_unmasked_coords`", {
  r <- propose_roles(iris, detect = FALSE)
  .expect_refusal(
    mask(iris, r, seed = 1, allow_unmasked_coords = c(TRUE, FALSE)),
    "masque_bad_allow_unmasked_coords_refusal"
  )
})

test_that("mask() refuses `alias_names` naming an unknown column", {
  r <- propose_roles(iris, detect = FALSE)
  .expect_refusal(
    mask(iris, r, seed = 1, alias_names = "not_a_column"),
    "masque_bad_alias_names_refusal"
  )
})

test_that("mask() refuses an `alias_names` of the wrong type", {
  r <- propose_roles(iris, detect = FALSE)
  .expect_refusal(
    mask(iris, r, seed = 1, alias_names = 1L),
    "masque_bad_alias_names_refusal"
  )
})

# --- mask_set() ----------------------------------------------------------

.link_set <- function() {
  list(
    trials = data.frame(
      env = rep(c("E1", "E2"), each = 6),
      gen = rep(c("Scope", "Compass", "Spartacus"), 4),
      yield = c(3.1, 2.9, 4.0, 3.7, 5.2, 5.0, 3.3, 2.8, 4.1, 3.6, 5.1, 4.9),
      stringsAsFactors = FALSE
    ),
    pedigree = data.frame(
      gen = c("Scope", "Compass", "Spartacus"),
      maturity = c("early", "mid", "late"),
      stringsAsFactors = FALSE
    )
  )
}

test_that("mask_set() refuses roles tables prepared for conflicting modes", {
  s <- .link_set()
  roles <- list(
    trials = propose_roles(s$trials, mode = "local", detect = FALSE),
    pedigree = propose_roles(s$pedigree, mode = "collaborate", detect = FALSE)
  )
  .expect_refusal(
    mask_set(s, roles = roles, seed = 1, quiet = TRUE),
    "masque_mode_conflict_refusal"
  )
})

test_that("mask_set() refuses a `roles` that is not a named list", {
  s <- .link_set()
  .expect_refusal(
    mask_set(s, roles = list(1, 2), seed = 1, quiet = TRUE),
    "masque_bad_roles_refusal"
  )
})

test_that("mask_set() refuses a `roles` missing a table", {
  s <- .link_set()
  roles <- list(trials = propose_roles(s$trials, detect = FALSE))
  .expect_refusal(
    mask_set(s, roles = roles, seed = 1, quiet = TRUE),
    "masque_roles_missing_table_refusal"
  )
})

test_that("mask_set() refuses `links` naming a column not shared across tables", {
  s <- .link_set()
  .expect_refusal(
    mask_set(s, links = "yield", seed = 1, quiet = TRUE),
    "masque_bad_links_refusal"
  )
})

# --- unmask() --------------------------------------------------------------

.unmask_fixture <- function() {
  set.seed(0)
  df <- data.frame(
    Rep = rep(1:4, 25),
    Genotype = factor(rep(LETTERS[1:5], each = 20)),
    yield = rnorm(100, mean = 10, sd = 2),
    stringsAsFactors = FALSE
  )
  r <- propose_roles(df, detect = FALSE)
  r$role[r$col == "yield"] <- "outcome"
  r$role[r$col == "Genotype"] <- "treatment"
  m <- mask(df, r, mode = "collaborate", seed = 1)
  list(df = df, m = m, rec = recipe(m))
}

test_that("unmask() refuses a `rec` that is not a masque_recipe", {
  .expect_refusal(unmask(1:3, rec = list()), "masque_bad_recipe_refusal")
})

test_that("unmask() refuses an unknown `column` on pass-through atomic input", {
  f <- .unmask_fixture()
  .expect_refusal(
    unmask(1:3, f$rec, column = "not_a_column"),
    "masque_unknown_column_refusal"
  )
})

test_that("unmask() refuses a categorical atomic vector when the recipe holds no level maps", {
  set.seed(0)
  df <- data.frame(
    Rep = rep(1:4, 25),
    yield = rnorm(100, mean = 10, sd = 2),
    stringsAsFactors = FALSE
  )
  r <- propose_roles(df, detect = FALSE)
  r$role[r$col == "yield"] <- "outcome"
  m <- mask(df, r, mode = "collaborate", seed = 1)
  rec <- recipe(m)
  expect_equal(length(rec@level_maps), 0L)
  .expect_refusal(
    unmask(c("a", "b"), rec),
    "masque_no_level_map_refusal"
  )
})

test_that("unmask() refuses ambiguous atomic input with multiple level maps and no `column`", {
  set.seed(0)
  df <- data.frame(
    Rep = rep(1:4, 25),
    Genotype = factor(rep(LETTERS[1:5], each = 20)),
    cov_c = factor(rep(c("alpha", "beta"), 50)),
    yield = rnorm(100, mean = 10, sd = 2),
    stringsAsFactors = FALSE
  )
  r <- propose_roles(df, detect = FALSE)
  r$role[r$col == "yield"] <- "outcome"
  r$role[r$col == "Genotype"] <- "treatment"
  r$role[r$col == "cov_c"] <- "covariate"
  m <- mask(df, r, mode = "collaborate", seed = 1)
  rec <- recipe(m)
  expect_gt(length(rec@level_maps), 1L)
  .expect_refusal(
    unmask(synthetic(m)$Genotype, rec),
    "masque_ambiguous_column_refusal"
  )
})

test_that("unmask() refuses a named `column` that has no level map", {
  f <- .unmask_fixture()
  .expect_refusal(
    unmask(synthetic(f$m)$Genotype, f$rec, column = "yield"),
    "masque_column_no_level_map_refusal"
  )
})

test_that("unmask() refuses `x` that is neither a data frame nor an atomic vector", {
  f <- .unmask_fixture()
  .expect_refusal(unmask(list(a = 1), f$rec), "masque_bad_x_refusal")
})

# --- audit_mask() ----------------------------------------------------------

test_that("audit_mask() refuses an `m` that is not a masque object", {
  .expect_refusal(audit_mask(list()), "masque_bad_masque_obj_refusal")
})

test_that("audit_mask() refuses a local-mode masque with no stored audit and no `original`", {
  r <- propose_roles(iris, detect = FALSE)
  r$role[r$col == "Sepal.Length"] <- "outcome"
  m <- mask(iris, r, mode = "local", seed = 1)
  .expect_refusal(audit_mask(m), "masque_audit_missing_refusal")
})
