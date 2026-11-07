# control_table(): regeneration from seed, argument checks, the manifest and
# the print.

test_that("a control table is regenerated identically from its seed", {
  df <- .ctl_met()
  r <- .ctl_roles(df)
  ctl <- controls(df, r, .ctl_spec(target = "yield", effect = c(G01 = 1)))
  expect_identical(control_table(ctl, "null"), control_table(ctl, "null"))
  expect_identical(
    control_table(ctl, "negative", 2L), control_table(ctl, "negative", 2L)
  )
  expect_identical(
    control_table(ctl, "positive", 2L), control_table(ctl, "positive", 2L)
  )
})

test_that("kind and replicate are checked", {
  df <- .ctl_met()
  r <- .ctl_roles(df)
  ctl <- controls(df, r, .ctl_spec())
  .ctl_expect_refusal(control_table(ctl, "negative", 3L), "masque_control_kind_refusal")
  .ctl_expect_refusal(control_table(ctl, "negative", 0L), "masque_control_kind_refusal")
  .ctl_expect_refusal(control_table(ctl, "positive", 1L), "masque_control_kind_refusal")
  .ctl_expect_refusal(control_table(df, "null"), "masque_control_kind_refusal")
  expect_error(control_table(ctl, "blank"))
  .ctl_expect_refusal(controls(df, r, list(on = "gen")), "masque_control_spec_refusal")
  .ctl_expect_refusal(controls(df[1L, ], r, .ctl_spec()), "masque_control_table_refusal")
  .ctl_expect_refusal(controls(df, r, .ctl_spec(), seed = 1.5), "masque_bad_seed_refusal")
})

test_that("the manifest lists every dataset with its own seed", {
  df <- .ctl_met()
  r <- .ctl_roles(df)
  ctl <- controls(df, r, .ctl_spec(n = 3L, target = "yield", effect = c(G01 = 1)))
  m <- ctl@manifest
  expect_identical(nrow(m), 7L)
  expect_identical(m$kind, c("null", rep("negative", 3L), rep("positive", 3L)))
  expect_identical(m$replicate, c(NA, 1L, 2L, 3L, 1L, 2L, 3L))
  expect_identical(m$seed[2:4], m$seed[5:7])
  expect_identical(anyDuplicated(m$seed[1:4]), 0L)
  expect_identical(m$permuted[2L], "gen")
  expect_match(m$permuted[1L], "yield", fixed = TRUE)
  expect_identical(m$strata[1L], "trial + rep + block")
  expect_identical(m$target[1L], "yield")
  ctl0 <- controls(df, r, .ctl_spec())
  expect_identical(nrow(ctl0@manifest), 3L)
  expect_true(is.na(ctl0@manifest$target[1L]))
})

test_that("the controls object prints its declaration and truth", {
  df <- .ctl_met()
  r <- .ctl_roles(df)
  ctl <- controls(df, r, .ctl_spec(target = "yield", effect = c(G01 = 1)))
  out <- capture_full(print(ctl))
  expect_match(out, "Datasets: 1 null, 2 negative, 2 positive", fixed = TRUE)
  expect_match(out, "Planted truth", fixed = TRUE)
  expect_match(out, "24 strata", fixed = TRUE)
  ctl2 <- controls(df, r, control_spec(
    on = "gen", strata = "trial", grain = list(plot_cov = "trial"), seed = 1L
  ))
  expect_match(capture_full(print(ctl2)), "Notes", fixed = TRUE)
})

test_that("the input table is not modified", {
  df <- data.table::as.data.table(.ctl_met())
  before <- data.table::copy(df)
  r <- .ctl_roles(df)
  ctl <- controls(df, r, .ctl_spec(target = "yield", effect = c(G01 = 1)))
  invisible(control_table(ctl, "null"))
  invisible(control_table(ctl, "positive", 1L))
  expect_identical(df, before)
  expect_identical(ctl@table, before)
})
