# Column-name aliasing: the alias_names depth control on mask().

basic <- function(df = iris) {
  r <- propose_roles(df, detect = FALSE)
  set_role(r, "Sepal.Length", role = "outcome")
}

test_that("alias_names = FALSE keeps column names (default)", {
  m <- suppressWarnings(mask(iris, basic(), seed = 1))
  expect_equal(names(synthetic(m)), names(iris))
  expect_null(recipe(m)@column_name_map)
})

test_that("alias_names = TRUE replaces all column names with aliases", {
  m <- suppressWarnings(mask(iris, basic(), seed = 1, alias_names = TRUE))
  expect_equal(
    names(synthetic(m)),
    sprintf("col_%03d", seq_len(ncol(iris)))
  )
  expect_false(any(names(iris) %in% names(synthetic(m))))
})

test_that("alias_names round-trips through apply_recipe + unmask", {
  m <- suppressWarnings(mask(iris, basic(), seed = 1, alias_names = TRUE))
  rec <- recipe(m)
  fwd <- apply_recipe(iris, rec)
  expect_equal(names(fwd), names(synthetic(m)))
  back <- unmask(fwd, rec)
  expect_setequal(names(back), names(iris))
})

test_that("alias_names accepts a character vector for partial aliasing", {
  m <- suppressWarnings(
    mask(iris, basic(), seed = 1, alias_names = c("Species"))
  )
  s <- synthetic(m)
  expect_false("Species" %in% names(s))
  expect_true(all(
    c("Sepal.Length", "Sepal.Width", "Petal.Length", "Petal.Width") %in%
      names(s)
  ))
  back <- unmask(apply_recipe(iris, recipe(m)), recipe(m))
  expect_setequal(names(back), names(iris))
})

test_that("alias_names errors on a dropped or unknown column", {
  df <- data.frame(
    id = 1:6, gen = factor(rep(c("a", "b"), 3)), yield = rnorm(6)
  )
  r <- propose_roles(df, mode = "collaborate", detect = FALSE)
  r <- set_role(r, "yield", role = "outcome")
  r <- set_role(r, "id", action = "drop")
  expect_error(
    suppressWarnings(
      mask(df, r, mode = "collaborate", seed = 1, alias_names = c("id"))
    ),
    "not in the synthetic"
  )
  expect_error(
    suppressWarnings(mask(df, r, seed = 1, alias_names = 1L)),
    "must be a single logical"
  )
})

test_that("aliased column names work alongside level aliasing", {
  df <- data.frame(
    gen = factor(rep(c("alpha", "bravo", "charlie"), 4)),
    yield = rnorm(12),
    stringsAsFactors = FALSE
  )
  r <- propose_roles(df, mode = "collaborate", detect = FALSE)
  r <- set_role(r, "yield", role = "outcome")
  r <- set_role(r, "gen", role = "treatment")
  m <- suppressWarnings(
    mask(df, r, mode = "collaborate", seed = 1, alias_names = TRUE)
  )
  s <- synthetic(m)
  # Both the column name and the factor labels are opaque.
  expect_true(all(grepl("^col_", names(s))))
  gen_alias_col <- names(recipe(m)@column_name_map)[
    match("gen", names(recipe(m)@column_name_map))
  ]
  expect_false(any(c("alpha", "bravo", "charlie") %in%
    as.character(s[[unname(unlist(recipe(m)@column_name_map[["gen"]]))]])))
  back <- unmask(apply_recipe(df, recipe(m)), recipe(m))
  expect_equal(as.character(back$gen), as.character(df$gen))
})

test_that("reveal_maps shows the column-name map", {
  m <- suppressWarnings(mask(iris, basic(), seed = 1, alias_names = TRUE))
  out <- capture_full(reveal_maps(recipe(m)))
  expect_match(out, "Sepal.Length")
  expect_match(out, "col_001")
})
