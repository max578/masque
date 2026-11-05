# masque_plan(): mask(df, plan), resolution, translation, both control sides.

.fx_plan_table <- function() {
  withr::with_seed(11L, {
    d <- expand.grid(
      site = c("Adelong", "Booleroo"), rep = c("R1", "R2", "R3"),
      block = paste0("B", 1:4), plot = 1:5,
      stringsAsFactors = FALSE
    )
    n <- nrow(d)
    d$block <- paste(d$site, d$rep, d$block, sep = "_")
    d$gen <- NA_character_
    for (k in unique(paste(d$site, d$rep))) {
      i <- which(paste(d$site, d$rep) == k)
      d$gen[i] <- sample(rep(paste0("Variety", 1:10), 2L))
    }
    d$yield <- 10 + stats::rnorm(n)
    d$yield[c(5L, 90L)] <- NA
    d$plot <- NULL
    d
  })
}

.fx_plan_roles <- function(d) {
  r <- propose_roles(d, mode = "local", detect = FALSE)
  r <- set_role(r, c("site", "rep", "block"), role = "design", action = "keep")
  r <- set_role(r, "gen", role = "treatment", action = "alias")
  set_role(r, "yield", role = "outcome", action = "scramble")
}

.fx_spec <- function(...) {
  control_spec(on = "gen", target = "yield", effect = list(sd = 0.5), n = 4L,
               seed = 77L, ...)
}

test_that("mask(df, plan) equals mask() with the same arguments", {
  d <- .fx_plan_table()
  r <- .fx_plan_roles(d)
  p <- masque_plan(r, conditional = "design", grain = FALSE)
  a <- suppressWarnings(mask(d, p, seed = 3L, quiet = TRUE))
  b <- suppressWarnings(mask(d, r, seed = 3L, quiet = TRUE,
                             conditional = "design", grain = FALSE))
  expect_identical(synthetic(a), synthetic(b))
})

test_that("an argument passed to mask() overrides the plan", {
  d <- .fx_plan_table()
  r <- .fx_plan_roles(d)
  p <- masque_plan(r, conditional = TRUE)
  a <- suppressWarnings(mask(d, p, seed = 3L, quiet = TRUE, conditional = FALSE))
  b <- suppressWarnings(mask(d, r, seed = 3L, quiet = TRUE))
  expect_identical(synthetic(a), synthetic(b))
  expect_false(recipe(a)@plan@conditional)
})

test_that("the clone is identical with and without a control spec", {
  d <- .fx_plan_table()
  r <- .fx_plan_roles(d)
  a <- mask(d, masque_plan(r), seed = 5L, quiet = TRUE)
  b <- mask(d, masque_plan(r, controls = .fx_spec()), seed = 5L, quiet = TRUE)
  expect_identical(synthetic(a), synthetic(b))
})

test_that("mask() resolves unit, strata, effect on the source and writes back", {
  d <- .fx_plan_table()
  m <- mask(d, masque_plan(.fx_plan_roles(d), controls = .fx_spec()),
            seed = 5L, quiet = TRUE)
  s <- recipe(m)@plan@controls$default
  # Every site and rep holds every variety; a block does not.
  expect_setequal(s@strata, c("site", "rep"))
  expect_length(s@unit, 0L)
  expect_true(is.numeric(s@effect))
  expect_setequal(names(s@effect), paste0("Variety", 1:10))
  again <- mask(d, masque_plan(.fx_plan_roles(d), controls = .fx_spec()),
                seed = 99L, quiet = TRUE)
  expect_identical(recipe(again)@plan@controls$default@effect, s@effect)
})

