# The guided front door: mode inheritance, argument forwarding, the summary
# and notices it prints, and input it must refuse.

dup_frame <- function() {
  set.seed(3)
  d <- data.frame(
    a = 1:8, a = round(stats::rnorm(8), 2), b = rep(c("x", "y"), 4),
    check.names = FALSE, stringsAsFactors = FALSE
  )
  d
}

no_rename_then <- function(expr) {
  withCallingHandlers(
    expr,
    masque_name_repaired = function(w) stop("a rename warning was raised")
  )
}

test_that("duplicated input column names give one classed refusal", {
  d <- dup_frame()
  r <- propose_roles(d, mode = "local", detect = FALSE)
  expect_error(
    no_rename_then(clean_table(d, quiet = TRUE)),
    class = "masque_duplicate_names_refusal"
  )
  expect_error(
    no_rename_then(mask(d, r, mode = "local", seed = 1)),
    class = "masque_duplicate_names_refusal"
  )
  expect_error(
    no_rename_then(masque(d, mode = "local", ask = FALSE, quiet = TRUE)),
    class = "masque_duplicate_names_refusal"
  )
  expect_error(
    no_rename_then(mask_set(list(t = d), mode = "local", quiet = TRUE)),
    class = "masque_duplicate_names_refusal"
  )
  # The refusal names the column the user has, not a generated one.
  err <- expect_error(clean_table(d, quiet = TRUE), "\"a\"")
  expect_false(grepl("a_1", conditionMessage(err), fixed = TRUE))
})
