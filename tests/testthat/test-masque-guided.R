# The guided masque() verb. Tests cover the non-interactive / scripted
# paths only (interactive review is exercised by hand).

test_that("masque() on a data frame with supplied roles masks it", {
  r <- propose_roles(iris)
  r <- set_role(r, "Sepal.Length", role = "outcome")
  m <- masque(iris, roles = r, seed = 1, ask = FALSE, quiet = TRUE)
  expect_true(S7::S7_inherits(m, masque_obj))
  expect_equal(ncol(synthetic(m)), ncol(iris))
})

test_that("masque() auto-proposes roles when none supplied (ask = FALSE)", {
  m <- masque(iris, seed = 1, ask = FALSE, quiet = TRUE)
  expect_true(S7::S7_inherits(m, masque_obj))
  expect_equal(nrow(synthetic(m)), nrow(iris))
})

test_that("masque() dispatches a named list to the set path", {
  tabs <- list(
    a = data.frame(gen = rep(c("x", "y"), 3), v = rnorm(6),
      stringsAsFactors = FALSE),
    b = data.frame(gen = c("x", "y"), w = c(1, 2), stringsAsFactors = FALSE)
  )
  m <- masque(tabs, mode = "collaborate", seed = 1, ask = FALSE, quiet = TRUE)
  expect_true(S7::S7_inherits(m, masque_set))
  expect_equal(length(synthetic(m)), 2L)
})

test_that("masque() reads a single CSV file", {
  d <- withr::local_tempdir()
  csv <- file.path(d, "data.csv")
  utils::write.csv(iris, csv, row.names = FALSE)
  m <- masque(csv, seed = 1, ask = FALSE, quiet = TRUE)
  expect_true(S7::S7_inherits(m, masque_obj))
  expect_equal(nrow(synthetic(m)), nrow(iris))
})

test_that("masque() reads a folder as a set", {
  d <- withr::local_tempdir()
  utils::write.csv(
    data.frame(gen = rep(c("x", "y"), 3), v = rnorm(6)),
    file.path(d, "t1.csv"), row.names = FALSE
  )
  utils::write.csv(
    data.frame(gen = c("x", "y"), w = c(1, 2)),
    file.path(d, "t2.csv"), row.names = FALSE
  )
  m <- masque(d, seed = 1, ask = FALSE, quiet = TRUE)
  expect_true(S7::S7_inherits(m, masque_set))
  expect_setequal(names(synthetic(m)), c("t1", "t2"))
})

test_that("masque() writes single-table output to a CSV", {
  d <- withr::local_tempdir()
  out <- file.path(d, "masked.csv")
  r <- propose_roles(iris)
  r <- set_role(r, "Sepal.Length", role = "outcome")
  masque(iris, roles = r, seed = 1, out = out, ask = FALSE, quiet = TRUE)
  expect_true(file.exists(out))
  back <- as.data.frame(data.table::fread(out))
  expect_equal(nrow(back), nrow(iris))
})

test_that("masque() writes a set to a folder", {
  tabs <- list(
    a = data.frame(gen = rep(c("x", "y"), 3), v = rnorm(6)),
    b = data.frame(gen = c("x", "y"), w = c(1, 2))
  )
  d <- withr::local_tempdir()
  out <- file.path(d, "masked_set")
  masque(tabs, mode = "collaborate", seed = 1, out = out,
    ask = FALSE, quiet = TRUE
  )
  expect_setequal(list.files(out), c("a.csv", "b.csv"))
})

test_that("masque() errors on an unreadable input path", {
  expect_error(masque("/no/such/path", ask = FALSE, quiet = TRUE), "No file")
})

test_that("masque() result round-trips like the lower-level verbs", {
  tabs <- list(
    trials = data.frame(
      gen = rep(c("Scope", "Compass"), 3), y = rnorm(6),
      stringsAsFactors = FALSE
    ),
    ped = data.frame(
      gen = c("Scope", "Compass"), m = c("e", "l"),
      stringsAsFactors = FALSE
    )
  )
  m <- masque(tabs, mode = "collaborate", seed = 1, ask = FALSE, quiet = TRUE)
  back <- unmask(synthetic(m), recipe(m))
  expect_equal(as.character(back$trials$gen), tabs$trials$gen)
})