test_that("a whole-plot unit and declared strata resolve", {
  d <- .fx_plan_table()
  d$irrig <- ifelse(as.integer(factor(d$block)) %% 2L == 0L, "wet", "dry")
  r <- .fx_plan_roles(d)
  r <- set_role(r, "gen", role = "covariate", action = "scramble")
  r <- set_role(r, "irrig", role = "treatment", action = "keep")
  p <- masque_plan(r, controls = control_spec(on = "irrig", n = 2L, seed = 1L))
  m <- suppressWarnings(mask(d, p, seed = 5L, quiet = TRUE))
  s <- recipe(m)@plan@controls$default
  expect_identical(s@unit, "block")
  expect_setequal(s@strata, c("site", "rep"))

  p2 <- masque_plan(r, controls = control_spec(
    on = "irrig", strata = "site", unit = "block", n = 2L, seed = 1L
  ))
  m2 <- suppressWarnings(mask(d, p2, seed = 5L, quiet = TRUE))
  expect_identical(recipe(m2)@plan@controls$default@strata, "site")
})

test_that("a spec the source cannot honour is refused at mask()", {
  d <- .fx_plan_table()
  r <- .fx_plan_roles(d)
  bad <- masque_plan(r, controls = control_spec(on = "yield", n = 2L, seed = 1L))
  expect_error(mask(d, bad, seed = 1L, quiet = TRUE), class = "orchestra_refusal")
  bad2 <- masque_plan(r, controls = control_spec(
    on = "gen", strata = "nope", n = 2L, seed = 1L
  ))
  expect_error(mask(d, bad2, seed = 1L, quiet = TRUE), class = "orchestra_refusal")
})

test_that("the clone plan is in clone vocabulary, with nothing of the source", {
  d <- .fx_plan_table()
  r <- .fx_plan_roles(d)
  m <- suppressWarnings(mask(
    d, masque_plan(r, controls = .fx_spec(), alias_names = TRUE),
    seed = 5L, quiet = TRUE
  ))
  cp <- clone_plan(m)
  expect_identical(cp@vocabulary, "clone")
  s <- cp@controls$default
  expect_true(all(c(s@on, s@target, s@strata) %in% names(synthetic(m))))
  expect_false(any(c("gen", "yield", "site", "rep") %in% c(s@on, s@target, s@strata)))
  clone_on <- as.character(synthetic(m)[[s@on]])
  expect_setequal(names(s@effect), unique(clone_on))
  expect_false(any(grepl("Variety", names(s@effect))))
  expect_length(cp@coords, 0L)
  # Falsifier: the source plan does hold the source vocabulary.
  expect_true(any(grepl("Variety", names(recipe(m)@plan@controls$default@effect))))
})

test_that("the effect means the same variety on both sides", {
  d <- .fx_plan_table()
  m <- mask(d, masque_plan(.fx_plan_roles(d), controls = .fx_spec()),
            seed = 5L, quiet = TRUE)
  src <- recipe(m)@plan@controls$default@effect
  cln <- clone_plan(m)@controls$default@effect
  map <- recipe(m)@level_maps$gen
  expect_equal(unname(cln[unname(map[names(src)])]), unname(src))
})

test_that("the analyst's controls run on the clone from the clone plan", {
  d <- .fx_plan_table()
  m <- mask(d, masque_plan(.fx_plan_roles(d), controls = .fx_spec()),
            seed = 5L, quiet = TRUE)
  ctl <- controls(synthetic(m), clone_plan(m))
  neg <- control_table(ctl, "negative", 2L)
  s <- synthetic(m)
  expect_identical(neg$site, s$site)
  expect_identical(is.na(neg$yield), is.na(s$yield))
  tab <- function(x) table(x$site, x$rep, x$gen)
  expect_identical(tab(neg), tab(s))
  expect_false(identical(neg$gen, s$gen))
  pos <- control_table(ctl, "positive", 2L)
  shift <- pos$yield - neg$yield
  eff <- ctl@spec@effect
  expect_equal(
    tapply(shift, pos$gen, mean, na.rm = TRUE)[names(eff)],
    eff * stats::sd(s$yield, na.rm = TRUE),
    ignore_attr = TRUE
  )
})

