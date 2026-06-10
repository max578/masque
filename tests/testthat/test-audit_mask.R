make_audit_fixture <- function(n = 100, seed = 0) {
  set.seed(seed)
  data.frame(
    Rep = rep(1:4, n / 4),
    Genotype = factor(rep(LETTERS[1:5], each = n / 5)),
    yield = rnorm(n, mean = 10, sd = 2),
    cov_n = rnorm(n),
    cov_c = factor(sample(c("alpha", "beta", "gamma"), n, replace = TRUE)),
    notes_id = paste0("note_", seq_len(n)),
    stringsAsFactors = FALSE
  )
}

basic_roles <- function(df) {
  r <- propose_roles(df)
  r$role[r$col == "yield"] <- "outcome"
  r
}

test_that("audit_mask returns a tibble with the spec'd schema", {
  df <- make_audit_fixture()
  r <- basic_roles(df)
  m <- mask(df, r, mode = "collaborate", seed = 1)
  out <- audit_mask(m, print = FALSE)

  expect_s3_class(out, "tbl_df")
  expect_named(out, c(
    "col", "role", "action", "kind", "leakage_class",
    "n_unique_levels", "freq_min", "exact_match_pct",
    "comparable_n",
    "na_pct", "na_pattern_uniqueness",
    "alias_status", "notes"
  ))
  expect_equal(nrow(out), ncol(df))
  expect_true(all(out$leakage_class %in% c("low", "medium", "high")))
})

test_that("Collaborate mode auto-runs audit and stores it on m@audit", {
  df <- make_audit_fixture()
  r <- basic_roles(df)
  m <- mask(df, r, mode = "collaborate", seed = 1)
  expect_false(is.null(m@audit))
  expect_s3_class(m@audit, "tbl_df")
})

test_that("Local mode does NOT auto-run audit", {
  df <- make_audit_fixture()
  r <- basic_roles(df)
  m <- suppressWarnings(mask(df, r, mode = "local", seed = 1))
  expect_null(m@audit)
})

test_that("audit_mask on a local masque requires `original`", {
  df <- make_audit_fixture()
  r <- basic_roles(df)
  m <- suppressWarnings(mask(df, r, mode = "local", seed = 1))
  expect_error(audit_mask(m, print = FALSE), "Supply")
  out <- audit_mask(m, original = df, print = FALSE)
  expect_s3_class(out, "tbl_df")
})

test_that("audit_mask flags PII-retained as HIGH", {
  set.seed(0)
  df <- data.frame(
    Rep = rep(1:4, 25),
    contact_person = factor(rep(c("A", "B"), 50)), # PII pattern -> auto ignore
    yield = rnorm(100),
    stringsAsFactors = FALSE
  )
  r <- propose_roles(df)
  r$role[r$col == "yield"] <- "outcome"
  # User OVERRIDES auto-flag and keeps contact_person as covariate
  r$role[r$col == "contact_person"] <- "covariate"
  expect_warning(
    m <- mask(df, r, mode = "collaborate", seed = 1),
    "HIGH leakage"
  )
  out <- audit_mask(m, print = FALSE)
  expect_equal(
    out$leakage_class[out$col == "contact_person"],
    "high"
  )
})

test_that("freq=1 categorical covariate is HIGH leakage in collaborate", {
  set.seed(0)
  df <- data.frame(
    Rep = rep(1:4, 25),
    rare = factor(
      c("only_one", sample(c("alpha", "beta"), 99, replace = TRUE))
    ),
    yield = rnorm(100),
    stringsAsFactors = FALSE
  )
  r <- propose_roles(df)
  r$role[r$col == "yield"] <- "outcome"
  expect_warning(
    m <- mask(df, r, mode = "collaborate", seed = 1),
    "HIGH leakage"
  )
  out <- audit_mask(m, print = FALSE)
  expect_equal(out$leakage_class[out$col == "rare"], "high")
})

test_that("Collaborate mode warns at mask() time on HIGH leakage", {
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
  expect_warning(mask(df, r, mode = "collaborate", seed = 1), "HIGH leakage")
})

test_that("Collaborate mode does NOT warn when nothing is HIGH", {
  df <- make_audit_fixture()
  r <- basic_roles(df)
  # All PII auto-ignored, no rare levels, no unaliased treatment -> no HIGH
  expect_no_warning(mask(df, r, mode = "collaborate", seed = 1))
})

test_that("Audit reports numeric exact-match-pct for outcome (collaborate)", {
  df <- make_audit_fixture(n = 1000)
  r <- basic_roles(df)
  m <- mask(df, r, mode = "collaborate", seed = 1)
  out <- audit_mask(m, print = FALSE)
  yield_row <- out[out$col == "yield", ]
  expect_true(is.finite(yield_row$exact_match_pct))
  expect_true(yield_row$exact_match_pct >= 0)
  expect_true(yield_row$exact_match_pct <= 100)
})

test_that("audit_mask errors on non-masque input", {
  expect_error(audit_mask(list()), "must be a")
})

test_that("audit_mask prints a styled report by default, returns invisibly", {
  df <- make_audit_fixture()
  r <- basic_roles(df)
  m <- mask(df, r, mode = "collaborate", seed = 1)
  joined <- capture_full(audit_mask(m))
  expect_match(joined, "masque audit")
  # ret is invisible
  ret <- audit_mask(m, print = FALSE)
  expect_s3_class(ret, "tbl_df")
})
