# Hygiene layer: legal names, whitespace trim, near-duplicate reporting,
# the clean = "auto" / "report" / "off" switch, and the cleaning
# round-trip through mask() / apply_recipe().

make_dirty <- function() {
  data.frame(
    check.names = FALSE, stringsAsFactors = FALSE,
    "Site Name" = c("north ", "north", "South", "north", "South", "South"),
    "Yield (t/ha)" = c(3.1, 2.9, 5.0, 3.0, 4.8, 5.1),
    "rep" = c(1L, 2L, 1L, 2L, 1L, 2L)
  )
}

test_that("clean_table legalises column names", {
  cl <- clean_table(make_dirty(), quiet = TRUE)
  expect_equal(names(cl$data), c("Site.Name", "Yield..t.ha.", "rep"))
  expect_equal(
    unname(cl$name_map[["Site Name"]]), "Site.Name"
  )
})

test_that("clean_table trims whitespace in labels", {
  cl <- clean_table(make_dirty(), quiet = TRUE)
  expect_false(any(grepl("\\s$", as.character(cl$data$Site.Name))))
  # " north " collapses onto "north": three norths now.
  expect_equal(sum(cl$data$Site.Name == "north"), 3L)
  expect_true("Site.Name" %in% names(cl$level_fixes))
})

test_that("clean_table reports near-duplicate labels without changing them", {
  df <- data.frame(
    geno = c("Scope", "scope", "Compass", "Compas", "Scope", "Compass"),
    yield = rnorm(6),
    stringsAsFactors = FALSE
  )
  cl <- clean_table(df, quiet = TRUE)
  # "Scope"/"scope" = case; "Compass"/"Compas" = edit-distance 1.
  expect_true(nrow(cl$near_duplicates) >= 2L)
  expect_setequal(unique(cl$near_duplicates$kind), c("case", "edit1"))
  # Untouched: both spellings still present.
  expect_true(all(c("Scope", "scope") %in% cl$data$geno))
})

test_that("clean = 'report' changes nothing but still reports", {
  cl <- clean_table(make_dirty(), clean = "report", quiet = TRUE)
  expect_equal(names(cl$data), names(make_dirty()))
  expect_true(length(cl$name_map) >= 1L)
})

test_that("clean = 'off' is a pure pass-through", {
  df <- make_dirty()
  cl <- clean_table(df, clean = "off", quiet = TRUE)
  expect_identical(cl$data, df)
  expect_length(cl$name_map, 0L)
  expect_equal(nrow(cl$near_duplicates), 0L)
})

test_that("name legalisation uniquifies collisions", {
  df <- data.frame(
    check.names = FALSE,
    "a b" = 1:3, "a.b" = 4:6
  )
  cl <- clean_table(df, quiet = TRUE)
  expect_equal(length(unique(names(cl$data))), 2L)
})

test_that("mask(clean='auto') legalises names and remaps the roles table", {
  df <- make_dirty()
  r <- propose_roles(df) # roles keyed to dirty names
  r <- set_role(r, "Yield (t/ha)", role = "outcome")
  m <- suppressWarnings(mask(df, r, seed = 1))
  expect_equal(names(synthetic(m)), c("Site.Name", "Yield..t.ha.", "rep"))
  expect_false(is.null(recipe(m)@cleaning))
})

test_that("apply_recipe re-applies cleaning so retargeting lines up", {
  df <- make_dirty()
  r <- propose_roles(df)
  r <- set_role(r, "Yield (t/ha)", role = "outcome")
  m <- suppressWarnings(mask(df, r, seed = 1))
  fwd <- apply_recipe(df, recipe(m)) # df still has the dirty names
  expect_true(all(names(fwd) %in% names(synthetic(m))))
  expect_false(any(grepl("\\s$", as.character(fwd$Site.Name))))
})

test_that("mask(clean='off') preserves dirty names verbatim", {
  df <- make_dirty()
  r <- propose_roles(df)
  r <- set_role(r, "Yield (t/ha)", role = "outcome")
  m <- suppressWarnings(mask(df, r, seed = 1, clean = "off"))
  expect_true("Site Name" %in% names(synthetic(m)))
})

test_that("clean_table errors on non-data-frame", {
  expect_error(clean_table(1:5), "must be a data frame")
})
