# A kept outcome audits HIGH in collaborate unless allow_kept_outcome = TRUE.

.fx_kept <- function() {
  withr::with_seed(4L, {
    g <- expand.grid(
      gen = sprintf("G%d", 1:6), rep = 1:4,
      stringsAsFactors = FALSE, KEEP.OUT.ATTRS = FALSE
    )
    g$yield <- round(stats::rnorm(nrow(g), 3, 0.5), 2)
    g$height <- round(stats::rnorm(nrow(g), 90, 6), 1)
    g
  })
}

.fx_kept_roles <- function(df, mode) {
  r <- suppressWarnings(propose_roles(df, mode = mode, detect = FALSE))
  r <- set_role(r, "rep", role = "design", action = "keep")
  r <- set_role(r, "gen", role = "treatment")
  r <- set_role(r, "yield", role = "outcome", action = "keep")
  set_role(r, "height", role = "covariate", action = "scramble")
}

test_that("a kept outcome audits HIGH in collaborate and blocks the write", {
  df <- .fx_kept()
  expect_warning(
    m <- mask(df, .fx_kept_roles(df, "collaborate"), mode = "collaborate",
              seed = 1),
    "yield", class = "masque_high_leakage"
  )
  expect_identical(m@audit$leakage_class[m@audit$col == "yield"], "high")
  expect_match(m@audit$notes[m@audit$col == "yield"], "allow_kept_outcome")
  expect_false(recipe(m)@allow_kept_outcome)
  expect_error(masque:::.gate_release(m), class = "masque_blocked_write")
})

test_that("allow_kept_outcome = TRUE lifts the HIGH and is recorded", {
  df <- .fx_kept()
  expect_no_warning(
    m <- mask(df, .fx_kept_roles(df, "collaborate"), mode = "collaborate",
              seed = 1, allow_kept_outcome = TRUE),
    class = "masque_high_leakage"
  )
  expect_true(recipe(m)@allow_kept_outcome)
  row <- m@audit[m@audit$col == "yield", ]
  expect_identical(row$leakage_class, "medium")
  expect_match(row$notes, "allow_kept_outcome = TRUE")
  expect_no_error(masque:::.gate_release(m))
  a <- audit_mask(m, original = df, print = FALSE)
  expect_identical(a$leakage_class[a$col == "yield"], "medium")
})

test_that("local mode does not grade a kept outcome HIGH", {
  df <- .fx_kept()
  m <- suppressWarnings(
    mask(df, .fx_kept_roles(df, "local"), mode = "local", seed = 1)
  )
  a <- audit_mask(m, original = df, print = FALSE)
  expect_false(a$leakage_class[a$col == "yield"] == "high")
})

test_that("allow_kept_outcome must be a single logical", {
  df <- .fx_kept()
  expect_error(
    mask(df, .fx_kept_roles(df, "collaborate"), mode = "collaborate",
         allow_kept_outcome = "yes"),
    class = "masque_bad_allow_kept_outcome_refusal"
  )
})

test_that("a recipe without the property audits as not allowed", {
  df <- .fx_kept()
  m <- suppressWarnings(mask(
    df, .fx_kept_roles(df, "collaborate"), mode = "collaborate", seed = 1,
    allow_kept_outcome = TRUE
  ))
  rec <- recipe(m)
  # As a recipe written before the property existed deserialises.
  attr(rec, "allow_kept_outcome") <- NULL
  expect_null(attr(rec, "allow_kept_outcome"))
  a <- masque:::.compute_audit(
    data.table::as.data.table(df), synthetic(m), rec, "collaborate"
  )
  expect_identical(a$leakage_class[a$col == "yield"], "high")
})

test_that("mask_set() and masque() pass allow_kept_outcome through", {
  df <- .fx_kept()
  roles <- list(plots = .fx_kept_roles(df, "collaborate"))
  ms <- suppressWarnings(mask_set(
    list(plots = df), roles = roles, mode = "collaborate", seed = 1,
    quiet = TRUE, allow_kept_outcome = TRUE
  ))
  expect_true(recipe(ms)@recipes$plots@allow_kept_outcome)
  mq <- suppressWarnings(masque(
    df, roles = .fx_kept_roles(df, "collaborate"), mode = "collaborate",
    seed = 1, ask = FALSE, quiet = TRUE, allow_kept_outcome = TRUE
  ))
  expect_true(recipe(mq)@allow_kept_outcome)
})