test_that("the owner's controls take a private seed and the real table", {
  d <- .fx_plan_table()
  m <- mask(d, masque_plan(.fx_plan_roles(d), controls = .fx_spec()),
            seed = 5L, quiet = TRUE)
  cp <- clone_plan(m)
  rec <- recipe(m)
  own <- controls(d, cp, recipe = rec)
  ana <- controls(synthetic(m), cp)
  # The seeds differ, and neither is the other's permutation.
  expect_false(identical(own@seeds, ana@seeds))
  expect_false(identical(own@seeds, as.integer(.sub_seeds(77L, 5L))))
  # The owner's table is the real one, in real labels.
  n1 <- control_table(own, "negative", 1L)
  expect_setequal(unique(n1$gen), paste0("Variety", 1:10))
  expect_identical(sort(n1$yield), sort(d$yield))
  expect_true(any(grepl("private", own@notes)))
  # Source plan and clone plan give the same owner's object.
  own2 <- controls(d, rec@plan, recipe = rec)
  expect_identical(own2@seeds, own@seeds)
  expect_identical(own2@spec@effect, own@spec@effect)
})

test_that("the source side refuses what it should", {
  d <- .fx_plan_table()
  m <- mask(d, masque_plan(.fx_plan_roles(d), controls = .fx_spec()),
            seed = 5L, quiet = TRUE)
  cp <- clone_plan(m)
  rec <- recipe(m)

  # A source plan without a recipe would permute real rows under a public seed.
  expect_error(controls(d, rec@plan), class = "masque_control_source_plan_refusal")
  # The spec's seed is the analyst's.
  expect_error(controls(d, cp, recipe = rec, seed = 77L),
               class = "masque_control_seed_refusal")
  # A different NA mask is a different table.
  other <- d
  other$yield[1L] <- NA
  expect_error(controls(other, cp, recipe = rec), class = "masque_integrity_refusal")
  # A missing column.
  gone <- d
  gone$rep <- NULL
  expect_error(controls(gone, cp, recipe = rec), class = "masque_control_mismatch_refusal")
  # A spec changed after the clone was made.
  changed <- cp
  s <- changed@controls$default
  s@n <- 9L
  changed@controls$default <- s
  expect_error(controls(d, changed, recipe = rec),
               class = "masque_control_spec_changed_refusal")
  # A recipe with a plain roles table.
  expect_error(
    controls(d, .fx_plan_roles(d), .fx_spec(), recipe = rec),
    class = "masque_control_recipe_refusal"
  )
  # No recipe seed and no private seed.
  m0 <- mask(d, masque_plan(.fx_plan_roles(d), controls = .fx_spec()), quiet = TRUE)
  expect_error(
    controls(d, clone_plan(m0), recipe = recipe(m0)),
    class = "masque_control_seed_refusal"
  )
  own <- controls(d, clone_plan(m0), recipe = recipe(m0), seed = 123L)
  expect_true(S7::S7_inherits(own, masque_controls))
})

test_that("cleaning is replayed on the owner's table", {
  d <- .fx_plan_table()
  names(d)[names(d) == "yield"] <- "yield t/ha"
  expect_warning(
    cl <- clean_table(d, quiet = TRUE)$data,
    class = "masque_name_repaired"
  )
  yield_col <- setdiff(names(cl), c("site", "rep", "block", "gen"))
  r <- propose_roles(cl, mode = "local", detect = FALSE)
  r <- set_role(r, c("site", "rep", "block"), role = "design", action = "keep")
  r <- set_role(r, "gen", role = "treatment", action = "alias")
  r <- set_role(r, yield_col, role = "outcome", action = "scramble")
  spec <- control_spec(on = "gen", target = yield_col, effect = list(sd = 0.5),
                       n = 2L, seed = 77L)
  m <- suppressWarnings(mask(d, masque_plan(r, controls = spec), seed = 5L, quiet = TRUE))
  own <- suppressWarnings(controls(d, clone_plan(m), recipe = recipe(m)))
  expect_true(yield_col %in% names(control_table(own, "negative", 1L)))
})

