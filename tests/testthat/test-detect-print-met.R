# MET print contract: scope first, pooled verdict clearly labelled, and bounded
# aggregation regardless of the number of environments.

.capture_design_print <- function(x) {
  capture.output(print(x), type = "message")
}

test_that("detected MET print is bounded across public fixtures", {
  skip_if_not_installed("agridat")
  fixtures <- list(
    besag = agridat::besag.met,
    australia = agridat::australia.soybean,
    adugna = agridat::adugna.sorghum,
    gauch = agridat::gauch.soy
  )

  for (nm in names(fixtures)) {
    output <- .capture_design_print(detect_design(fixtures[[nm]]))
    expect_true(length(output) <= 40L, info = nm)
    expect_match(output[1L], "multi_environment", info = nm)
    expect_true(any(grepl("Pooled legacy verdict", output)), info = nm)
    expect_true(any(grepl("Within-environment advisory", output)), info = nm)
    expect_false(any(grepl("^\\s*E[0-9]+", output)), info = nm)
  }
})

test_that("MET print separates grouping, connectivity and recommendations", {
  skip_if_not_installed("agridat")
  output <- .capture_design_print(detect_design(agridat::adugna.sorghum))

  expect_true(any(grepl("experiment groups: trial", output)))
  expect_true(any(grepl("Connectivity: connected", output)))
  expect_true(any(grepl("local=keep; collaborate=alias", output)))
})

test_that("uncertain scope leads the print output", {
  skip_if_not_installed("agridat")
  output <- .capture_design_print(
    detect_design(agridat::onofri.winterwheat)
  )

  expect_match(output[1L], "uncertain")
  expect_true(any(grepl("review required", output, ignore.case = TRUE)))
  expect_false(any(grepl("single trial", output, ignore.case = TRUE)))
})
