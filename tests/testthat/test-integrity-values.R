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

test_that("a column's type on the way back from a file does not change the match", {
  d <- data.frame(
    empty = rep(NA_real_, 12L), lab = factor(1:12), whole = 3e9 + 1:12,
    flag = rep(c(TRUE, FALSE), 6L), txt = as.character(1:12)
  )
  fp <- masque:::.content_fingerprint(d)
  back <- data.frame(
    empty = rep(NA, 12L), lab = 1:12, whole = as.character(3e9 + 1:12),
    flag = rep(c(1L, 0L), 6L), txt = 1:12
  )
  expect_true(masque:::.content_matches(fp, masque:::.content_fingerprint(back)))
  back$lab[1L] <- 99L
  expect_false(masque:::.content_matches(fp, masque:::.content_fingerprint(back)))
})

test_that("neither a large value nor a large table hides a change", {
  set.seed(9)
  n <- 1000L
  y <- c(1e10, stats::rnorm(n - 1L))
  fp <- masque:::.content_fingerprint(data.frame(y = y))
  y2 <- c(y[1L], rev(y[-1L]))
  expect_false(masque:::.content_matches(fp, masque:::.content_fingerprint(data.frame(y = y2))))
  path <- withr::local_tempfile(fileext = ".csv")
  data.table::fwrite(data.frame(y = y), path)
  expect_true(masque:::.content_matches(fp, masque:::.content_fingerprint(data.table::fread(path))))
  big <- stats::rnorm(1e5, 5000, 1000)
  fp2 <- masque:::.content_fingerprint(data.frame(y = big))
  big[17L] <- big[17L] + 50
  expect_false(masque:::.content_matches(fp2, masque:::.content_fingerprint(data.frame(y = big))))
})

test_that("each sum has its own tolerance", {
  entry <- function(value = 100, log_value = 10) {
    list(sums = list(y = list(
      value = value, scale = 1e6, log_value = log_value, log_scale = 1e3, other = "x"
    )), text = "t")
  }
  expect_true(masque:::.content_matches(entry(), entry(100 + 1e-9, 10 + 1e-12)))
  expect_false(masque:::.content_matches(entry(), entry(value = 100 + 1e-7)))
  expect_false(masque:::.content_matches(entry(), entry(log_value = 10 + 1e-10)))
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
  skip_if_not_installed("yaml")
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

test_that("the value fingerprint does not depend on how text is held in memory", {
  path <- tempfile(fileext = ".csv")
  writeLines(c("site,yield", "a,1", "b,2", "c,3"), path)
  read <- data.table::fread(path)
  expect_identical(.content_fingerprint(read), .content_fingerprint(data.table::copy(read)))
})
