# The null control: every analysed column permuted at its grain, nothing else
# touched, every association removed.

test_that("the null keeps structure, NA mask, classes and multisets", {
  df <- .ctl_met()
  r <- .ctl_roles(df)
  ctl <- controls(df, r, .ctl_spec())
  nul <- control_table(ctl, "null")

  expect_identical(names(nul), names(df))
  expect_identical(nrow(nul), nrow(df))
  for (cl in c("trial", "rep", "block", "gen")) {
    expect_identical(nul[[cl]], df[[cl]])
  }
  expect_identical(
    unname(is.na(as.data.frame(nul))), unname(is.na(df))
  )
  expect_identical(
    vapply(nul, function(x) class(x)[1L], character(1L)),
    vapply(df, function(x) class(x)[1L], character(1L))
  )
  for (cl in c("yield", "count", "plot_cov", "irrig", "aet", "soil", "sow")) {
    expect_true(.ctl_same_multiset(nul[[cl]], df[[cl]]), info = cl)
  }
  expect_identical(attr(nul, "masque_control")$kind, "null")
  expect_true(is.na(attr(nul, "masque_control")$replicate))
})

test_that("a declared unit-grained column stays constant within its unit", {
  df <- .ctl_met()
  r <- .ctl_roles(df)
  ctl <- controls(df, r, .ctl_spec())
  nul <- control_table(ctl, "null")
  trial_id <- masque:::.unit_id(df, "trial")
  for (cl in c("aet", "soil", "sow")) {
    expect_true(masque:::.constant_within(trial_id, nul[[cl]]), info = cl)
  }
  # The all-missing trial stays missing; the unit values are the same set.
  expect_true(all(is.na(nul$aet[nul$trial == "T2"])))
  expect_identical(
    sort(unique(nul$aet[!is.na(nul$aet)])),
    sort(unique(df$aet[!is.na(df$aet)]))
  )
  # The unit values moved: at least one trial holds another trial's value.
  expect_false(identical(nul$aet, df$aet) && identical(nul$soil, df$soil))
})

test_that("a column not constant within its declared unit is row-permuted with a note", {
  df <- .ctl_met()
  r <- .ctl_roles(df)
  spec <- control_spec(
    on = "gen", strata = c("trial", "rep", "block"),
    grain = list(plot_cov = "trial"), seed = 3L
  )
  ctl <- controls(df, r, spec)
  expect_length(ctl@notes, 1L)
  expect_match(ctl@notes, "plot_cov is not constant within trial", fixed = TRUE)
  nul <- control_table(ctl, "null")
  expect_true(.ctl_same_multiset(nul$plot_cov, df$plot_cov))
})

test_that("the null removes the association among analysed columns", {
  df <- .ctl_met(n_trial = 5L, n_gen = 20L)
  r <- .ctl_roles(df)
  ctl <- controls(df, r, .ctl_spec())
  nul <- control_table(ctl, "null")
  before <- stats::cor(df$yield, df$plot_cov, use = "complete.obs")
  after <- stats::cor(nul$yield, nul$plot_cov, use = "complete.obs")
  expect_gt(before, 0.95)
  expect_lt(abs(after), 0.3)
})

test_that("controls() and control_table() leave the caller's RNG untouched", {
  df <- .ctl_met()
  r <- .ctl_roles(df)
  set.seed(123)
  before <- .Random.seed
  ctl <- controls(df, r, .ctl_spec())
  nul <- control_table(ctl, "null")
  neg <- control_table(ctl, "negative", 1L)
  expect_identical(.Random.seed, before)
})

test_that("the same seed gives the same null on data.frame and data.table input", {
  df <- .ctl_met()
  r <- .ctl_roles(df)
  a <- control_table(controls(df, r, .ctl_spec()), "null")
  b <- control_table(controls(data.table::as.data.table(df), r, .ctl_spec()), "null")
  expect_identical(a, b)
  c3 <- control_table(controls(df, r, .ctl_spec(seed = 4L)), "null")
  expect_false(identical(a$yield, c3$yield))
})

test_that("a kept outcome is reported and left alone; no analysed column is refused", {
  df <- .ctl_met()
  r <- .ctl_roles(df)
  r_keep <- set_role(r, "yield", role = "outcome", action = "keep")
  expect_warning(
    ctl <- controls(df, r_keep, .ctl_spec()),
    class = "masque_control_kept_outcome"
  )
  expect_identical(control_table(ctl, "null")$yield, df$yield)

  r_all <- r
  r_all$action <- "keep"
  err <- tryCatch(
    suppressWarnings(controls(df, r_all, .ctl_spec())),
    error = function(e) e
  )
  expect_true(inherits(err, "masque_control_analysed_refusal"))
})
