# test-role_options.R -- the option grid must mirror the validator.

test_that("role_options() returns the full 32-row grid", {
  opts <- role_options()
  expect_s3_class(opts, "tbl_df")
  expect_identical(names(opts), c("role", "action", "kinds", "notes"))
  expect_identical(nrow(opts), 32L)
  expect_setequal(
    unique(opts$role),
    c(
      "design", "treatment", "outcome", "covariate",
      "date", "id", "text", "other"
    )
  )
  expect_setequal(
    unique(opts$action),
    c("keep", "scramble", "alias", "drop")
  )
  expect_true(all(table(opts$role) == 4L))
})

test_that("keep and drop are unconstrained for every role", {
  opts <- role_options()
  kd <- opts[opts$action %in% c("keep", "drop"), ]
  expect_identical(nrow(kd), 16L)
  expect_true(all(kd$kinds == "all"))
  expect_true(all(kd$notes == ""))
})

test_that("known constraints render as expected", {
  opts <- role_options()
  row_of <- function(r, a) opts[opts$role == r & opts$action == a, ]

  expect_identical(row_of("design", "scramble")$kinds, "none")
  expect_match(row_of("design", "scramble")$notes, "structure, not content")

  expect_identical(
    row_of("treatment", "alias")$kinds,
    "factor, character, logical"
  )
  expect_identical(row_of("outcome", "scramble")$kinds, "numeric, integer")
  expect_identical(row_of("outcome", "alias")$kinds, "none")
  expect_identical(row_of("id", "scramble")$kinds, "none")
  expect_identical(row_of("other", "scramble")$kinds, "none")
  expect_identical(row_of("other", "alias")$kinds, "none")
  expect_identical(row_of("covariate", "scramble")$kinds, "all except other")
})

test_that("the grid agrees with .action_problem() on every combination", {
  opts <- role_options()
  kinds <- .kinds_vocab()
  for (i in seq_len(nrow(opts))) {
    workable <- kinds[vapply(
      kinds,
      function(k) is.na(.action_problem(opts$role[i], opts$action[i], k)),
      logical(1L)
    )]
    shown <- switch(opts$kinds[i],
      "all" = kinds,
      "none" = character(0L),
      "all except other" = setdiff(kinds, "other"),
      strsplit(opts$kinds[i], ", ", fixed = TRUE)[[1L]]
    )
    expect_identical(shown, workable)
  }
})

test_that("kind filters to the combinations valid for that kind", {
  fac <- role_options(kind = "factor")
  expect_true(all(vapply(
    seq_len(nrow(fac)),
    function(i) is.na(.action_problem(fac$role[i], fac$action[i], "factor")),
    logical(1L)
  )))
  expect_true(any(fac$role == "treatment" & fac$action == "alias"))
  expect_false(any(fac$role == "outcome" & fac$action == "scramble"))

  num <- role_options(kind = "numeric")
  expect_true(any(num$role == "outcome" & num$action == "scramble"))
  expect_false(any(num$role == "treatment" & num$action == "alias"))

  oth <- role_options(kind = "other")
  expect_setequal(unique(oth$action), c("keep", "drop"))
})

test_that("an unknown kind is rejected with the vocabulary shown", {
  expect_error(role_options(kind = "banana"), "must be one of")
  expect_error(role_options(kind = 1L), "must be one of")
  expect_error(role_options(kind = c("factor", "numeric")), "must be one of")
})
