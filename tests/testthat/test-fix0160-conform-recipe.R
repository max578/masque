# conform_table() decisions travel on the recipe: apply_recipe() replays the
# effective merge map and the type changes on the original.

state_raw <- function() {
  set.seed(2)
  state <- c(
    rep("NSW", 20), rep("nsw", 5), rep("Nsw", 3), rep("N.S.W.", 2),
    rep("VIC", 15), rep("QLD", 15)
  )
  data.frame(
    rep = rep(1:3, each = 20),
    genotype = rep(sprintf("G%d", 1:4), 15),
    state = sample(state),
    yield = round(stats::rnorm(60, 3, 0.5), 2),
    stringsAsFactors = FALSE
  )
}

state_roles <- function(df, mode, state_action = NULL) {
  r <- propose_roles(df, mode = mode, detect = FALSE)
  r <- set_role(r, "rep", role = "design")
  r <- set_role(r, "genotype", role = "treatment")
  r <- set_role(r, "state", role = "covariate", action = state_action)
  set_role(r, "yield", role = "outcome")
}

state_cf <- function(raw = state_raw()) {
  conform_table(raw, merge_labels = "auto", types = "auto", quiet = TRUE)
}

test_that("mask() records conform decisions with their final targets", {
  cf <- state_cf()
  m <- mask(cf, state_roles(cf$data, "local"), mode = "local", seed = 1)
  rec <- recipe(m)@conform
  expect_type(rec, "list")
  expect_s3_class(rec$merges, "data.frame")
  expect_false(inherits(rec$merges, "data.table"))
  expect_setequal(rec$merges$from, c("nsw", "Nsw"))
  expect_true(all(rec$merges$col == "state"))
  expect_true(all(rec$merges$to == "NSW"))
  expect_setequal(rec$types$col, c("genotype", "state"))
  expect_true(all(rec$types$to == "factor"))
  expect_identical(rec$max_levels, 20L)
  expect_identical(rec$modes$merge_labels, "auto")
  expect_identical(rec$modes$types, "auto")
})

test_that("apply_recipe replays merges and types in local mode", {
  raw <- state_raw()
  cf <- state_cf(raw)
  m <- mask(cf, state_roles(cf$data, "local"), mode = "local", seed = 1)
  fwd <- apply_recipe(raw, recipe(m))
  expect_identical(fwd$state, cf$data$state)
  expect_identical(fwd$genotype, cf$data$genotype)
})

test_that("apply_recipe replays merges and types in collaborate mode", {
  raw <- state_raw()
  cf <- state_cf(raw)
  # Kept: the replayed column equals the conformed one.
  m1 <- mask(cf, state_roles(cf$data, "collaborate", "keep"),
    mode = "collaborate", seed = 1
  )
  expect_identical(apply_recipe(raw, recipe(m1))$state, cf$data$state)

  # Aliased: the replayed column lands on the clone's aliases and unmasks to
  # the conformed labels.
  m2 <- mask(cf, state_roles(cf$data, "collaborate"),
    mode = "collaborate", seed = 1
  )
  rec <- recipe(m2)
  fwd <- apply_recipe(raw, rec)
  expect_identical(fwd$state, apply_recipe(cf$data, rec)$state)
  expect_setequal(
    as.character(unique(fwd$state)),
    as.character(unique(synthetic(m2)$state))
  )
  expect_identical(
    as.character(unmask(fwd, rec)$state), as.character(cf$data$state)
  )
})

test_that("a recipe with no conform decisions replays nothing", {
  raw <- state_raw()
  m <- mask(raw, state_roles(raw, "local"), mode = "local", seed = 1)
  expect_null(recipe(m)@conform)
  expect_identical(apply_recipe(raw, recipe(m))$state, raw$state)
})

test_that("illegal headers and conform decisions replay together", {
  raw <- state_raw()
  names(raw) <- c("Rep", "Genotype", "State Name", "Yield (t/ha)")
  cf <- suppressWarnings(
    conform_table(raw, merge_labels = "auto", types = "auto", quiet = TRUE)
  )
  r <- propose_roles(cf$data, mode = "local", detect = FALSE)
  r <- set_role(r, "Rep", role = "design")
  r <- set_role(r, "Genotype", role = "treatment")
  r <- set_role(r, "Yield..t.ha.", role = "outcome")
  m <- mask(cf, r, mode = "local", seed = 1)
  rec <- recipe(m)
  fwd <- apply_recipe(raw, rec)
  expect_identical(names(fwd), names(synthetic(m)))
  expect_identical(fwd$State.Name, cf$data$State.Name)
  expect_identical(names(unmask(synthetic(m), rec)), names(raw))
})

