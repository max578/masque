# A declared linked-event pair moves as one row block in the null, so the
# time order within a row and the status patterns survive.

test_that("a declared event pair moves as one block in the null", {
  df <- .events_fixture(n = 300L)
  r <- .events_roles(df)
  spec <- control_spec(on = "arm", seed = 1L)
  ctl <- controls(df, r, spec, events = .events_spec)
  nul <- control_table(ctl, "null")
  key_in <- paste(df$time_rec, df$status_rec, df$time_death, df$status_death)
  key_out <- paste(nul$time_rec, nul$status_rec, nul$time_death, nul$status_death)
  expect_identical(sort(key_in), sort(key_out))
  expect_false(identical(key_in, key_out))
  expect_true(all(nul$time_rec <= nul$time_death))
  expect_identical(nul$id, df$id)
  expect_identical(nul$arm, df$arm)
})

test_that("without the declaration the pair breaks, and an event column is no target", {
  df <- .events_fixture(n = 300L)
  r <- .events_roles(df)
  ctl <- controls(df, r, control_spec(on = "arm", seed = 1L))
  nul <- control_table(ctl, "null")
  key_in <- paste(df$time_rec, df$status_rec, df$time_death, df$status_death)
  key_out <- paste(nul$time_rec, nul$status_rec, nul$time_death, nul$status_death)
  expect_false(identical(sort(key_in), sort(key_out)))
  .ctl_expect_refusal(
    controls(df, r, control_spec(
      on = "arm", target = "time_rec", effect = c(B = 1), seed = 1L
    ), events = .events_spec),
    "masque_control_target_kind_refusal"
  )
})