test_that("several named specs are picked by name", {
  d <- .fx_plan_table()
  specs <- list(
    a = .fx_spec(),
    b = control_spec(on = "gen", n = 2L, seed = 8L)
  )
  m <- mask(d, masque_plan(.fx_plan_roles(d), controls = specs), seed = 5L, quiet = TRUE)
  cp <- clone_plan(m)
  expect_error(controls(synthetic(m), cp), class = "masque_control_spec_refusal")
  expect_error(controls(synthetic(m), cp, "c"), class = "masque_control_spec_refusal")
  expect_identical(controls(synthetic(m), cp, "b")@spec@n, 2L)
})

test_that("a plan refuses bad input and the wrong verb", {
  d <- .fx_plan_table()
  r <- .fx_plan_roles(d)
  expect_error(masque_plan(1), class = "masque_plan_roles_refusal")
  expect_error(masque_plan(r[, c("col", "role")]), class = "masque_plan_roles_refusal")
  expect_error(masque_plan(r, conditional = 2), class = "masque_bad_conditional_refusal")
  expect_error(masque_plan(r, grain = NA), class = "masque_plan_grain_refusal")
  expect_error(masque_plan(r, controls = list(1)), class = "masque_plan_controls_refusal")
  expect_error(masque(d, roles = masque_plan(r)), class = "masque_plan_unsupported_refusal")
  m <- mask(d, masque_plan(r), seed = 1L, quiet = TRUE)
  expect_error(mask(d, clone_plan(m)), class = "masque_plan_vocabulary_refusal")
  expect_error(clone_plan(1), class = "masque_bad_masque_obj_refusal")
})

test_that("a plan with no spec still gives a clone plan and refuses controls", {
  d <- .fx_plan_table()
  m <- suppressWarnings(mask(d, .fx_plan_roles(d), seed = 1L, quiet = TRUE))
  cp <- clone_plan(m)
  expect_length(cp@controls, 0L)
  expect_error(controls(synthetic(m), cp), class = "masque_control_spec_refusal")
})

test_that("printing a plan shows no seed and no level", {
  d <- .fx_plan_table()
  m <- mask(d, masque_plan(.fx_plan_roles(d), controls = .fx_spec()),
            seed = 5L, quiet = TRUE)
  out <- paste(cli::cli_fmt(print(clone_plan(m))), collapse = "\n")
  expect_match(out, "clone vocabulary")
  expect_match(out, "default")
  expect_false(grepl("Variety|77", out))
})

test_that("a plan round-trips through YAML, with awkward labels", {
  skip_if_not_installed("yaml")
  d <- .fx_plan_table()
  awkward <- c("NA", "yes", "1", "0.5", "a: b", "true", "~", "null", "#x", "é")
  labs <- stats::setNames(c(awkward), paste0("Variety", 1:10))
  d$gen <- unname(labs[d$gen])
  r <- .fx_plan_roles(d)
  r <- set_role(r, "gen", role = "treatment", action = "keep")
  m <- mask(d, masque_plan(r, conditional = "design", controls = .fx_spec()),
            seed = 5L, quiet = TRUE)
  src <- recipe(m)@plan
  f <- withr::local_tempfile(fileext = ".yaml")
  save_plan(src, f)
  back <- read_plan(f)
  expect_identical(back@controls$default@effect, src@controls$default@effect)
  expect_identical(back@controls$default@strata, src@controls$default@strata)
  expect_identical(back@conditional, src@conditional)
  expect_identical(back@roles$col, src@roles$col)
  expect_identical(back@roles$action, src@roles$action)
  expect_identical(back@vocabulary, "source")
  expect_identical(back@mode, "local")
  a <- suppressWarnings(mask(d, back, seed = 5L, quiet = TRUE))
  expect_identical(synthetic(a), synthetic(m))

  # The owner's spec check holds after a round trip of the clone plan.
  g <- withr::local_tempfile(fileext = ".yaml")
  save_plan(clone_plan(m), g)
  own <- controls(d, read_plan(g), recipe = recipe(m))
  expect_true(S7::S7_inherits(own, masque_controls))
})

