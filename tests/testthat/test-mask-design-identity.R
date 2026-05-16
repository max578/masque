test_that("design columns are byte-identical between original and synthetic", {
  set.seed(0)
  df <- data.frame(
    Rep    = rep(1:4, 25),
    block  = rep(1:5, each = 20),
    site   = factor(rep(c("S1","S2","S3","S4"), 25)),
    year   = rep(2020:2024, each = 20),
    yield  = rnorm(100, mean = 5, sd = 1),
    cov1   = rnorm(100),
    stringsAsFactors = FALSE
  )
  r <- propose_roles(df)
  r$role[r$col == "yield"] <- "outcome"

  m <- mask(df, r, seed = 1)
  s <- m$synthetic

  expect_identical(s$Rep,   df$Rep)
  expect_identical(s$block, df$block)
  expect_identical(s$site,  df$site)
  expect_identical(s$year,  df$year)
})

test_that("treatment column passes through in step 3 (level handling in step 4)", {
  set.seed(0)
  df <- data.frame(
    Rep      = rep(1:4, 5),
    Genotype = factor(rep(LETTERS[1:5], 4)),
    yield    = rnorm(20),
    stringsAsFactors = FALSE
  )
  r <- propose_roles(df)
  r$role[r$col == "yield"] <- "outcome"

  m <- mask(df, r, seed = 1)
  expect_identical(m$synthetic$Genotype, df$Genotype)
})

test_that("ignore columns pass through in local mode", {
  set.seed(0)
  df <- data.frame(
    Rep         = rep(1:4, 5),
    yield       = rnorm(20),
    sowing_date = as.Date("2026-01-01") + 1:20,  # auto -> ignore
    stringsAsFactors = FALSE
  )
  r <- propose_roles(df)
  r$role[r$col == "yield"] <- "outcome"

  m <- mask(df, r, seed = 1)
  expect_identical(m$synthetic$sowing_date, df$sowing_date)
})

test_that("synthetic has the same shape and column order as original", {
  set.seed(0)
  df <- data.frame(
    a = 1:50,            # auto -> covariate (integer)
    b = rnorm(50),       # auto -> covariate (we re-role)
    c = factor(rep(c("x","y"), 25)),
    stringsAsFactors = FALSE
  )
  r <- propose_roles(df)
  r$role[r$col == "b"] <- "outcome"

  m <- mask(df, r, seed = 1)
  expect_equal(dim(m$synthetic), dim(df))
  expect_identical(names(m$synthetic), names(df))
})
