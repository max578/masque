# The owner's draw: a 256-bit key, used whole, and no integer to search.

owner_fixture <- function() {
  set.seed(5)
  d <- expand.grid(gen = paste0("g", 1:6), rep = paste0("r", 1:6), stringsAsFactors = FALSE)
  d$y <- stats::rnorm(36L)
  r <- suppressWarnings(propose_roles(d, detect = FALSE))
  r <- set_role(r, "rep", role = "design", action = "keep")
  r <- set_role(r, "gen", role = "treatment", action = "keep")
  r <- set_role(r, "y", role = "outcome", action = "scramble")
  list(d = d, r = r, spec = control_spec(on = "gen", strata = "rep", n = 3L, seed = 99L))
}

test_that("the owner key is 256 bits from the system source", {
  key <- masque:::.new_owner_key()
  expect_match(key, "^[0-9a-f]{64}$")
  expect_false(identical(key, masque:::.new_owner_key()))
  set.seed(1)
  a <- masque:::.new_owner_key()
  set.seed(1)
  expect_false(identical(a, masque:::.new_owner_key()))
})

test_that("the key is the system's bytes and nothing else", {
  testthat::local_mocked_bindings(.system_entropy = function() as.raw(1:32), .package = "masque")
  expect_identical(masque:::.new_owner_key(), paste(as.character(as.raw(1:32)), collapse = ""))
})

test_that("a recipe draw is the whole digest and holds no integer seed", {
  draw <- masque:::.control_source_draw(strrep("ab", 32L), 99L, NULL)
  expect_null(draw$seed)
  expect_match(draw$key, "^[0-9a-f]{64}$")
  f <- owner_fixture()
  m <- mask(f$d, masque_plan(f$r, controls = f$spec), seed = 1L, quiet = TRUE)
  own <- controls(f$d, clone_plan(m), recipe = recipe(m))
  expect_true(all(is.na(own@seeds)))
  expect_true(all(is.na(own@manifest$seed)))
  shown <- c(utils::capture.output(print(own)), utils::capture.output(utils::str(own)))
  expect_false(any(grepl(own@key, shown, fixed = TRUE)))
  # A key differing in its last digit gives other permutations.
  other <- own
  last <- substr(own@key, 64L, 64L)
  other@key <- paste0(substr(own@key, 1L, 63L), if (last == "0") "1" else "0")
  expect_false(identical(
    control_table(own, "negative", 1L)$gen, control_table(other, "negative", 1L)$gen
  ))
})

test_that("a keyed table ignores the R stream and leaves it alone", {
  f <- owner_fixture()
  m <- mask(f$d, masque_plan(f$r, controls = f$spec), seed = 1L, quiet = TRUE)
  own <- controls(f$d, clone_plan(m), recipe = recipe(m))
  set.seed(1)
  a <- control_table(own, "negative", 2L)
  before <- .Random.seed
  set.seed(2)
  b <- control_table(own, "negative", 2L)
  expect_identical(a$gen, b$gen)
  set.seed(1)
  invisible(control_table(own, "negative", 2L))
  expect_identical(.Random.seed, before)
  expect_identical(sort(a$gen), sort(f$d$gen))
  expect_true(all(tapply(a$gen, a$rep, function(v) length(unique(v))) == 6L))
})

test_that("keyed permutations are uniform", {
  draws <- vapply(seq_len(6000L), function(i) {
    paste(masque:::.keyed_perm(paste("k", i), 3L), collapse = "")
  }, character(1L))
  counts <- table(draws)
  expect_length(counts, 6L)
  expect_gt(stats::chisq.test(counts)$p.value, 1e-4)
  expect_identical(sort(masque:::.keyed_perm("k", 50L)), 1:50)
  expect_identical(masque:::.keyed_perm("k", 1L), 1L)
})

test_that("with no system source the mask warns and controls ask for a seed", {
  f <- owner_fixture()
  testthat::local_mocked_bindings(.system_entropy = function() NULL, .package = "masque")
  expect_identical(masque:::.new_owner_key(), character())
  expect_warning(
    m <- mask(f$d, masque_plan(f$r, controls = f$spec), seed = 1L, quiet = TRUE),
    class = "masque_owner_key_unavailable"
  )
  expect_error(
    controls(f$d, clone_plan(m), recipe = recipe(m)), class = "masque_control_seed_refusal"
  )
  own <- controls(f$d, clone_plan(m), recipe = recipe(m), seed = 7L)
  expect_false(anyNA(own@seeds))
})

test_that("an explicit integer seed keeps its stream", {
  f <- owner_fixture()
  ctl <- controls(f$d, f$r, f$spec, seed = 7L)
  seeds <- as.integer(masque:::.sub_seeds(7L, 4L))
  expect_identical(ctl@seeds, seeds)
  out <- withr::with_seed(seeds[2L], {
    perm <- integer(36L)
    for (g in split(seq_len(36L), masque:::.unit_id(f$d, "rep"))) {
      perm[g] <- g[sample.int(length(g))]
    }
    f$d$gen[perm]
  })
  expect_identical(control_table(ctl, "negative", 1L)$gen, out)
})
