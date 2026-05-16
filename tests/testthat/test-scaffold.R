test_that("scaffold: package can be loaded", {
  expect_true(requireNamespace("masque", quietly = TRUE))
})

test_that("scaffold: DESCRIPTION declares MIT licence", {
  desc <- read.dcf(system.file("DESCRIPTION", package = "masque"))
  expect_match(unname(desc[1, "License"]), "MIT", fixed = TRUE)
})
