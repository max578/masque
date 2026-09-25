# A `print` binding in the namespace captures the S3 print methods'
# registration; the installed package then prints the raw list.

test_that("no external generic is bound in the namespace", {
  ns <- asNamespace("masque")
  for (gen in c("print", "format", "plot")) {
    expect_false(exists(gen, envir = ns, inherits = FALSE), info = gen)
  }
})

test_that("print methods for the cleaning and conformance records resolve", {
  expect_false(is.null(
    getS3method("print", "masque_cleaning", optional = TRUE)
  ))
  expect_false(is.null(
    getS3method("print", "masque_conformance", optional = TRUE)
  ))
  cf <- conform_table(data.frame(s = c("a", "b", "a", "b", "c")), quiet = TRUE)
  raw <- capture.output(print(cf), type = "output")
  expect_false(any(grepl("attr(,\"class\")", raw, fixed = TRUE)))
})

test_that("print methods dispatch from an installed copy of the package", {
  skip_on_cran()
  skip_if_not_installed("callr")
  # Under R CMD check there is no source tree; the checked copy is installed.
  pkg <- normalizePath(testthat::test_path("..", ".."))
  from_source <- file.exists(file.path(pkg, "DESCRIPTION"))
  lib <- withr::local_tempdir()
  res <- callr::r(
    function(pkg, lib, from_source) {
      if (from_source) {
        install.packages(
          pkg, lib = lib, repos = NULL, type = "source",
          INSTALL_opts = c("--no-docs", "--no-multiarch", "--no-test-load"),
          quiet = TRUE
        )
        library(masque, lib.loc = lib)
      } else {
        library(masque)
      }
      cf <- conform_table(
        data.frame(s = c("a", "b", "a", "b", "c")), quiet = TRUE
      )
      cl <- clean_table(data.frame(`a b` = 1:3, check.names = FALSE),
        quiet = TRUE
      )
      out <- c(
        capture.output(print(cf), type = "output"),
        capture.output(print(cl), type = "output")
      )
      list(
        conformance = !is.null(
          getS3method("print", "masque_conformance", optional = TRUE)
        ),
        cleaning = !is.null(
          getS3method("print", "masque_cleaning", optional = TRUE)
        ),
        raw_list = any(grepl("attr(,\"class\")", out, fixed = TRUE)),
        recipe_lines = length(capture.output(
          print(recipe(mask(iris, propose_roles(iris), seed = 1L))),
          type = "message"
        ))
      )
    },
    args = list(pkg = pkg, lib = lib, from_source = from_source)
  )
  expect_true(res$conformance)
  expect_true(res$cleaning)
  expect_false(res$raw_list)
  expect_gt(res$recipe_lines, 0L)
})
