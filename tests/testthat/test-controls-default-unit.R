# The plan's default unit, and the warnings on a control that cannot read as a
# test size.

confounded <- function(tech = TRUE) {
  set.seed(2)
  d <- data.frame(
    field = rep(paste0("f", 1:3), each = 30L),
    tech = rep(paste0("t", 1:9), each = 10L),
    plot = 1:90
  )
  d$gen <- paste0("G", match(d$field, paste0("f", 1:3)))
  d$y <- c(0, 5, 1)[match(d$field, paste0("f", 1:3))] + stats::rnorm(90L)
  design <- if (tech) c("field", "tech") else "field"
  if (!tech) d$tech <- NULL
  r <- suppressWarnings(propose_roles(d, detect = FALSE))
  r <- set_role(r, design, role = "design", action = "keep")
  r <- set_role(r, "gen", role = "treatment", action = "keep")
  r <- set_role(r, "y", role = "outcome", action = "scramble")
  r <- set_role(r, "plot", role = "id", action = "keep")
  list(d = d, r = r)
}

test_that("a confounder too coarse for a 5 percent level is not the default", {
  f <- confounded()
  spec <- control_spec(on = "gen", target = "y", effect = list(sd = 0.5), n = 20L, seed = 3L)
  m <- mask(f$d, masque_plan(f$r, controls = spec), seed = 4L, quiet = TRUE)
  own <- controls(f$d, clone_plan(m), recipe = recipe(m))
  expect_identical(own@spec@unit, "tech")
  p <- vapply(1:20, function(i) {
    stats::anova(stats::lm(y ~ gen, control_table(own, "negative", i)))["gen", "Pr(>F)"]
  }, numeric(1L))
  expect_gt(length(unique(signif(p, 6L))), 1L)
  # Column order does not choose.
  r2 <- f$r[rev(seq_len(nrow(f$r))), ]
  d2 <- f$d[, rev(names(f$d))]
  expect_identical(
    recipe(mask(d2, masque_plan(r2, controls = spec), seed = 4L, quiet = TRUE))@plan@controls$default@unit,
    "tech"
  )
})

test_that("between two legal columns the coarser is chosen, with a warning", {
  d <- data.frame(
    field = rep(paste0("f", 1:8), each = 8L),
    tech = rep(paste0("t", 1:16), each = 4L),
    gen = rep(paste0("G", 1:4), each = 16L)
  )
  expect_warning(
    u1 <- masque:::.default_control_unit(d, "gen", c("field", "tech")),
    class = "masque_control_unit_ambiguous"
  )
  expect_identical(u1, "field")
  expect_identical(
    suppressWarnings(masque:::.default_control_unit(d, "gen", c("tech", "field"))), "field"
  )
})

test_that("a column with too few units is passed over, with a warning", {
  f <- confounded(tech = FALSE)
  spec <- control_spec(on = "gen", n = 20L, seed = 3L)
  expect_warning(
    m <- mask(f$d, masque_plan(f$r, controls = spec), seed = 4L, quiet = TRUE),
    class = "masque_control_unit_small"
  )
  expect_length(recipe(m)@plan@controls$default@unit, 0L)
})

test_that("a named unit with too few arrangements warns and still runs", {
  f <- confounded(tech = FALSE)
  spec <- control_spec(on = "gen", unit = "field", n = 2L, seed = 3L)
  expect_warning(ctl <- controls(f$d, f$r, spec), class = "masque_control_unit_small")
  expect_identical(ctl@spec@unit, "field")
})

test_that("arrangements are counted within strata and across equal labels", {
  id <- 1:3
  expect_false(masque:::.level_attainable(id, c("a", "b", "c"), rep(1L, 3L)))
  expect_false(masque:::.level_attainable(1:6, c("a", "b", "c", "d", "e", "f"), rep(1L, 6L)))
  expect_true(masque:::.level_attainable(1:72, rep(paste0("G", 1:24), 3L), rep(1:3, each = 24L)))
  # Two equal labels: choose(6, 3) = 20 arrangements are 10 partitions.
  expect_false(masque:::.level_attainable(1:6, rep(c("a", "b"), each = 3L), rep(1L, 6L)))
  expect_false(masque:::.level_attainable(1:6, c("a", "a", "b", "b", "b", "b"), rep(1:2, each = 3L)))
  expect_true(masque:::.level_attainable(1:7, c(rep("a", 3L), rep("b", 4L)), rep(1L, 7L)))
})

