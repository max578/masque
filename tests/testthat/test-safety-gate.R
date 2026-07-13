# Safety-gate regressions: the guided flow must surface HIGH leakage
# findings, and package-managed writers must refuse to write a blocked
# collaborate-mode object. Guards against the v0.7.x defect where
# masque() / mask_set() wrapped mask() in suppressWarnings() and then
# printed share-ready language.

# Trips the "retained PII-pattern column" HIGH rule in collaborate mode.
high_fixture <- function() {
  set.seed(0)
  df <- data.frame(
    Rep = rep(1:4, 25),
    contact_email = factor(rep(c("a", "b"), 50)),
    yield = rnorm(100),
    stringsAsFactors = FALSE
  )
  r <- propose_roles(df)
  r$role[r$col == "yield"] <- "outcome"
  r$role[r$col == "contact_email"] <- "covariate"
  list(df = df, roles = r)
}

# No HIGH finding in collaborate mode.
clean_fixture <- function() {
  set.seed(0)
  df <- data.frame(
    Rep = rep(1:4, 25),
    Genotype = factor(rep(LETTERS[1:5], each = 20)),
    yield = rnorm(100, mean = 10, sd = 2),
    stringsAsFactors = FALSE
  )
  r <- propose_roles(df)
  r$role[r$col == "yield"] <- "outcome"
  list(df = df, roles = r)
}

test_that("guided masque() surfaces the HIGH leakage warning (single table)", {
  f <- high_fixture()
  seen <- NULL
  withCallingHandlers(
    m <- masque(
      f$df,
      roles = f$roles, mode = "collaborate", seed = 1,
      ask = FALSE, quiet = TRUE
    ),
    masque_high_leakage = function(w) {
      seen <<- conditionMessage(w)
      invokeRestart("muffleWarning")
    }
  )
  expect_match(seen, "HIGH leakage")
  expect_match(seen, "contact_email")
})

test_that("guided masque() surfaces the HIGH leakage warning (set)", {
  f <- high_fixture()
  tables <- list(
    trial = f$df,
    sites = data.frame(loc = c("x", "y"), depth = c(1.2, 3.4))
  )
  roles <- list(trial = f$roles, sites = propose_roles(tables$sites))
  seen <- FALSE
  withCallingHandlers(
    m <- masque(
      tables,
      roles = roles, mode = "collaborate", seed = 1,
      ask = FALSE, quiet = TRUE
    ),
    masque_high_leakage = function(w) {
      seen <<- TRUE
      invokeRestart("muffleWarning")
    }
  )
  expect_true(seen)
})

test_that("blocked write: masque(out = ) refuses and writes nothing", {
  f <- high_fixture()
  out <- file.path(tempdir(), "masque-blocked-single.csv")
  on.exit(unlink(out), add = TRUE)
  expect_error(
    suppressWarnings(masque(
      f$df,
      roles = f$roles, mode = "collaborate", seed = 1,
      ask = FALSE, quiet = TRUE, out = out
    )),
    class = "masque_blocked_write"
  )
  expect_false(file.exists(out))
})

test_that("blocked write: write_set() refuses and writes nothing", {
  f <- high_fixture()
  tables <- list(
    trial = f$df,
    sites = data.frame(loc = c("x", "y"), depth = c(1.2, 3.4))
  )
  roles <- list(trial = f$roles, sites = propose_roles(tables$sites))
  m <- suppressWarnings(mask_set(
    tables,
    roles = roles, mode = "collaborate", seed = 1, quiet = TRUE
  ))
  dir <- file.path(tempdir(), "masque-blocked-set")
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  expect_error(write_set(m, dir), class = "masque_blocked_write")
  expect_false(dir.exists(dir))
})

test_that("allow_high = TRUE writes, warns the override, and records it", {
  f <- high_fixture()
  out <- file.path(tempdir(), "masque-override-single.csv")
  on.exit(unlink(out), add = TRUE)
  seen <- character()
  withCallingHandlers(
    m <- masque(
      f$df,
      roles = f$roles, mode = "collaborate", seed = 1,
      ask = FALSE, quiet = TRUE, out = out, allow_high = TRUE
    ),
    warning = function(w) {
      seen <<- c(seen, class(w)[1])
      invokeRestart("muffleWarning")
    }
  )
  expect_true("masque_high_leakage" %in% seen)
  expect_true("masque_high_override" %in% seen)
  expect_true(file.exists(out))
  expect_true(any(grepl("overridden at write time", recipe(m)@warnings)))
})

test_that("blocked summary is status-first and avoids release language", {
  f <- high_fixture()
  msgs <- testthat::capture_messages(
    m <- suppressWarnings(masque(
      f$df,
      roles = f$roles, mode = "collaborate", seed = 1,
      ask = FALSE, quiet = FALSE
    ))
  )
  expect_true(any(grepl("BLOCKED", msgs)))
  # The fixture trips two HIGH rules: the retained PII-pattern column and
  # the byte-identical Rep design column.
  expect_true(any(grepl("2 HIGH", msgs)))
  expect_false(any(grepl("\\bshare\\b|\\bsend\\b|\\bsafe\\b", msgs,
    ignore.case = TRUE
  )))
})

test_that("clean collaborate objects write ungated", {
  f <- clean_fixture()
  out <- file.path(tempdir(), "masque-clean-collab.csv")
  on.exit(unlink(out), add = TRUE)
  expect_no_warning(
    m <- masque(
      f$df,
      roles = f$roles, mode = "collaborate", seed = 1,
      ask = FALSE, quiet = TRUE, out = out
    )
  )
  expect_true(file.exists(out))
  expect_false(any(grepl("overridden", recipe(m)@warnings)))
})

test_that("mask() errors on unused arguments instead of ignoring them", {
  r <- propose_roles(iris)
  r$role[r$col == "Sepal.Length"] <- "outcome"
  expect_error(mask(iris, r, sedd = 1), "sedd")
  expect_error(mask(iris, r, sedd = 1), "Unused")
  expect_error(mask(iris, r, sedd = 1, cleen = "off"), "arguments")
})

test_that("local mode is never gated", {
  r <- propose_roles(iris)
  r$role[r$col == "Sepal.Length"] <- "outcome"
  out <- file.path(tempdir(), "masque-local.csv")
  on.exit(unlink(out), add = TRUE)
  expect_no_warning(
    m <- masque(iris,
      roles = r, seed = 1,
      ask = FALSE, quiet = TRUE, out = out
    )
  )
  expect_true(file.exists(out))
})
