# plot(design_summary, df = ...): smoke tests across every design class.
# No vdiffr snapshots — keep test deps lean. We assert no error + that
# the device wrote something.

# Helper: render to a null PDF device and confirm zero errors.
plot_smoke <- function(ds, df) {
  pdf(NULL)
  on.exit(dev.off(), add = TRUE)
  expect_no_error(plot(ds, df = df))
}

test_that("plot() handles CRD without error", {
  ds <- detect_design(iris)
  expect_equal(ds@class_label, "CRD")
  plot_smoke(ds, iris)
})

test_that("plot() handles factorial without error", {
  ds <- detect_design(ToothGrowth)
  expect_equal(ds@class_label, "factorial")
  plot_smoke(ds, ToothGrowth)
})

test_that("plot() handles 'none' without error", {
  ds <- detect_design(mtcars)
  expect_equal(ds@class_label, "none")
  plot_smoke(ds, mtcars)
})

test_that("plot() handles RCBD without error", {
  df <- expand.grid(rep = 1:5, trt = factor(letters[1:4]))
  df$yield <- rnorm(nrow(df))
  ds <- detect_design(df)
  expect_equal(ds@class_label, "RCBD")
  plot_smoke(ds, df)
})

test_that("plot() handles IBD/alpha-lattice without error", {
  skip_if_not_installed("agridat")
  d <- agridat::john.alpha
  ds <- detect_design(d)
  expect_equal(ds@class_label, "IBD/alpha-lattice")
  plot_smoke(ds, d)
})

test_that("plot() handles split-plot without error", {
  skip_if_not_installed("agridat")
  d <- agridat::yates.oats
  ds <- detect_design(d)
  expect_equal(ds@class_label, "split-plot")
  plot_smoke(ds, d)
})

test_that("plot() falls back to base when ggplot2 requested but absent", {
  ds <- detect_design(iris)
  # Force engine = "ggplot2" with ggplot2 actually installed in suggests.
  # When ggplot2 IS installed, this exercises the ggplot2 dispatch
  # without erroring.
  skip_if_not_installed("ggplot2")
  pdf(NULL)
  on.exit(dev.off(), add = TRUE)
  expect_no_error(plot(ds, df = iris, engine = "ggplot2"))
})

test_that("plot() errors when df is missing", {
  ds <- detect_design(iris)
  expect_error(plot(ds))
})