test_that("label symmetry counts across strata, and a unit's NA row does not drop it", {
  # Paired, five blocks: 32 arrangements, 16 partitions.
  pair <- rep(c("a", "b"), 5L)
  expect_false(masque:::.level_attainable(1:10, pair, rep(1:5, each = 2L)))
  # A randomised block of three treatments in two blocks: 36 arrangements, 6 partitions.
  expect_false(masque:::.level_attainable(1:6, rep(c("a", "b", "c"), 2L), rep(1:2, each = 3L)))
  # Eight units whose first rows hold NA are still eight units.
  unit <- rep(1:8, each = 2L)
  on <- rep(c("a", "a", "b", "b", "c", "c", "d", "d"), each = 2L)
  on[seq(1L, 15L, by = 2L)] <- NA
  expect_true(masque:::.level_attainable(unit, on, rep(1L, 16L)))
})

test_that("strata holding one level warn from a tenth of the strata", {
  d <- data.frame(
    site = rep(paste0("S", 1:5), each = 8L),
    trt = c(rep("a", 8L), rep("b", 8L), rep(c("a", "b"), 12L)),
    y = seq_len(40L) + 0.5
  )
  r <- suppressWarnings(propose_roles(d, detect = FALSE))
  r <- set_role(r, "site", role = "design", action = "keep")
  r <- set_role(r, "trt", role = "treatment", action = "keep")
  r <- set_role(r, "y", role = "outcome", action = "scramble")
  expect_warning(
    ctl <- controls(d, r, control_spec(on = "trt", strata = "site", seed = 1L)),
    class = "masque_control_strata_weak"
  )
  expect_identical(ctl@manifest$strata_constant_share[1L], 0.4)
})

test_that("the stored absence of strata goes back through the constructor", {
  f <- confounded()
  m <- mask(f$d, masque_plan(f$r, controls = control_spec(on = "gen", n = 2L, seed = 3L)),
            seed = 4L, quiet = TRUE)
  s <- recipe(m)@plan@controls$default
  expect_length(s@strata, 0L)
  again <- control_spec(on = "gen", strata = s@strata, unit = s@unit, n = 2L, seed = 3L)
  expect_length(again@strata, 0L)
})

test_that("rounding that changes the declared shape warns", {
  set.seed(4)
  d <- data.frame(gen = rep(c("a", "b", "c"), 20L), y = as.integer(rpois(60L, 10)))
  r <- suppressWarnings(propose_roles(d, detect = FALSE))
  r <- set_role(r, "gen", role = "treatment", action = "keep")
  r <- set_role(r, "y", role = "outcome", action = "scramble")
  expect_warning(
    ctl <- controls(d, r, control_spec(on = "gen", target = "y", effect = c(a = 0.4, b = -0.2), seed = 1L)),
    class = "masque_control_shape_rounded"
  )
  expect_identical(ctl@truth$shift_realised[ctl@truth$level == "a"], -ctl@truth$shift_realised[ctl@truth$level == "b"])
  many <- data.frame(gen = rep(paste0("G", 1:24), 3L), y = as.integer(rpois(72L, 10)))
  rm <- suppressWarnings(propose_roles(many, detect = FALSE))
  rm <- set_role(rm, "gen", role = "treatment", action = "keep")
  rm <- set_role(rm, "y", role = "outcome", action = "scramble")
  expect_warning(
    controls(many, rm, control_spec(on = "gen", target = "y", effect = stats::setNames(rep(c(0.4, -0.2), 12L), paste0("G", 1:24)), seed = 1L)),
    class = "masque_control_shape_rounded"
  )
  expect_no_warning(
    controls(d, r, control_spec(on = "gen", target = "y", effect = c(a = 2, b = -1), seed = 1L)),
    class = "masque_control_shape_rounded"
  )
})
