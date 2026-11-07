# control_spec(): the declaration is validated before it meets a table.

test_that("the seed is required", {
  .ctl_expect_refusal(control_spec(on = "gen"), "masque_control_seed_refusal")
  .ctl_expect_refusal(
    control_spec(on = "gen", seed = NULL), "masque_control_seed_refusal"
  )
  .ctl_expect_refusal(
    control_spec(on = "gen", seed = 1.5), "masque_bad_seed_refusal"
  )
})

test_that("target and effect come together", {
  .ctl_expect_refusal(
    control_spec(target = "y", seed = 1L), "masque_control_effect_refusal"
  )
  .ctl_expect_refusal(
    control_spec(effect = c(A = 1), seed = 1L), "masque_control_effect_refusal"
  )
})

test_that("effect forms are a named vector or list(sd = )", {
  .ctl_expect_refusal(
    control_spec(target = "y", effect = 0.5, seed = 1L),
    "masque_control_effect_refusal"
  )
  .ctl_expect_refusal(
    control_spec(target = "y", effect = c(A = 1, A = 2), seed = 1L),
    "masque_control_effect_refusal"
  )
  .ctl_expect_refusal(
    control_spec(target = "y", effect = c(A = Inf), seed = 1L),
    "masque_control_effect_refusal"
  )
  .ctl_expect_refusal(
    control_spec(target = "y", effect = list(sd = -1), seed = 1L),
    "masque_control_effect_refusal"
  )
  .ctl_expect_refusal(
    control_spec(target = "y", effect = list(scale = 1), seed = 1L),
    "masque_control_effect_refusal"
  )
  s1 <- control_spec(target = "y", effect = c(A = 1L), seed = 1L)
  expect_identical(s1@effect, c(A = 1))
  s2 <- control_spec(target = "y", effect = list(sd = 2L), seed = 1L)
  expect_identical(s2@effect, list(sd = 2))
})

test_that("n, on, strata and grain are checked", {
  .ctl_expect_refusal(control_spec(n = 0L, seed = 1L), "masque_control_n_refusal")
  .ctl_expect_refusal(control_spec(n = 1.5, seed = 1L), "masque_control_n_refusal")
  .ctl_expect_refusal(
    control_spec(on = c("a", "b"), seed = 1L), "masque_control_on_refusal"
  )
  .ctl_expect_refusal(
    control_spec(strata = c("a", "a"), seed = 1L), "masque_control_strata_refusal"
  )
  .ctl_expect_refusal(
    control_spec(grain = list("trial"), seed = 1L), "masque_control_grain_refusal"
  )
  .ctl_expect_refusal(
    control_spec(grain = list(aet = 1L), seed = 1L), "masque_control_grain_refusal"
  )
  s <- control_spec(n = 19, seed = 2026, unit = "trial")
  expect_identical(s@n, 19L)
  expect_identical(s@seed, 2026L)
  expect_identical(s@unit, "trial")
  expect_identical(s@strata, character())
})

test_that("the spec prints its declaration", {
  s <- control_spec(
    on = "gen", target = "yield", effect = c(G01 = 0.5),
    strata = c("rep", "block"), grain = list(aet = "trial"), n = 19L,
    seed = 1L
  )
  out <- capture_full(print(s))
  expect_match(out, "Replicates: 19", fixed = TRUE)
  expect_match(out, "G01 +0.5", fixed = TRUE)
  expect_match(out, "aet within trial", fixed = TRUE)
  s2 <- control_spec(target = "y", effect = list(sd = 0.3), seed = 1L)
  expect_match(capture_full(print(s2)), "drawn from N(0, 0.3^2)", fixed = TRUE)
})
