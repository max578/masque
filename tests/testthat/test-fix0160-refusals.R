# F19 and F22: refusals with a complete message and a proper class.

.refusal_roles <- function() {
  r <- propose_roles(iris)
  set_role(r, "Sepal.Length", role = "outcome")
}

test_that("recipe() and synthetic() refuse a non-masque with a full message", {
  for (accessor in list(recipe, synthetic)) {
    err <- expect_error(accessor(iris), class = "orchestra_refusal")
    expect_identical(
      class(err)[1:2],
      c("masque_bad_masque_obj_refusal", "orchestra_refusal")
    )
    expect_false(any(grepl("{", class(err), fixed = TRUE)))
    expect_match(conditionMessage(err), "got <data.frame>", fixed = TRUE)
  }
})

test_that("save_recipe() refuses a path that is not .rds and writes nothing", {
  rec <- recipe(mask(iris, .refusal_roles(), mode = "local", seed = 1L))
  for (ext in c(".csv", ".xlsx", ".rds.bak", "")) {
    path <- file.path(tempdir(), paste0("masque-recipe-ext", ext))
    unlink(path)
    expect_error(
      save_recipe(rec, path),
      class = "masque_bad_recipe_path_refusal"
    )
    expect_false(file.exists(path))
  }
  upper <- withr::local_tempfile(fileext = ".RDS")
  expect_identical(save_recipe(rec, upper), upper)
  expect_true(S7::S7_inherits(read_recipe(upper), masque:::masque_recipe))
})

test_that("a seed that is not a whole finite integer is refused", {
  r <- .refusal_roles()
  for (bad in list(1.5, Inf, -Inf, NaN, 2^31, -0.25)) {
    expect_error(
      mask(iris, r, mode = "local", seed = bad),
      class = "masque_bad_seed_refusal"
    )
  }
  expect_error(
    mask(iris, r, mode = "local", seed = "1"),
    class = "masque_bad_seed_refusal"
  )
  # A whole double is the same seed as the integer.
  expect_identical(
    synthetic(mask(iris, r, mode = "local", seed = 7)),
    synthetic(mask(iris, r, mode = "local", seed = 7L))
  )
})

test_that("mask_set() and masque() route a bad seed to the same refusal", {
  tables <- list(
    a = data.frame(site = rep(c("s1", "s2"), 5L), y = seq_len(10L) / 3),
    b = data.frame(site = c("s1", "s2"), z = c(1.5, 2.5))
  )
  expect_error(
    mask_set(tables, mode = "local", seed = 1.5, quiet = TRUE),
    class = "masque_bad_seed_refusal"
  )
  expect_error(
    masque(iris, roles = .refusal_roles(), mode = "local", seed = 1.5,
      ask = FALSE, quiet = TRUE
    ),
    class = "masque_bad_seed_refusal"
  )
})
