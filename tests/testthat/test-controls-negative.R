# The negative control: `on` permuted within strata at its unit, nothing
# else touched.

test_that("the negative permutes on within strata and keeps everything else", {
  df <- .ctl_met()
  r <- .ctl_roles(df)
  ctl <- controls(df, r, .ctl_spec())
  neg <- control_table(ctl, "negative", 1L)
  for (cl in setdiff(names(df), "gen")) {
    expect_identical(neg[[cl]], df[[cl]], info = cl)
  }
  stratum <- paste(df$trial, df$rep, df$block)
  for (s in unique(stratum)) {
    expect_identical(sort(neg$gen[stratum == s]), sort(df$gen[stratum == s]))
  }
  expect_false(identical(neg$gen, df$gen))
  expect_identical(ctl@manifest$n_strata[1L], 24L)
  expect_identical(ctl@manifest$strata_constant_share[1L], 0)
  expect_identical(attr(neg, "masque_control")$replicate, 1L)
})

test_that("replicates differ and the treatment-by-stratum incidence is kept", {
  df <- .ctl_met()
  r <- .ctl_roles(df)
  ctl <- controls(df, r, .ctl_spec(n = 3L))
  n1 <- control_table(ctl, "negative", 1L)
  n2 <- control_table(ctl, "negative", 2L)
  expect_false(identical(n1$gen, n2$gen))
  expect_identical(table(n1$trial, n1$gen), table(df$trial, df$gen))
})

test_that("a whole-plot on is permuted at its unit within coarser strata", {
  df <- .ctl_met()
  r <- .ctl_roles(df)
  spec <- control_spec(
    on = "irrig", unit = c("trial", "rep"), strata = "trial", n = 1L, seed = 9L
  )
  ctl <- controls(df, r, spec)
  neg <- control_table(ctl, "negative", 1L)
  unit <- masque:::.unit_id(df, c("trial", "rep"))
  expect_true(masque:::.constant_within(unit, neg$irrig))
  for (t in unique(df$trial)) {
    u_in <- unique(df[df$trial == t, c("rep", "irrig")])$irrig
    u_out <- unique(as.data.frame(neg)[neg$trial == t, c("rep", "irrig")])$irrig
    expect_identical(sort(u_out), sort(u_in))
  }
  expect_identical(ctl@manifest$unit[1L], "trial + rep")
})

test_that("a degenerate restricted permutation is refused", {
  df <- .ctl_met()
  r <- .ctl_roles(df)
  spec <- control_spec(
    on = "irrig", strata = c("trial", "rep", "block"), seed = 1L
  )
  .ctl_expect_refusal(controls(df, r, spec), "masque_control_degenerate_refusal")
})

test_that("on constant in most strata warns", {
  df <- data.frame(
    site = rep(c("S1", "S2", "S3", "S4"), each = 4L),
    trt = c(rep("a", 4L), rep("b", 4L), rep("a", 4L), c("a", "a", "b", "b")),
    y = seq_len(16L) + 0.5,
    stringsAsFactors = FALSE
  )
  r <- suppressWarnings(propose_roles(df, detect = FALSE))
  r <- set_role(r, "site", role = "design", action = "keep")
  r <- set_role(r, "trt", role = "treatment", action = "keep")
  r <- set_role(r, "y", role = "outcome", action = "scramble")
  spec <- control_spec(on = "trt", strata = "site", seed = 1L)
  expect_warning(
    ctl <- controls(df, r, spec), class = "masque_control_strata_weak"
  )
  expect_identical(ctl@manifest$strata_constant_share[1L], 0.75)
})

test_that("unit and strata must nest, be design columns, and hold on constant", {
  df <- .ctl_met()
  r <- .ctl_roles(df)
  .ctl_expect_refusal(
    controls(df, r, control_spec(
      on = "irrig", unit = c("trial", "rep"), strata = "block", seed = 1L
    )),
    "masque_control_strata_refusal"
  )
  .ctl_expect_refusal(
    controls(df, r, control_spec(on = "gen", unit = "block", seed = 1L)),
    "masque_control_unit_refusal"
  )
  .ctl_expect_refusal(
    controls(df, r, control_spec(on = "gen", strata = "gen", seed = 1L)),
    "masque_control_strata_refusal"
  )
  .ctl_expect_refusal(
    controls(df, r, control_spec(on = "gen", unit = "soil", seed = 1L)),
    "masque_control_unit_refusal"
  )
})

test_that("on defaults to the single treatment and is checked by role and kind", {
  df <- .ctl_met()
  r <- .ctl_roles(df)
  ctl <- controls(df, r, control_spec(strata = "trial", seed = 1L))
  expect_identical(ctl@spec@on, "gen")

  r_two <- set_role(r, "irrig", role = "treatment", action = "keep")
  .ctl_expect_refusal(
    controls(df, r_two, control_spec(strata = "trial", seed = 1L)),
    "masque_control_on_refusal"
  )
  .ctl_expect_refusal(
    controls(df, r, control_spec(on = "trial", seed = 1L)),
    "masque_control_on_refusal"
  )
  .ctl_expect_refusal(
    controls(df, r, control_spec(on = "yield", seed = 1L)),
    "masque_control_on_refusal"
  )
  .ctl_expect_refusal(
    controls(df, r, control_spec(on = "plot_cov", seed = 1L)),
    "masque_control_on_refusal"
  )
  .ctl_expect_refusal(
    controls(df, r, control_spec(on = "nope", seed = 1L)),
    "masque_control_on_refusal"
  )
})

test_that("a whole-valued numeric treatment can be on", {
  df <- .ctl_two_arm(n = 40L)
  df$dose <- rep(c(50L, 100L), 20L)
  r <- .ctl_two_arm_roles(df)
  r <- set_role(r, "trt", role = "covariate", action = "scramble")
  r <- set_role(r, "dose", role = "treatment", action = "keep")
  ctl <- controls(df, r, control_spec(
    target = "y", effect = c(`100` = 0.5), seed = 1L
  ))
  expect_identical(ctl@spec@on, "dose")
  expect_identical(ctl@truth$level, c("50", "100"))
  expect_identical(ctl@truth$effect_sd, c(0, 0.5))
})
