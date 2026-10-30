# The NA-pattern uniqueness share, grouped rather than pasted row by row.

# The row-paste computation the audit used before 0.16.0.
.na_uniqueness_paste <- function(df) {
  if (nrow(df) == 0L) {
    return(NA_real_)
  }
  na_mat <- is.na(df)
  patterns <- apply(na_mat, 1L, function(r) paste(as.integer(r), collapse = ""))
  freqs <- table(patterns)
  sum(freqs == 1L) / nrow(df)
}

test_that("the grouped NA-pattern share equals the row-paste share", {
  set.seed(16L)
  n <- 400L
  mixed <- data.frame(
    a = ifelse(runif(n) < 0.2, NA, rnorm(n)),
    b = factor(ifelse(runif(n) < 0.4, NA, sample(letters[1:3], n, TRUE))),
    c = as.Date(ifelse(runif(n) < 0.05, NA, 19000 + seq_len(n))),
    d = ifelse(runif(n) < 0.01, NA_character_, "x"),
    e = ifelse(runif(n) < 0.3, NA, TRUE)
  )
  fixtures <- list(
    complete = data.frame(a = 1:10, b = letters[1:10]),
    all_missing = data.frame(a = rep(NA_real_, 6L), b = rep(NA_character_, 6L)),
    one_row = data.frame(a = NA, b = 1),
    one_row_complete = data.frame(a = 1, b = 2),
    alternating = data.frame(a = c(1, NA, 3, NA, 5), b = c(NA, 2, NA, 4, NA)),
    mixed = mixed,
    duplicate_names = stats::setNames(
      data.frame(c(1, NA, 3), c(NA, NA, 3), c(1, 2, NA)), c("x", "x", "x y")
    ),
    no_columns = data.frame(row.names = 1:3),
    no_rows = data.frame(a = numeric(), b = character())
  )
  for (nm in names(fixtures)) {
    expect_identical(
      masque:::.global_na_pattern_uniqueness(fixtures[[nm]]),
      .na_uniqueness_paste(fixtures[[nm]]),
      info = nm
    )
  }
  expect_identical(masque:::.global_na_pattern_uniqueness(fixtures$complete), 0)
  expect_identical(
    masque:::.global_na_pattern_uniqueness(fixtures$all_missing), 0
  )
  expect_true(is.na(masque:::.global_na_pattern_uniqueness(fixtures$no_rows)))
})

test_that("the grouped NA-pattern share is much faster than the row paste", {
  skip_on_cran()
  set.seed(17L)
  n <- 200000L
  big <- as.data.frame(lapply(seq_len(12L), function(j) {
    x <- rnorm(n)
    x[runif(n) < 0.05 * j / 4] <- NA
    x
  }))
  t_paste <- system.time(ref <- .na_uniqueness_paste(big))[["elapsed"]]
  t_grouped <- system.time(
    out <- masque:::.global_na_pattern_uniqueness(big)
  )[["elapsed"]]
  expect_identical(out, ref)
  # Measured near 100x; 5x leaves room for a loaded machine.
  expect_lt(t_grouped * 5, t_paste)
})
