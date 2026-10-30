# Near-duplicate labels: coded vocabularies are not typos, the report is
# capped, and the recipe keeps a short plain record.

near_dup_count <- function(x) {
  nrow(clean_table(data.frame(g = x), quiet = TRUE)$near_duplicates)
}

test_that("an edit inside a run of digits is not a near-duplicate", {
  expect_equal(near_dup_count(rep(sprintf("G%02d", 1:24), 2)), 0L)
  expect_equal(near_dup_count(sprintf("G%03d", 1:80)), 0L)
  expect_equal(near_dup_count(c("Plot12", "Plot13", "Plot2", "Plot21")), 0L)
  expect_equal(near_dup_count(c("Year2023", "Year2024")), 0L)
})

test_that("real near-duplicates are still reported", {
  nd <- clean_table(
    data.frame(g = c("north", "North", "Ashfield", "Ashfiel", "G0l", "G01")),
    quiet = TRUE
  )$near_duplicates
  pairs <- vapply(seq_len(nrow(nd)), function(i) {
    paste(sort(c(nd$a[i], nd$b[i]), method = "radix"), collapse = " ")
  }, character(1L))
  expect_setequal(pairs, c("North north", "Ashfiel Ashfield", "G01 G0l"))
})

wordy <- function() {
  # 26 labels, every pair one letter apart: 325 near-duplicate pairs.
  data.frame(word = rep(paste0("word", letters), 2))
}

test_that("the printed near-duplicate report is capped at 20 pairs", {
  msgs <- testthat::capture_messages(clean_table(wordy()))
  pair_lines <- grep("~", msgs, value = TRUE, fixed = TRUE)
  expect_equal(length(pair_lines), 20L)
  expect_true(any(grepl("305 more", msgs, fixed = TRUE)))
  expect_true(any(grepl("325", msgs, fixed = TRUE)))
})

test_that("the recipe keeps the count and 20 pairs as a plain data frame", {
  d <- wordy()
  d$y <- seq_len(nrow(d))
  r <- propose_roles(d, mode = "local", detect = FALSE)
  rec <- recipe(mask(d, r, mode = "local", seed = 1))
  expect_identical(rec@cleaning$n_near_duplicates, 325L)
  expect_identical(class(rec@cleaning$near_duplicates), "data.frame")
  expect_equal(nrow(rec@cleaning$near_duplicates), 20L)

  path <- withr::local_tempfile(fileext = ".rds")
  saveRDS(rec, path)
  expect_identical(readRDS(path), rec)
})

test_that("conform_table never merges codes that differ inside a digit run", {
  g <- factor(c(
    rep("G001", 3), rep("G002", 2), rep("G010", 4), "G011", rep("G020", 2)
  ))
  cf <- conform_table(data.frame(genotype = g), merge_labels = "auto",
    quiet = TRUE
  )
  expect_identical(cf$data$genotype, g)
  expect_equal(nrow(cf$merges), 0L)

  e <- c(rep("Entry10", 5), rep("Entry11", 2), rep("Entry12", 3), "Entry13")
  ce <- conform_table(data.frame(entry = e), merge_labels = "auto",
    types = "auto", quiet = TRUE
  )
  expect_identical(as.character(ce$data$entry), e)
})
