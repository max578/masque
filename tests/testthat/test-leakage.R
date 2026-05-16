test_that(".classify_leakage flags PII-retained-as-not-ignored as HIGH", {
  out <- masque:::.classify_leakage(
    role = "covariate", kind = "numeric", pii = TRUE, mode = "collaborate",
    in_synth = TRUE, alias_status = "passthrough",
    exact_match_pct = 0, freq_min = NA_integer_,
    n_unique_levels = NA_integer_, n_rows = 100L
  )
  expect_equal(out, "high")
})

test_that(".classify_leakage flags treatment passthrough in collaborate as HIGH", {
  out <- masque:::.classify_leakage(
    role = "treatment", kind = "factor", pii = FALSE, mode = "collaborate",
    in_synth = TRUE, alias_status = "passthrough",
    exact_match_pct = NA_real_, freq_min = 5L,
    n_unique_levels = 5L, n_rows = 100L
  )
  expect_equal(out, "high")
})

test_that(".classify_leakage flags freq=1 categorical covariate in collaborate as HIGH", {
  out <- masque:::.classify_leakage(
    role = "covariate", kind = "factor", pii = FALSE, mode = "collaborate",
    in_synth = TRUE, alias_status = "aliased",
    exact_match_pct = NA_real_, freq_min = 1L,
    n_unique_levels = 10L, n_rows = 100L
  )
  expect_equal(out, "high")
})

test_that(".classify_leakage flags outcome exact-match > 1% in collaborate as MEDIUM", {
  out <- masque:::.classify_leakage(
    role = "outcome", kind = "numeric", pii = FALSE, mode = "collaborate",
    in_synth = TRUE, alias_status = "passthrough",
    exact_match_pct = 1.5, freq_min = NA_integer_,
    n_unique_levels = NA_integer_, n_rows = 100L
  )
  expect_equal(out, "medium")
})

test_that(".classify_leakage flags numeric covariate exact-match > 5% in collaborate as MEDIUM", {
  out <- masque:::.classify_leakage(
    role = "covariate", kind = "numeric", pii = FALSE, mode = "collaborate",
    in_synth = TRUE, alias_status = "passthrough",
    exact_match_pct = 5.5, freq_min = NA_integer_,
    n_unique_levels = NA_integer_, n_rows = 100L
  )
  expect_equal(out, "medium")
})

test_that(".classify_leakage returns LOW for ignore retained in local", {
  out <- masque:::.classify_leakage(
    role = "ignore", kind = "character", pii = FALSE, mode = "local",
    in_synth = TRUE, alias_status = "passthrough",
    exact_match_pct = NA_real_, freq_min = NA_integer_,
    n_unique_levels = 5L, n_rows = 100L
  )
  expect_equal(out, "low")
})

test_that(".classify_leakage returns LOW when nothing matches", {
  out <- masque:::.classify_leakage(
    role = "design", kind = "numeric", pii = FALSE, mode = "local",
    in_synth = TRUE, alias_status = "passthrough",
    exact_match_pct = NA_real_, freq_min = NA_integer_,
    n_unique_levels = NA_integer_, n_rows = 100L
  )
  expect_equal(out, "low")
})

test_that(".global_na_pattern_uniqueness on no-NA df = 0", {
  df <- data.frame(a = 1:10, b = 11:20)
  expect_equal(masque:::.global_na_pattern_uniqueness(df), 0)
})

test_that(".global_na_pattern_uniqueness on per-row-unique NA = 1", {
  df <- data.frame(a = c(1, NA, 3, NA, 5), b = c(NA, 2, NA, 4, NA))
  # Patterns: 01, 10, 01, 10, 01 -> all duplicates (3,2), uniqueness 0
  expect_equal(masque:::.global_na_pattern_uniqueness(df), 0)
  # Now build one with one unique row:
  df2 <- data.frame(a = c(1, NA, 3, NA, 5), b = c(NA, 2, NA, 4, NA), c = c(NA, NA, NA, NA, 99))
  # Row 5 has NA pattern 010 (unique); others share 100/010 patterns
  u <- masque:::.global_na_pattern_uniqueness(df2)
  expect_gt(u, 0)
})
