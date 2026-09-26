# Allocation and NA pattern must come back byte-identical, model terms within
# the pass rule in helper-design-preservation.R. 3 seeds on CRAN, 20 off.

design_seeds <- function() {
  if (identical(Sys.getenv("NOT_CRAN"), "true")) 1:20 else 1:3
}

test_that("every design class passes the preservation rule", {
  skip_if_not_installed("agridat")
  specs <- design_specs()
  seeds <- design_seeds()
  for (nm in names(specs)) {
    res <- design_run(specs[[nm]], seeds)
    verdict <- design_verdict(specs[[nm]], res)
    expect_true(all(verdict), info = sprintf(
      "%s: %s", nm, paste(names(verdict)[!verdict], collapse = ", ")
    ))
  }
})

test_that("the blocked MET keeps its environment and replicate effects", {
  skip_if_not_installed("agridat")
  res <- design_run(design_specs()$MET, design_seeds())
  expect_identical(res$used, "gen")
  expect_match(res$shifted, "county")
  expect_match(res$shifted, "rep:county|county:rep")
  expect_gt(res$F_clone[["county"]], 0.7 * res$F_orig[["county"]])
  expect_gt(res$F_clone[["county:rep"]], 0.5 * res$F_orig[["county:rep"]])
  expect_gt(res$trt_corr[["gen"]], 0.8)
})

test_that("the split-plot keeps its block effect and nitrogen response", {
  skip_if_not_installed("agridat")
  res <- design_run(design_specs()$`split-plot`, design_seeds())
  expect_identical(res$used, "gen x nitro")
  expect_gt(res$F_clone[["block"]], 0.5 * res$F_orig[["block"]])
  expect_gt(res$F_clone[["nitro"]], 0.5 * res$F_orig[["nitro"]])
  expect_gt(res$trt_corr[["nitro"]], 0.9)
})

test_that("the levels ladder loses what the hierarchy ladder keeps", {
  skip_if_not_installed("agridat")
  seeds <- design_seeds()
  met <- design_run(design_specs()$MET, seeds, ladder = "levels")
  expect_lt(met$F_clone[["county"]], 0.05 * met$F_orig[["county"]])
  oats <- design_run(design_specs()$`split-plot`, seeds, ladder = "levels")
  expect_lt(oats$F_clone[["block"]], 0.2 * oats$F_orig[["block"]])
})