test_that("mask_set() takes a conformance object per table and replays it", {
  raw <- state_raw()
  cf <- state_cf(raw)
  other <- data.frame(
    genotype = sprintf("G%d", 1:4), height = c(80, 95, 102, 88),
    stringsAsFactors = FALSE
  )
  ro <- propose_roles(other, mode = "local", detect = FALSE)
  ro <- set_role(ro, "genotype", role = "treatment")
  roles <- list(trial = state_roles(cf$data, "local"), lines = ro)
  m <- mask_set(list(trial = cf, lines = other), roles = roles,
    mode = "local", seed = 1, quiet = TRUE
  )
  expect_false(is.null(recipe(m)@recipes$trial@conform))
  fwd <- apply_recipe(list(trial = raw, lines = other), recipe(m))
  expect_identical(fwd$trial$state, cf$data$state)
})

colour_frame <- function() {
  data.frame(
    colour = c(rep("color", 5), rep("colour", 5), "colur", rep("red", 4)),
    stringsAsFactors = FALSE
  )
}

test_that("a source with two candidate targets is not merged", {
  expect_warning(
    cf <- conform_table(
      colour_frame(), merge_labels = "auto", types = "auto", quiet = TRUE
    ),
    class = "masque_conform_ambiguous_merge"
  )
  expect_true(all(c("color", "colour", "colur") %in% cf$data$colour))
  amb <- cf$merges[cf$merges$from == "colur", , drop = FALSE]
  expect_gt(nrow(amb), 0L)
  expect_true(all(!amb$applied))
  expect_true(all(grepl("more than one", amb$reason)))
  expect_false("colur" %in% cf$merge_map$from)
})

test_that("merges follow chains to the label left in the data", {
  cf <- state_cf()
  expect_setequal(cf$merge_map$from, c("nsw", "Nsw"))
  expect_true(all(cf$merge_map$to == "NSW"))
  expect_true(all(cf$merge_map$to %in% as.character(cf$data$state)))
})

test_that("types = 'off' still merges categories and leaves storage alone", {
  raw <- state_raw()
  cf <- conform_table(raw, merge_labels = "auto", types = "off", quiet = TRUE)
  expect_type(cf$data$state, "character")
  expect_false(any(c("nsw", "Nsw") %in% cf$data$state))
  expect_equal(nrow(cf$types), 0L)
  # Numbers held as text are still not categories.
  num <- data.frame(y = c("3.1", "4.2", "4.4", "4.4", "5.0"))
  cn <- conform_table(num, merge_labels = "auto", types = "off", quiet = TRUE)
  expect_equal(nrow(cn$merges), 0L)
  expect_identical(cn$data$y, num$y)
})

test_that("a recipe saved before the conform property existed still applies", {
  raw <- state_raw()
  rec <- recipe(mask(raw, state_roles(raw, "local"), mode = "local", seed = 1))
  # Rebuild the object as an older masque wrote it: the class definition it
  # carries has no `conform` property and the attribute is absent.
  cls <- attr(rec, "S7_class")
  old_cls <- S7::new_class(
    "masque_recipe", package = "masque",
    properties = cls@properties[setdiff(names(cls@properties), "conform")]
  )
  old <- rec
  attr(old, "conform") <- NULL
  attr(old, "S7_class") <- old_cls
  expect_error(old@conform)
  expect_identical(apply_recipe(raw, old), apply_recipe(raw, rec))
})

test_that("masque() takes a conformance object as one table or in a set", {
  raw <- state_raw()
  cf <- state_cf(raw)
  m <- masque(cf, roles = state_roles(cf$data, "local"), mode = "local",
    seed = 1, ask = FALSE, quiet = TRUE
  )
  expect_true(S7::S7_inherits(m, masque_obj))
  expect_identical(apply_recipe(raw, recipe(m))$state, cf$data$state)

  ms <- masque(list(trial = cf), mode = "local", seed = 1, ask = FALSE,
    quiet = TRUE
  )
  expect_true(S7::S7_inherits(ms, masque_set))
  expect_false(is.null(recipe(ms)@recipes$trial@conform))
})