test_that("reading and writing refuse what they cannot do", {
  skip_if_not_installed("yaml")
  d <- .fx_plan_table()
  r <- .fx_plan_roles(d)
  f <- withr::local_tempfile(fileext = ".yaml")
  expect_error(save_plan(r, f), class = "masque_plan_class_refusal")
  expect_error(save_plan(masque_plan(r), "a.csv"), class = "masque_plan_file_refusal")
  expect_error(read_plan("nope.yaml"), class = "masque_plan_file_refusal")
  writeLines("a: 1", f)
  expect_error(read_plan(f), class = "masque_plan_file_refusal")
  writeLines("a: [", f)
  expect_error(read_plan(f), class = "masque_plan_file_refusal")
  p <- masque_plan(r, coords = list(lat = "a", lon = "b", on_land = function(lon, lat) TRUE))
  expect_error(save_plan(p, f), class = "masque_plan_file_refusal")
})

test_that("handover writes four files and no source vocabulary", {
  skip_if_not_installed("yaml")
  d <- .fx_plan_table()
  r <- set_role(.fx_plan_roles(d), c("site", "block"), action = "alias")
  m <- suppressWarnings(mask(
    d, masque_plan(r, controls = .fx_spec(), alias_names = TRUE),
    seed = 5L, quiet = TRUE
  ))
  dir <- withr::local_tempdir()
  out <- file.path(dir, "pack")
  paths <- handover(m, out)
  expect_setequal(basename(paths), c("clone.csv", "plan.yaml", "card.yaml", "README.txt"))
  expect_setequal(list.files(out), basename(paths))
  text <- unlist(lapply(paths, readLines))
  for (w in c("Variety", "Adelong", "Booleroo", "yield")) {
    expect_false(any(grepl(w, text, fixed = TRUE)), info = w)
  }
  # Falsifier: the same scan finds the plan's words in the source plan's file.
  own_file <- withr::local_tempfile(fileext = ".yaml")
  save_plan(recipe(m)@plan, own_file)
  own_text <- readLines(own_file)
  for (w in c("Variety", "yield")) {
    expect_true(any(grepl(w, own_text, fixed = TRUE)), info = w)
  }
  expect_error(handover(m, out), class = "masque_handover_exists_refusal")
  handover(m, out, overwrite = TRUE)

  # The file round trip the note describes.
  clone <- data.table::fread(file.path(out, "clone.csv"))
  ctl <- controls(clone, read_plan(file.path(out, "plan.yaml")))
  expect_true(S7::S7_inherits(ctl, masque_controls))
})

test_that("handover runs the release gate", {
  skip_if_not_installed("yaml")
  d <- .fx_plan_table()
  d$id_copy <- seq_len(nrow(d))
  r <- .fx_plan_roles(d[, setdiff(names(d), "id_copy")])
  r <- propose_roles(d, mode = "collaborate", detect = FALSE)
  r <- set_role(r, c("site", "rep", "block"), role = "design", action = "keep")
  r <- set_role(r, "gen", role = "treatment", action = "alias")
  r <- set_role(r, c("yield", "id_copy"), role = "outcome", action = "keep")
  m <- suppressWarnings(mask(d, r, mode = "collaborate", seed = 1L, quiet = TRUE,
                             allow_kept_outcome = TRUE))
  out <- file.path(withr::local_tempdir(), "pack")
  expect_error(handover(m, out), class = "masque_blocked_write")
  expect_false(dir.exists(out))
  expect_warning(handover(m, out, allow_high = TRUE), class = "masque_high_override")
  expect_true(any(grepl("HIGH", readLines(file.path(out, "README.txt")))))
})
