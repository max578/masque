# The null clone is a function of the design columns, the missing-value mask,
# each column's coarse summary and kind, and the seed. Swapping the real
# values for others with the same summary must leave it byte-identical.

null_guard_fixture <- function() {
  withr::with_seed(11L, {
    n <- 48L
    df <- data.frame(
      block = factor(rep(sprintf("B%d", 1:4), each = 12L)),
      variety = factor(rep(sprintf("V%02d", 1:12), 4L)),
      yield = round(stats::rnorm(n, 5, 1), 2),
      protein = stats::runif(n, 9, 14),
      count = stats::rpois(n, 3),
      soil = sample(c("clay", "loam", "sand"), n, TRUE),
      irrigated = sample(c(TRUE, FALSE), n, TRUE),
      sown = as.Date("2021-05-01") + sample(0:30, n, TRUE),
      stringsAsFactors = FALSE
    )
    df$protein[c(3L, 17L, 40L)] <- NA
    df$soil[c(5L, 6L)] <- NA
    df$yield[9L] <- NA
    df
  })
}

# Permute the observed values of each non-design column among its observed
# cells: same multiset (so the same summary and levels), same NA mask, new
# rows. The design columns are untouched.
null_guard_swap <- function(df, design) {
  withr::with_seed(99L, {
    for (col in setdiff(names(df), design)) {
      obs <- which(!is.na(df[[col]]))
      df[[col]][obs] <- df[[col]][obs][sample.int(length(obs))]
    }
  })
  df
}

null_guard_roles <- function(df, mode) {
  r <- propose_roles(df, mode = mode, detect = FALSE)
  r <- set_role(r, "block", role = "design")
  r <- set_role(r, "variety", role = "treatment")
  set_role(r, "yield", role = "outcome")
}

test_that("a null clone uses no value beyond each column's summary", {
  df <- null_guard_fixture()
  swapped <- null_guard_swap(df, c("block", "variety"))
  expect_false(identical(df$yield, swapped$yield))

  r <- null_guard_roles(df, "null")
  a <- synthetic(mask(df, r, mode = "null", seed = 7L, quiet = TRUE))
  b <- synthetic(mask(swapped, r, mode = "null", seed = 7L, quiet = TRUE))
  expect_identical(a, b)
  expect_identical(
    serialize(a, NULL, version = 3L), serialize(b, NULL, version = 3L)
  )
})

test_that("the same holds for standard draws", {
  df <- null_guard_fixture()
  swapped <- null_guard_swap(df, c("block", "variety"))
  r <- null_guard_roles(df, "null")
  a <- synthetic(mask(df, r, seed = 7L, noise = "standard", quiet = TRUE))
  b <- synthetic(mask(swapped, r, seed = 7L, noise = "standard", quiet = TRUE))
  expect_identical(a, b)
})

test_that("the guard fails on a local clone, which keeps structure", {
  df <- null_guard_fixture()
  swapped <- null_guard_swap(df, c("block", "variety"))
  r <- null_guard_roles(df, "local")
  a <- synthetic(mask(df, r, mode = "local", seed = 7L, quiet = TRUE))
  b <- synthetic(mask(swapped, r, mode = "local", seed = 7L, quiet = TRUE))
  expect_false(identical(a, b))
})

test_that("the guard fails on a collaborate clone", {
  df <- null_guard_fixture()
  swapped <- null_guard_swap(df, c("block", "variety"))
  r <- null_guard_roles(df, "collaborate")
  a <- suppressWarnings(synthetic(
    mask(df, r, mode = "collaborate", seed = 7L, quiet = TRUE)
  ))
  b <- suppressWarnings(synthetic(
    mask(swapped, r, mode = "collaborate", seed = 7L, quiet = TRUE)
  ))
  expect_false(identical(a, b))
})

test_that("a changed summary changes the null clone", {
  df <- null_guard_fixture()
  shifted <- df
  shifted$protein <- shifted$protein + 1
  r <- null_guard_roles(df, "null")
  a <- synthetic(mask(df, r, seed = 7L, quiet = TRUE))
  b <- synthetic(mask(shifted, r, seed = 7L, quiet = TRUE))
  expect_false(identical(a$protein, b$protein))
  expect_identical(a$yield, b$yield)
})
