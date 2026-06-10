make_valid_roles <- function() {
  r <- propose_roles(iris)
  r$role[r$col == "Sepal.Length"] <- "outcome"
  r
}

test_that("roles_validate accepts a clean roles tibble", {
  r <- make_valid_roles()
  expect_invisible(roles_validate(r))
  expect_invisible(roles_validate(r, iris))
})

test_that("roles_validate errors on non-data-frame", {
  expect_error(
    roles_validate(list(col = "x", role = "outcome", kind = "numeric")),
    "must be a data frame"
  )
})

test_that("roles_validate errors when required columns are missing", {
  r <- make_valid_roles()
  expect_error(
    roles_validate(r[, c("col", "role")]),
    "missing required column.*kind"
  )
  expect_error(
    roles_validate(r[, c("col", "kind")]),
    "missing required column.*role"
  )
  expect_error(
    roles_validate(r[, c("role", "kind")]),
    "missing required column.*col"
  )
})

test_that("roles_validate errors on NA role", {
  r <- make_valid_roles()
  r$role[1] <- NA
  expect_error(roles_validate(r), "NA")
})

test_that("roles_validate errors on unknown role string", {
  r <- make_valid_roles()
  r$role[1] <- "blocker"
  expect_error(roles_validate(r), "Unknown role")
})

test_that("roles_validate errors when no outcome flagged", {
  r <- propose_roles(iris) # propose_roles never picks outcome
  expect_error(roles_validate(r), "outcome")
})

test_that("roles_validate accepts multiple treatment columns", {
  # Joint-treatment masking (factorial / split-plot designs) is supported:
  # two or more treatment factors must validate cleanly.
  r <- make_valid_roles()
  r$role[r$col %in% c("Sepal.Width", "Petal.Width")] <- "treatment"
  expect_invisible(roles_validate(r))
  expect_invisible(roles_validate(r, iris))
})

test_that("roles_validate accepts explicit keep columns", {
  r <- make_valid_roles()
  r$role[r$col == "Species"] <- "keep"
  expect_invisible(roles_validate(r))
  expect_invisible(roles_validate(r, iris))
})

test_that("roles_validate errors on duplicate col entries", {
  r <- make_valid_roles()
  r <- rbind(r, r[1, ])
  expect_error(roles_validate(r), "Duplicate")
})

test_that("roles_validate errors when unsupported columns are covariates", {
  df <- data.frame(
    payload = I(list(list(a = 1), list(a = 2), list(a = 3))),
    yield = c(1.0, 2.0, 3.0)
  )
  r <- propose_roles(df, detect = FALSE)
  r$role[r$col == "yield"] <- "outcome"
  r$role[r$col == "payload"] <- "covariate"
  expect_error(roles_validate(r, df), "Unsupported")
})

test_that("roles_validate cross-checks df columns when df supplied", {
  r <- make_valid_roles()
  # Drop a row -> df has a column not in roles
  expect_error(roles_validate(r[-1, ], iris), "not in.*roles")
  # Add a row -> roles has a column not in df
  r_extra <- r
  r_extra <- rbind(r_extra, data.frame(
    col = "ghost", role = "covariate", kind = "numeric",
    freq_or_range = "[0, 1]", pii_suspected = FALSE, notes = "test",
    stringsAsFactors = FALSE
  ))
  expect_error(roles_validate(r_extra, iris), "not in.*df")
})

test_that("roles_validate returns the roles tibble invisibly", {
  r <- make_valid_roles()
  out <- withVisible(roles_validate(r))
  expect_false(out$visible)
  expect_identical(out$value, r)
})
