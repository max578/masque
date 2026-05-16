test_that("print(recipe) does not leak original level labels (collaborate)", {
  set.seed(0)
  df <- data.frame(
    Rep      = rep(1:4, 25),
    Genotype = factor(rep(c("VarietyAlpha","VarietyBeta","VarietyGamma","VarietyDelta","VarietyEpsilon"), each = 20)),
    yield    = rnorm(100),
    stringsAsFactors = FALSE
  )
  r <- propose_roles(df)
  r$role[r$col == "yield"] <- "outcome"

  m <- mask(df, r, mode = "collaborate", seed = 1)
  joined <- capture_full(print(recipe(m)))

  for (lbl in c("VarietyAlpha","VarietyBeta","VarietyGamma","VarietyDelta","VarietyEpsilon")) {
    expect_false(grepl(lbl, joined, fixed = TRUE), info = sprintf("Original label leaked: %s", lbl))
  }
  expect_match(joined, "PRIVATE", fixed = TRUE)
})

test_that("print(recipe) shows level-map markers but not contents", {
  set.seed(0)
  df <- data.frame(
    Rep      = rep(1:4, 25),
    Genotype = factor(rep(c("VarietyAlpha","VarietyBeta","VarietyGamma","VarietyDelta","VarietyEpsilon"), each = 20)),
    yield    = rnorm(100),
    stringsAsFactors = FALSE
  )
  r <- propose_roles(df)
  r$role[r$col == "yield"] <- "outcome"

  m <- mask(df, r, mode = "collaborate", seed = 1)
  joined <- capture_full(print(recipe(m)))

  expect_match(joined, "\\* +treatment\\s+Genotype")
})

test_that("reveal_maps(recipe) prints the original labels (audited reveal)", {
  set.seed(0)
  df <- data.frame(
    Rep      = rep(1:4, 25),
    Genotype = factor(rep(c("VarietyAlpha","VarietyBeta","VarietyGamma","VarietyDelta","VarietyEpsilon"), each = 20)),
    yield    = rnorm(100),
    stringsAsFactors = FALSE
  )
  r <- propose_roles(df)
  r$role[r$col == "yield"] <- "outcome"

  m <- mask(df, r, mode = "collaborate", seed = 1)
  joined <- capture_full(reveal_maps(recipe(m)))

  for (lbl in c("VarietyAlpha","VarietyBeta","VarietyGamma","VarietyDelta","VarietyEpsilon")) {
    expect_true(grepl(lbl, joined, fixed = TRUE), info = sprintf("reveal_maps missed: %s", lbl))
  }
})

test_that("reveal_maps prints a warning banner before maps", {
  r <- propose_roles(iris)
  r$role[r$col == "Sepal.Length"] <- "outcome"
  r$role[r$col == "Species"]      <- "covariate"
  m <- mask(iris, r, mode = "collaborate", seed = 1)
  joined <- capture_full(reveal_maps(recipe(m)))
  expect_match(joined, "Revealing sensitive")
})

test_that("reveal_maps on an empty-maps recipe says so", {
  r <- propose_roles(iris)
  r$role[r$col == "Sepal.Length"] <- "outcome"
  m <- suppressWarnings(mask(iris, r, mode = "local", seed = 1))
  joined <- capture_full(reveal_maps(recipe(m)))
  expect_match(joined, "No level maps")
})

test_that("reveal_maps errors on non-recipe input", {
  expect_error(reveal_maps(list()), "must be a")
})

test_that("Seed is redacted in print(recipe)", {
  r <- propose_roles(iris)
  r$role[r$col == "Sepal.Length"] <- "outcome"
  m <- suppressWarnings(mask(iris, r, seed = 99999, mode = "local"))
  joined <- capture_full(print(recipe(m)))
  expect_false(grepl("99999", joined, fixed = TRUE))
  expect_match(joined, "redacted")
})

test_that("print(masque) calls through to print(recipe)", {
  r <- propose_roles(iris)
  r$role[r$col == "Sepal.Length"] <- "outcome"
  m <- suppressWarnings(mask(iris, r, mode = "local", seed = 1))
  joined <- capture_full(print(m))
  expect_match(joined, "masque")
  expect_match(joined, "Mode: local")
  expect_match(joined, "PRIVATE")
})
