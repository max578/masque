# The positive control: the negative plus the declared per-level shift on
# each target. Positive minus negative is the planted truth exactly.

test_that("positive minus negative equals the realised shift, row by row", {
  df <- .ctl_met()
  r <- .ctl_roles(df)
  spec <- .ctl_spec(target = c("yield", "count"), effect = c(G01 = 0.5, G02 = -0.5))
  ctl <- controls(df, r, spec)
  neg <- control_table(ctl, "negative", 2L)
  pos <- control_table(ctl, "positive", 2L)
  for (cl in setdiff(names(df), c("yield", "count"))) {
    expect_identical(pos[[cl]], neg[[cl]], info = cl)
  }
  truth <- ctl@truth
  for (tg in c("yield", "count")) {
    shift <- truth$shift_realised[truth$target == tg][
      match(pos$gen, truth$level[truth$target == tg])
    ]
    diff <- pos[[tg]] - neg[[tg]]
    obs <- !is.na(neg[[tg]])
    expect_identical(is.na(pos[[tg]]), is.na(neg[[tg]]))
    expect_equal(diff[obs], shift[obs], tolerance = 1e-12)
  }
  expect_true(is.integer(pos$count))
  expect_true(all(truth$whole_valued[truth$target == "count"]))
  expect_identical(nrow(truth), 16L)
  expect_identical(
    truth$effect_sd[truth$target == "yield"],
    c(0.5, -0.5, 0, 0, 0, 0, 0, 0)
  )
  expect_equal(
    truth$shift_raw[truth$target == "yield" & truth$level == "G01"],
    0.5 * stats::sd(df$yield, na.rm = TRUE)
  )
})

test_that("a shift that rounds to zero on a whole-valued target is refused", {
  df <- .ctl_met()
  r <- .ctl_roles(df)
  spec <- .ctl_spec(target = "count", effect = c(G01 = 0.05))
  .ctl_expect_refusal(controls(df, r, spec), "masque_control_shift_vanishes_refusal")
})

test_that("a shift below zero on a non-negative target is reported", {
  df <- .ctl_met()
  r <- .ctl_roles(df)
  ctl <- controls(df, r, .ctl_spec(target = "yield", effect = c(G01 = -30)))
  expect_warning(
    pos <- control_table(ctl, "positive", 1L),
    class = "masque_control_sign_crossed"
  )
  expect_true(any(pos$yield < 0, na.rm = TRUE))
})

test_that("list(sd = ) draws the same vector whatever the run seed", {
  df <- .ctl_met()
  r <- .ctl_roles(df)
  spec <- .ctl_spec(target = "yield", effect = list(sd = 0.5))
  a <- controls(df, r, spec)
  b <- controls(df, r, spec, seed = 99L)
  expect_identical(a@spec@effect, b@spec@effect)
  expect_identical(names(a@spec@effect), sprintf("G%02d", 1:8))
  expect_false(identical(
    control_table(a, "negative", 1L)$gen, control_table(b, "negative", 1L)$gen
  ))
  expect_identical(control_table(a, "null"), control_table(a, "null"))
})

test_that("a two-arm planted effect is recovered without bias", {
  df <- .ctl_two_arm()
  r <- .ctl_two_arm_roles(df)
  n_rep <- 50L
  ctl <- controls(df, r, control_spec(
    on = "trt", target = "y", effect = c(B = 1), n = n_rep, seed = 21L
  ))
  shift <- ctl@truth$shift_realised[ctl@truth$level == "B"]
  est <- vapply(seq_len(n_rep), function(i) {
    d <- control_table(ctl, "positive", i)
    unname(stats::coef(stats::lm(y ~ trt, data = d))["trtB"])
  }, numeric(1L))
  est_null <- vapply(seq_len(n_rep), function(i) {
    d <- control_table(ctl, "negative", i)
    unname(stats::coef(stats::lm(y ~ trt, data = d))["trtB"])
  }, numeric(1L))
  se <- stats::sd(est) / sqrt(n_rep)
  expect_lt(abs(mean(est) - shift), 3 * se)
  expect_lt(abs(mean(est_null)), 3 * stats::sd(est_null) / sqrt(n_rep))
})

test_that("a many-level planted vector is recovered in rank", {
  df <- .ctl_many_levels()
  r <- .ctl_many_roles(df)
  n_rep <- 50L
  ctl <- controls(df, r, control_spec(
    on = "lev", target = "y", effect = list(sd = 1), n = n_rep, seed = 22L
  ))
  truth <- ctl@truth$effect_sd
  rho <- vapply(seq_len(n_rep), function(i) {
    d <- control_table(ctl, "positive", i)
    means <- tapply(d$y, d$lev, mean)
    stats::cor(truth, means[ctl@truth$level], method = "spearman")
  }, numeric(1L))
  expect_gte(sum(rho >= 0.9), 45L)
})

test_that("targets are checked by kind, grain, events and against on", {
  df <- .ctl_met()
  r <- .ctl_roles(df)
  .ctl_expect_refusal(
    controls(df, r, .ctl_spec(target = "soil", effect = c(G01 = 1))),
    "masque_control_target_kind_refusal"
  )
  .ctl_expect_refusal(
    controls(df, r, .ctl_spec(target = "irrig", effect = c(G01 = 1))),
    "masque_control_target_kind_refusal"
  )
  .ctl_expect_refusal(
    controls(df, r, control_spec(
      on = "gen", target = "aet", effect = c(G01 = 1), grain = list(aet = "trial"),
      seed = 1L
    )),
    "masque_control_target_grain_refusal"
  )
  .ctl_expect_refusal(
    controls(df, r, control_spec(
      on = "irrig", target = "irrig", effect = c(wet = 1), seed = 1L
    )),
    "masque_control_on_refusal"
  )
  .ctl_expect_refusal(
    controls(df, r, .ctl_spec(target = "nope", effect = c(G01 = 1))),
    "masque_control_target_refusal"
  )
  .ctl_expect_refusal(
    controls(df, r, .ctl_spec(target = "yield", effect = c(G99 = 1))),
    "masque_control_effect_refusal"
  )
})
