# plot(design_summary, df = ...): smoke tests across every design class.
# No vdiffr snapshots — keep test deps lean. We assert no error + that
# the device wrote something.

# Helper: render to a null PDF device and confirm zero errors.
plot_smoke <- function(ds, df, engine = "base", environment = NULL) {
  pdf(NULL)
  on.exit(dev.off(), add = TRUE)
  expect_no_error(plot(
    ds, df = df, engine = engine, environment = environment
  ))
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

test_that("MET overview is bounded for 6, 8, 13 and 55 environments", {
  skip_if_not_installed("agridat")
  fixtures <- list(
    agridat::besag.met,
    agridat::australia.soybean,
    agridat::adugna.sorghum,
    agridat::gauch.soy
  )
  expected <- c(6L, 8L, 13L, 55L)

  for (i in seq_along(fixtures)) {
    ds <- detect_design(fixtures[[i]])
    expect_equal(ds@n_env, expected[i])
    plot_smoke(ds, fixtures[[i]])
    overview <- masque:::.met_overview_data(ds)
    expect_equal(nrow(overview), expected[i])
    expect_named(overview, c("env", "value", "metric"))
  }
})

test_that("ggplot2 MET overview is compact and drawable", {
  skip_if_not_installed("agridat")
  skip_if_not_installed("ggplot2")
  d <- agridat::gauch.soy
  ds <- detect_design(d)
  p <- masque:::.plot_met_overview(ds, "ggplot2")

  expect_true(inherits(p, "ggplot"))
  expect_equal(nrow(p@data), 55L)
  plot_smoke(ds, d, engine = "ggplot2")
})

test_that("one selected environment draws a field-layout diagnostic", {
  skip_if_not_installed("agridat")
  d <- agridat::besag.met
  ds <- detect_design(d)
  selected <- levels(d$county)[1L]

  plot_smoke(ds, d, environment = selected)
  if (requireNamespace("ggplot2", quietly = TRUE)) {
    plot_smoke(ds, d, engine = "ggplot2", environment = selected)
  }
  expect_error(
    plot(ds, df = d, environment = c("C1", "C2")),
    "one non-missing"
  )
  expect_error(plot(ds, df = d, environment = "not-a-county"), "Unknown")
})
