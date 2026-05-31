# detect_design(): orchestrator + agridat fixture regression.

test_that("detect_design() rejects non-data-frame input", {
  expect_error(detect_design(1:10), "must be a data frame")
  expect_error(detect_design(list(a = 1)), "must be a data frame")
})

test_that("detect_design() rejects too-small input", {
  expect_error(detect_design(data.frame(x = 1)), "at least 2 rows")
  expect_error(detect_design(data.frame()), "at least 2 rows")
})

test_that("detect_design() returns S7 design_summary with the expected shape", {
  ds <- detect_design(iris)
  expect_true(inherits(ds, "masque::design_summary"))
  expect_true(ds@class_label %in% c(
    "CRD", "RCBD", "IBD/alpha-lattice",
    "row-column", "split-plot",
    "factorial", "none"
  ))
  expect_named(ds@scores, c(
    "CRD", "RCBD", "IBD/alpha-lattice",
    "row-column", "split-plot", "factorial"
  ))
  expect_true(is.list(ds@evidence))
  expect_s3_class(ds@recommended_roles, "data.frame")
})

test_that("detect_design() classifies iris as CRD (balanced 50/50/50)", {
  ds <- detect_design(iris)
  expect_equal(ds@class_label, "CRD")
  expect_equal(ds@treatment_col, "Species")
  expect_gte(ds@scores[["CRD"]], 0.9)
})

test_that("detect_design() classifies mtcars as none (observational)", {
  ds <- detect_design(mtcars)
  expect_equal(ds@class_label, "none")
  expect_true(all(ds@scores < 0.5))
})

test_that("detect_design() classifies ToothGrowth as factorial", {
  ds <- detect_design(ToothGrowth)
  expect_equal(ds@class_label, "factorial")
  expect_setequal(ds@treatment_col, c("supp", "dose"))
})

test_that("detect_design() respects user roles for treatment override", {
  d <- iris
  roles <- propose_roles(d, detect = FALSE)
  # Force a different treatment than detection would pick.
  roles$role[roles$col == "Sepal.Width"] <- "treatment"
  ds <- detect_design(d, roles = roles)
  expect_true("Sepal.Width" %in% ds@candidates$trt_user)
})

# --- agridat fixture regression -----------------------------------------

test_that("detect_design() on agridat::john.alpha -> IBD/alpha-lattice", {
  skip_if_not_installed("agridat")
  ds <- detect_design(agridat::john.alpha)
  expect_equal(ds@class_label, "IBD/alpha-lattice")
  expect_equal(ds@treatment_col, "gen")
  expect_setequal(ds@block_cols, c("rep", "block"))
})

test_that("detect_design() on agridat::cochran.crd -> CRD", {
  skip_if_not_installed("agridat")
  ds <- detect_design(agridat::cochran.crd)
  expect_equal(ds@class_label, "CRD")
  expect_equal(ds@treatment_col, "trt")
})

test_that("detect_design() on agridat::yates.oats -> split-plot", {
  skip_if_not_installed("agridat")
  ds <- detect_design(agridat::yates.oats)
  expect_equal(ds@class_label, "split-plot")
  expect_true(length(ds@whole_plot_col) == 1L)
  expect_true(length(ds@sub_plot_col) == 1L)
})

test_that("detect_design() on agridat::beall.webworms -> RCBD (simpler wins)", {
  skip_if_not_installed("agridat")
  ds <- detect_design(agridat::beall.webworms)
  expect_equal(ds@class_label, "RCBD")
})

test_that("detect_design() on agridat::archbold.apple -> split-plot", {
  skip_if_not_installed("agridat")
  ds <- detect_design(agridat::archbold.apple)
  expect_equal(ds@class_label, "split-plot")
})

# --- print() output -----------------------------------------------------

test_that("print(design_summary) renders without error and includes label", {
  ds <- detect_design(iris)
  out <- capture_full(print(ds))
  expect_true(nchar(out) > 0L)
  expect_match(out, "CRD")
  expect_match(out, "Species")
})

test_that("print(design_summary) for 'none' indicates no design detected", {
  ds <- detect_design(mtcars)
  out <- capture_full(print(ds))
  expect_match(out, "none")
  expect_match(out, "No experimental design", fixed = TRUE)
})
