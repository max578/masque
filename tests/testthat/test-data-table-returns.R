test_that("every exported table comes back as a data.table", {
  roles <- propose_roles(iris)
  m <- mask(iris, roles, seed = 1L)

  expect_s3_class(roles, "data.table")
  expect_s3_class(role_options(), "data.table")
  expect_s3_class(synthetic(m), "data.table")
  expect_s3_class(audit_mask(m, original = iris, print = FALSE), "data.table")
  expect_s3_class(apply_recipe(iris, recipe(m)), "data.table")
  expect_s3_class(unmask(synthetic(m), recipe(m)), "data.table")

  ds <- detect_design(iris)
  expect_s3_class(ds@recommended_roles, "data.table")
  expect_s3_class(ds@per_env, "data.table")

  cl <- clean_table(iris, quiet = TRUE)
  expect_s3_class(cl$data, "data.table")
  expect_s3_class(cl$near_duplicates, "data.table")

  ct <- conform_table(iris, quiet = TRUE)
  expect_s3_class(ct$data, "data.table")
  expect_s3_class(ct$merges, "data.table")
  expect_s3_class(ct$types, "data.table")
})

test_that("read_set returns data.tables", {
  dir <- withr::local_tempdir()
  utils::write.csv(iris, file.path(dir, "a.csv"), row.names = FALSE)
  utils::write.csv(mtcars, file.path(dir, "b.csv"), row.names = FALSE)
  tables <- read_set(dir)
  expect_true(all(vapply(tables, data.table::is.data.table, logical(1L))))
})

test_that("roles keep their mode through a column edit", {
  roles <- propose_roles(iris, mode = "collaborate")
  roles[roles$col == "Species", "role"] <- "covariate"
  expect_identical(attr(roles, "mode"), "collaborate")
})

test_that("editing an extracted table by reference leaves the masque intact", {
  m <- mask(iris, propose_roles(iris, mode = "collaborate"), seed = 1L)
  s <- synthetic(m)
  data.table::set(s, j = "extra", value = 1)
  expect_false("extra" %in% names(synthetic(m)))
  a <- audit_mask(m, print = FALSE)
  data.table::set(a, j = "extra", value = 1)
  expect_false("extra" %in% names(audit_mask(m, print = FALSE)))
})

test_that("a := edit on a returned table never reaches the input", {
  roles <- propose_roles(iris)
  r2 <- set_role(roles, "Species", action = "drop")
  data.table::set(r2, i = 1L, j = "role", value = "outcome")
  expect_false(identical(roles$role[1L], "outcome"))

  dt <- data.table::as.data.table(iris)
  m <- mask(dt, propose_roles(dt), seed = 1L)
  out <- apply_recipe(dt, recipe(m))
  data.table::set(out, i = 1L, j = 1L, value = -1)
  expect_false(dt[[1L]][1L] == -1)

  cl <- clean_table(dt, clean = "off", quiet = TRUE)
  data.table::set(cl$data, i = 1L, j = 1L, value = -1)
  expect_false(dt[[1L]][1L] == -1)
})
