test_that("linked events keep their structure in the clone", {
  df <- .events_fixture()
  m <- suppressWarnings(
    mask(df, .events_roles(df), seed = 3, events = .events_spec)
  )
  s <- synthetic(m)

  expect_true(all(s$time_rec <= s$time_death))
  no_rec <- s$status_rec == 0L
  expect_identical(s$time_rec[no_rec], s$time_death[no_rec])
  expect_setequal(unique(s$status_rec), unique(df$status_rec))
  expect_setequal(unique(s$status_death), unique(df$status_death))
  expect_identical(
    as.vector(table(.pattern_of(s))), as.vector(table(.pattern_of(df)))
  )
  expect_type(s$status_rec, "integer")
  expect_false(anyNA(s[, c("time_rec", "time_death")]))
})

test_that("event times are re-simulated, not carried by their rows", {
  df <- .events_fixture()
  m <- suppressWarnings(
    mask(df, .events_roles(df), seed = 3, events = .events_spec)
  )
  s <- synthetic(m)
  # Status patterns are permuted across rows, so most rows change pattern or
  # time.
  same_row <- .pattern_of(s) == .pattern_of(df) &
    s$time_death == df$time_death & s$time_rec == df$time_rec
  expect_lt(mean(same_row), 0.05)
  # Gaps come from the rows of the same status pattern, except where a row's
  # final time was capped at the pattern's longest follow-up.
  for (p in unique(.pattern_of(df))) {
    g_obs <- with(df[.pattern_of(df) == p, ], time_death - time_rec)
    g_new <- with(s[.pattern_of(s) == p, ], time_death - time_rec)
    capped <- s$time_death[.pattern_of(s) == p] ==
      max(df$time_death[.pattern_of(df) == p])
    expect_true(all(g_new %in% g_obs | capped))
  }
})

test_that("events are reproducible under a seed", {
  df <- .events_fixture(n = 200L)
  r <- .events_roles(df)
  m1 <- suppressWarnings(mask(df, r, seed = 9, events = .events_spec))
  m2 <- suppressWarnings(mask(df, r, seed = 9, events = .events_spec))
  expect_identical(synthetic(m1), synthetic(m2))
})

test_that("conditional events keep each arm's pattern counts", {
  df <- .events_fixture()
  m <- suppressWarnings(mask(
    df, .events_roles(df),
    seed = 3, events = .events_spec, conditional = TRUE
  ))
  s <- synthetic(m)
  expect_identical(
    table(s$arm, .pattern_of(s)), table(df$arm, .pattern_of(df))
  )
  expect_true(recipe(m)@events[[1L]]$strata)
})

test_that("collaborate events stay ordered, whole-day and zero-gapped", {
  df <- .events_fixture()
  m <- suppressWarnings(mask(
    df, .events_roles(df),
    mode = "collaborate", seed = 3, events = .events_spec
  ))
  s <- synthetic(m)
  expect_true(all(s$time_rec <= s$time_death))
  expect_true(all(s$time_death == round(s$time_death)))
  no_rec <- s$status_rec == 0L
  expect_identical(s$time_rec[no_rec], s$time_death[no_rec])
})

test_that("the recipe records the event spec and prints it", {
  df <- .events_fixture(n = 200L)
  m <- suppressWarnings(
    mask(df, .events_roles(df), seed = 3, events = .events_spec)
  )
  er <- recipe(m)@events
  expect_length(er, 1L)
  expect_identical(er[[1L]]$time, c("time_rec", "time_death"))
  expect_false(er[[1L]]$strata)
  expect_message(print(recipe(m)), "Linked events")

  # A recipe written before 0.16.0 has no events property and still prints.
  old <- recipe(m)
  attr(old, "events") <- NULL
  expect_no_error(suppressMessages(print(old)))
})

test_that("a small status pattern pools its free gaps and warns", {
  df <- .events_fixture()
  keep <- .pattern_of(df) != "1/1"
  small <- which(!keep)[1:3]
  df <- df[c(which(keep), small), ]
  expect_warning(
    m <- mask(df, .events_roles(df), seed = 3, events = .events_spec),
    class = "masque_events_pooled"
  )
  s <- synthetic(m)
  expect_identical(sum(.pattern_of(s) == "1/1"), 3L)
  expect_true(all(s$time_rec <= s$time_death))
  expect_identical(recipe(m)@events[[1L]]$pooled, "1/1")
})

test_that("a free gap held only by a small pattern is refused", {
  df <- .events_fixture()
  # Drop "recurred, censored" rows: the recurrence-to-death gap is then free
  # only in the three "recurred, died" rows.
  keep <- !.pattern_of(df) %in% c("1/1", "1/0")
  df <- df[c(which(keep), which(.pattern_of(df) == "1/1")[1:3]), ]
  expect_error(
    suppressWarnings(
      mask(df, .events_roles(df), seed = 3, events = .events_spec)
    ),
    class = "masque_bad_events_refusal"
  )
})

test_that("bad event specs are refused with a classed error", {
  df <- .events_fixture(n = 100L)
  r <- .events_roles(df)
  refuse <- function(d, ev, roles = r) {
    expect_error(
      suppressWarnings(mask(d, roles, seed = 1, events = ev)),
      class = "masque_bad_events_refusal"
    )
  }
  spec <- .events_spec[[1L]]

  refuse(df, list(list(time = "time_rec")))
  refuse(df, list(list(time = spec$time, status = "status_rec")))
  refuse(df, list(list(time = c("time_rec", "nope"), status = spec$status)))
  refuse(df, list(spec, spec))
  refuse(df, .events_spec, roles = set_role(r, "time_rec", role = "covariate"))

  d2 <- df
  d2$status_rec <- d2$status_rec + 0.5
  refuse(d2, .events_spec, roles = .events_roles(d2))

  d3 <- df
  d3$time_death[1L] <- NA
  refuse(d3, .events_spec, roles = .events_roles(d3))

  d4 <- df
  d4$time_rec[1L] <- d4$time_death[1L] + 10
  refuse(d4, .events_spec, roles = .events_roles(d4))
})

test_that("a single spec may be passed without the outer list", {
  df <- .events_fixture(n = 200L)
  m <- suppressWarnings(
    mask(df, .events_roles(df), seed = 3, events = .events_spec[[1L]])
  )
  expect_length(recipe(m)@events, 1L)
})
