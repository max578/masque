# F22: the numeric-environment disclosure warning and the numeric design
# alias refusal both name the remedy.

test_that("the numeric-environment warning names factor, alias and drop", {
  d <- met_site_year_fixture()
  cnd <- expect_warning(
    propose_roles(d, mode = "collaborate"),
    class = "masque_environment_disclosure"
  )
  msg <- conditionMessage(cnd)
  expect_match(msg, "year")
  expect_match(msg, "convert")
  expect_match(msg, "factor")
  expect_match(msg, "propose_roles")
  expect_match(msg, "alias")
  expect_match(msg, "drop")
})

test_that("following the remedy removes the warning and aliases the year", {
  d <- met_site_year_fixture()
  d$year <- factor(d$year)
  expect_no_warning(r <- propose_roles(d, mode = "collaborate"))
  expect_equal(r$role[r$col == "year"], "design")
  expect_equal(r$action[r$col == "year"], "alias")
})

test_that("aliasing a numeric design column is refused with the remedy", {
  d <- met_site_year_fixture()
  r <- suppressWarnings(propose_roles(d, mode = "collaborate"))
  r$action[r$col == "year"] <- "alias"
  err <- expect_error(roles_validate(r, d), "year")
  msg <- conditionMessage(err)
  # The old refusal already said "factor" and "dropped"; the remedy is new.
  expect_match(msg, "convert")
  expect_match(msg, "factor")
  expect_match(msg, "propose_roles")
  expect_match(msg, "alias")
  expect_match(msg, "drop")
})
