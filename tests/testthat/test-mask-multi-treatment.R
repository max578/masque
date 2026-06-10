# Joint-treatment masking: factorial / split-plot designs carry two or more
# treatment factors. Each is masked independently; in collaborate mode the
# column name is folded into the alias prefix (`<col>_trt_NNN`) so the opaque
# labels stay distinct, while a single treatment keeps the historical
# `trt_NNN` prefix.

make_factorial_fixture <- function(reps = 6, seed = 0) {
  set.seed(seed)
  cells <- expand.grid(
    variety = factor(c("alpha", "bravo", "charlie")),
    nitrogen = factor(c("lo", "hi")),
    stringsAsFactors = FALSE
  )
  grid <- cells[rep(seq_len(nrow(cells)), times = reps), , drop = FALSE]
  n <- nrow(grid)
  df <- data.frame(
    block = rep(seq_len(reps), each = nrow(cells)),
    variety = grid$variety,
    nitrogen = grid$nitrogen,
    yield = rnorm(n, mean = 10, sd = 2),
    cov_n = rnorm(n),
    stringsAsFactors = FALSE
  )
  r <- propose_roles(df)
  r$role[r$col == "yield"] <- "outcome"
  r$role[r$col == "variety"] <- "treatment"
  r$role[r$col == "nitrogen"] <- "treatment"
  list(df = df, roles = r)
}

test_that("two treatment factors validate and mask without error", {
  f <- make_factorial_fixture()
  expect_invisible(roles_validate(f$roles, f$df))
  expect_no_error(m <- mask(f$df, f$roles, mode = "collaborate", seed = 1))
  expect_true(inherits(m, "masque::masque"))
})

test_that("each treatment factor is aliased with its own column prefix", {
  f <- make_factorial_fixture()
  m <- mask(f$df, f$roles, mode = "collaborate", seed = 1)
  s <- synthetic(m)

  expect_true(all(grepl("^variety_trt_\\d{3}$", levels(s$variety))))
  expect_true(all(grepl("^nitrogen_trt_\\d{3}$", levels(s$nitrogen))))
  # No original label leaks into either synthetic treatment column.
  expect_false(any(as.character(s$variety) %in% c("alpha", "bravo", "charlie")))
  expect_false(any(as.character(s$nitrogen) %in% c("lo", "hi")))

  # Recipe holds one level map per treatment column.
  rec <- recipe(m)
  expect_true(all(c("variety", "nitrogen") %in% names(rec@level_maps)))
  expect_setequal(names(rec@level_maps$variety), c("alpha", "bravo", "charlie"))
  expect_setequal(names(rec@level_maps$nitrogen), c("lo", "hi"))
})

test_that("per-level frequencies survive joint aliasing", {
  f <- make_factorial_fixture()
  m <- mask(f$df, f$roles, mode = "collaborate", seed = 1)
  s <- synthetic(m)
  expect_equal(
    sort(as.vector(table(s$variety))),
    sort(as.vector(table(f$df$variety)))
  )
  expect_equal(
    sort(as.vector(table(s$nitrogen))),
    sort(as.vector(table(f$df$nitrogen)))
  )
})

test_that("a single treatment keeps the historical trt_ prefix", {
  # Same fixture, but demote nitrogen to covariate: exactly one treatment
  # must fall back to the byte-stable `trt_NNN` form.
  f <- make_factorial_fixture()
  f$roles$role[f$roles$col == "nitrogen"] <- "covariate"
  m <- mask(f$df, f$roles, mode = "collaborate", seed = 1)
  s <- synthetic(m)
  expect_true(all(grepl("^trt_\\d{3}$", levels(s$variety))))
  expect_false(any(grepl("variety_trt_", levels(s$variety))))
})

test_that("local mode permutes each treatment factor independently", {
  f <- make_factorial_fixture()
  r <- set_role(f$roles, c("variety", "nitrogen"), action = "scramble")

  m <- suppressWarnings(mask(f$df, r, mode = "local", seed = 1))
  rec <- recipe(m)
  s <- synthetic(m)

  # Permutation keeps each vocabulary (shuffled assignment, same labels).
  expect_setequal(
    unname(rec@level_maps$variety),
    c("alpha", "bravo", "charlie")
  )
  expect_setequal(unname(rec@level_maps$nitrogen), c("lo", "hi"))
  expect_setequal(levels(s$variety), c("alpha", "bravo", "charlie"))
  expect_setequal(levels(s$nitrogen), c("lo", "hi"))
})

test_that("round-trip restores every treatment factor exactly", {
  f <- make_factorial_fixture()
  m <- mask(f$df, f$roles, mode = "collaborate", seed = 1)
  rec <- recipe(m)
  s <- synthetic(m)

  # A model trained in the synthetic namespace applies to the original
  # after both treatment factors are renamed into that namespace.
  fit <- stats::lm(yield ~ variety + nitrogen + cov_n, data = s)
  df_in_synth <- apply_recipe(f$df, rec)
  preds <- stats::predict(fit, newdata = df_in_synth)
  expect_equal(length(preds), nrow(f$df))
  expect_false(any(is.na(preds)))

  # unmask() restores both factors to their original vocabularies.
  back <- unmask(df_in_synth, rec)
  expect_equal(as.character(back$variety), as.character(f$df$variety))
  expect_equal(as.character(back$nitrogen), as.character(f$df$nitrogen))
})

test_that("NA cells in a treatment factor are preserved through masking", {
  f <- make_factorial_fixture()
  df <- f$df
  df$nitrogen[c(1L, 5L)] <- NA
  m <- mask(df, f$roles, mode = "collaborate", seed = 1)
  s <- synthetic(m)
  expect_true(all(is.na(s$nitrogen[c(1L, 5L)])))
  expect_equal(sum(is.na(s$nitrogen)), 2L)
})
