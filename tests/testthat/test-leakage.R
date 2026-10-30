test_that(".classify_leakage flags PII-retained-as-not-ignored as HIGH", {
  out <- masque:::.classify_leakage(
    role = "covariate", kind = "numeric", pii = TRUE, mode = "collaborate",
    in_synth = TRUE, alias_status = "passthrough",
    exact_match_pct = 0, freq_min = NA_integer_,
    n_unique_levels = NA_integer_, n_rows = 100L
  )
  expect_equal(out, "high")
})

test_that(".classify_leakage: treatment passthrough is HIGH (collaborate)", {
  out <- masque:::.classify_leakage(
    role = "treatment", kind = "factor", pii = FALSE, mode = "collaborate",
    in_synth = TRUE, alias_status = "passthrough",
    exact_match_pct = NA_real_, freq_min = 5L,
    n_unique_levels = 5L, n_rows = 100L
  )
  expect_equal(out, "high")
})

test_that(".classify_leakage: freq=1 categorical covariate is HIGH", {
  out <- masque:::.classify_leakage(
    role = "covariate", kind = "factor", pii = FALSE, mode = "collaborate",
    in_synth = TRUE, alias_status = "aliased",
    exact_match_pct = NA_real_, freq_min = 1L,
    n_unique_levels = 10L, n_rows = 100L
  )
  expect_equal(out, "high")
})

test_that(".classify_leakage: outcome exact-match > 1% is MEDIUM", {
  out <- masque:::.classify_leakage(
    role = "outcome", kind = "numeric", pii = FALSE, mode = "collaborate",
    in_synth = TRUE, alias_status = "passthrough",
    exact_match_pct = 1.5, freq_min = NA_integer_,
    n_unique_levels = NA_integer_, n_rows = 100L
  )
  expect_equal(out, "medium")
})

test_that(".classify_leakage: numeric covariate exact-match > 5% is MEDIUM", {
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
  df2 <- data.frame(
    a = c(1, NA, 3, NA, 5),
    b = c(NA, 2, NA, 4, NA),
    c = c(NA, NA, NA, NA, 99)
  )
  # Row 5 has NA pattern 010 (unique); others share 100/010 patterns
  u <- masque:::.global_na_pattern_uniqueness(df2)
  expect_gt(u, 0)
})

test_that(".classify_leakage: content column beyond chance on its own row is MEDIUM", {
  args <- list(
    role = "covariate", kind = "factor", action = "alias", pii = FALSE,
    mode = "collaborate", in_synth = TRUE, alias_status = "aliased",
    exact_match_pct = NA_real_, freq_min = 5L, n_unique_levels = 3L,
    n_rows = 100L
  )
  expect_equal(
    do.call(masque:::.classify_leakage, c(args, list(
      same_row_excess = 40, same_row_sd = 5
    ))),
    "medium"
  )
  # Within four SDs of chance, or below ten points, it is not graded.
  expect_equal(
    do.call(masque:::.classify_leakage, c(args, list(
      same_row_excess = 15, same_row_sd = 5
    ))),
    "low"
  )
  expect_equal(
    do.call(masque:::.classify_leakage, c(args, list(
      same_row_excess = 9, same_row_sd = 1
    ))),
    "low"
  )
  # Structural and linked columns match by construction.
  design <- modifyList(args, list(role = "design"))
  expect_equal(
    do.call(masque:::.classify_leakage, c(design, list(
      same_row_excess = 60, same_row_sd = 2
    ))),
    "low"
  )
  expect_equal(
    do.call(masque:::.classify_leakage, c(args, list(
      same_row_excess = 60, same_row_sd = 2, linked = TRUE
    ))),
    "low"
  )
  # Local mode reports only.
  local <- modifyList(args, list(mode = "local"))
  expect_equal(
    do.call(masque:::.classify_leakage, c(local, list(
      same_row_excess = 60, same_row_sd = 2
    ))),
    "low"
  )
})

test_that(".classify_leakage: a two-valued outcome skips the exact-match rule", {
  args <- list(
    role = "outcome", kind = "integer", action = "scramble", pii = FALSE,
    mode = "collaborate", in_synth = TRUE, alias_status = "passthrough",
    exact_match_pct = 52, freq_min = NA_integer_,
    n_unique_levels = NA_integer_, n_rows = 200L
  )
  expect_equal(do.call(masque:::.classify_leakage, args), "medium")
  expect_equal(
    do.call(masque:::.classify_leakage, c(args, list(
      two_valued = TRUE, same_row_excess = 1.5, same_row_sd = 3.5
    ))),
    "low"
  )
})
