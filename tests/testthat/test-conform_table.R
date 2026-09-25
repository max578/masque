test_that("report mode changes nothing but names every decision", {
  df <- data.frame(
    state = c("NSW", "Nsw", "NSW", "VIC", "VIC", "vic"),
    yield = c("3.1", "2.9", "5.0", "4.2", "3.8", "4.4"),
    stringsAsFactors = FALSE
  )
  cf <- conform_table(df, quiet = TRUE)
  expect_s3_class(cf, "masque_conformance")
  expect_identical(vapply(cf$data, function(z) class(z)[1], ""),
                   c(state = "character", yield = "character"))
  expect_true(all(!cf$assumptions$applied))
  expect_true(any(grepl("same category", cf$assumptions$assumption)))
})

test_that("auto mode merges case-only labels and sets storage", {
  df <- data.frame(
    state = c("NSW", "Nsw", "NSW", "VIC", "VIC", "vic"),
    yield = c("3.1", "2.9", "5.0", "4.2", "3.8", "4.4"),
    sown  = c("2024-05-01", "2024-05-03", "2024-05-01",
              "2024-05-08", "2024-05-08", "2024-05-02"),
    stringsAsFactors = FALSE
  )
  cf <- conform_table(df, merge_labels = "auto", types = "auto", quiet = TRUE)
  expect_identical(levels(cf$data$state), c("NSW", "VIC"))
  expect_true(is.numeric(cf$data$yield))
  expect_s3_class(cf$data$sown, "Date")
  expect_true(all(cf$assumptions$applied))
})

test_that("storage is decided before categories, so numbers are never merged", {
  # "4.2" and "4.4" differ by one character; they are values, not categories
  df <- data.frame(yield = c("3.1", "4.2", "4.4", "5.0"), stringsAsFactors = FALSE)
  cf <- conform_table(df, merge_labels = "auto", types = "auto", quiet = TRUE)
  expect_equal(nrow(cf$merges), 0L)
  expect_true(is.numeric(cf$data$yield))
})

test_that("a one-edit difference between short labels is not a typo", {
  df <- data.frame(g = c("a", "b", "a", "b", "c", "c"), stringsAsFactors = FALSE)
  cf <- conform_table(df, merge_labels = "auto", types = "auto", quiet = TRUE)
  expect_equal(nrow(cf$merges), 0L)
  expect_identical(sort(levels(cf$data$g)), c("a", "b", "c"))
})

test_that("an edit-distance tie is refused, not broken", {
  # a single deletion, each spelling once: one edit apart with no majority.
  # (A transposition such as "Ashfeild" is TWO edits and is never flagged.)
  df <- data.frame(
    site = c("Ashfield", "Ashfiel", "Burwood", "Burwood", "Concord", "Concord"),
    stringsAsFactors = FALSE
  )
  cf <- conform_table(df, merge_labels = "auto", types = "auto", quiet = TRUE)
  tie <- cf$merges[cf$merges$n_from == cf$merges$n_to, , drop = FALSE]
  expect_gt(nrow(tie), 0L)
  expect_true(all(!tie$applied))
  expect_true(any(grepl("equally", tie$reason)))
  # and the refusal means both spellings survive
  expect_true(all(c("Ashfield", "Ashfiel") %in% levels(cf$data$site)))
})

test_that("off means off", {
  df <- data.frame(state = c("NSW", "Nsw"), stringsAsFactors = FALSE)
  cf <- conform_table(df, merge_labels = "off", types = "off", quiet = TRUE)
  expect_equal(nrow(cf$merges), 0L)
  expect_equal(nrow(cf$types), 0L)
  expect_identical(cf$data$state, c("NSW", "Nsw"))
})

test_that("a column left as text names the reason that applies to it", {
  df <- data.frame(
    id = c("a1", "b2", "c3", "d4"),
    n_applied = c("1.5", "2.0", "n/a", "3.5", "4.0", "5.5", "6.0", "7.5")[1:4],
    stringsAsFactors = FALSE
  )
  df$id <- sprintf("id_%02d", 1:4)
  cf <- conform_table(df, quiet = TRUE)
  r <- setNames(cf$types$reason, cf$types$col)
  expect_match(r[["id"]], "^all 4 labels are distinct")
  expect_match(r[["n_applied"]], "^1 of 4 values do not parse as a number \\(first: \"n/a\"\\)")

  wide <- data.frame(g = rep(sprintf("L%02d", 1:25), 2), stringsAsFactors = FALSE)
  cw <- conform_table(wide, quiet = TRUE)
  expect_match(cw$types$reason, "above max_levels = 20")
})
