# The recipe binds the table's values as well as its NA mask.

integrity_fixture <- function() {
  set.seed(8)
  d <- data.frame(
    gen = rep(paste0("G", 1:6), 6L),
    rep = rep(paste0("R", 1:6), each = 6L),
    y = stats::rnorm(36L, 5, 2),
    stringsAsFactors = FALSE
  )
  r <- suppressWarnings(propose_roles(d, detect = FALSE))
  r <- set_role(r, "rep", role = "design", action = "keep")
  r <- set_role(r, "gen", role = "treatment", action = "keep")
  r <- set_role(r, "y", role = "outcome", action = "scramble")
  spec <- control_spec(on = "gen", strata = "rep", n = 2L, seed = 5L)
  m <- mask(d, masque_plan(r, controls = spec), seed = 1L, quiet = TRUE)
  list(d = d, m = m, plan = clone_plan(m), rec = recipe(m))
}

test_that("a table with other values and the same holes is refused", {
  f <- integrity_fixture()
  swapped <- f$d
  swapped$y <- rev(swapped$y)
  expect_error(controls(swapped, f$plan, recipe = f$rec), class = "masque_integrity_refusal")
  expect_error(apply_recipe(swapped, f$rec), class = "masque_integrity_refusal")
  labels <- f$d
  labels$gen[1:2] <- labels$gen[2:1]
  expect_error(controls(labels, f$plan, recipe = f$rec), class = "masque_integrity_refusal")
  one <- f$d
  one$y[20L] <- one$y[20L] + 1e-3
  expect_error(controls(one, f$plan, recipe = f$rec), class = "masque_integrity_refusal")
  expect_no_error(apply_recipe(swapped, f$rec, check_integrity = FALSE))
})

test_that("the table itself passes, through every route it can come back by", {
  f <- integrity_fixture()
  expect_no_error(controls(f$d, f$plan, recipe = f$rec))
  expect_no_error(controls(data.table::as.data.table(f$d), f$plan, recipe = f$rec))
  as_factor <- f$d
  as_factor$gen <- factor(as_factor$gen)
  expect_no_error(controls(as_factor, f$plan, recipe = f$rec))
  path <- withr::local_tempfile(fileext = ".csv")
  utils::write.csv(f$d, path, row.names = FALSE)
  expect_no_error(controls(utils::read.csv(path), f$plan, recipe = f$rec))
  data.table::fwrite(f$d, path)
  expect_no_error(controls(data.table::fread(path), f$plan, recipe = f$rec))
})

test_that("non-finite values and whole numbers read back as doubles match", {
  d <- data.frame(a = c(1L, 2L, NA, 4L), b = c(1.5, Inf, -Inf, 2), s = as.Date("2026-01-01") + 0:3)
  fp <- masque:::.content_fingerprint(d)
  back <- d
  back$a <- as.double(back$a)
  back$s <- as.character(back$s)
  expect_true(masque:::.content_matches(fp, masque:::.content_fingerprint(back)))
  moved <- d
  moved$b <- d$b[c(1L, 3L, 2L, 4L)]
  expect_false(masque:::.content_matches(fp, masque:::.content_fingerprint(moved)))
})

test_that("a recipe without the value fingerprint still applies", {
  f <- integrity_fixture()
  rec <- f$rec
  rec@content_fp <- list()
  swapped <- f$d
  swapped$y <- rev(swapped$y)
  expect_no_error(apply_recipe(swapped, rec))
})

test_that("the fingerprint stays with the owner", {
  f <- integrity_fixture()
  r <- set_role(roles(f$m), "gen", role = "treatment", action = "alias")
  m <- mask(f$d, masque_plan(r, controls = control_spec(on = "gen", strata = "rep", n = 2L, seed = 5L)),
            mode = "collaborate", seed = 1L, quiet = TRUE)
  f$rec <- recipe(m)
  expect_gt(length(f$rec@content_fp$sums), 0L)
  out <- file.path(withr::local_tempdir(), "pack")
  handover(m, out)
  shipped <- unlist(lapply(list.files(out, full.names = TRUE), readLines))
  value <- format(f$rec@content_fp$sums$y$value, digits = 8L)
  expect_false(any(grepl(value, shipped, fixed = TRUE)))
  expect_false(any(grepl(f$rec@content_fp$text, shipped, fixed = TRUE)))
})
