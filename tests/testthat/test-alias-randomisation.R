# Audit finding M-01 -- the collaborate-mode alias map must not be the
# sort order.
#
# Aliasing used to assign `<prefix>001`, `<prefix>002`, ... in lexicographic
# order of the levels, invariant to `seed`. Anyone holding the synthetic and
# a candidate vocabulary -- a public variety roster, a published N-rate
# ladder -- inverted the map exactly, with no recipe: the k-th alias was
# always the k-th level in sort order. The map is now drawn from a random
# permutation taken from the same seeded RNG stream `mask()` already uses.
#
# ORACLE. The null the fix must satisfy is that the level receiving the
# first alias is uniform over the k levels. Its reference distribution is
# the discrete uniform on k categories, and the test statistic is Pearson's
# chi-squared goodness-of-fit, computed by `stats::chisq.test()` -- R Core's
# implementation, with the null and its p-value derived from the chi-squared
# distribution, not from anything masque produces.
#
# BEFORE THIS FIX: three seeds produced byte-identical maps, and the
# first-alias counts over 600 seeds were (600, 0, 0, 0, 0, 0), i.e.
# chi-squared = 3000 on 5 degrees of freedom, p < 1e-16.

alias_vocab <- function() {
  factor(
    c("Axe", "Boree", "Corack", "Dart", "Emu Rock", "Frelon"),
    levels = c("Axe", "Boree", "Corack", "Dart", "Emu Rock", "Frelon")
  )
}

# Which original level received the first alias, under one seed.
.first_alias_level <- function(x, seed, prefix = "trt_") {
  res <- withr::with_seed(seed, masque:::alias_levels(x, prefix = prefix))
  names(res$map)[res$map == sprintf("%s%03d", prefix, 1L)]
}

test_that("the alias map is not invariant to the seed", {
  x <- alias_vocab()
  maps <- lapply(
    c(1L, 999L, 424242L),
    function(s) withr::with_seed(s, masque:::alias_levels(x, "trt_"))$map
  )
  expect_false(identical(maps[[1L]], maps[[2L]]))
  expect_false(identical(maps[[1L]], maps[[3L]]))
  expect_false(identical(maps[[2L]], maps[[3L]]))
})

test_that("the first alias is uniform over the level vocabulary", {
  x <- alias_vocab()
  lvls <- levels(x)
  hits <- vapply(seq_len(600L), function(s) .first_alias_level(x, s), "")
  counts <- table(factor(hits, levels = lvls))
  expect_equal(sum(counts), 600L)
  # Pearson goodness-of-fit against the discrete uniform. A sort-order map
  # puts every count on one level and returns p < 1e-16.
  p <- stats::chisq.test(as.vector(counts))$p.value
  expect_gt(p, 0.001)
})

test_that("the alias map is reproducible for a fixed seed", {
  x <- alias_vocab()
  a <- withr::with_seed(7L, masque:::alias_levels(x, "trt_"))$map
  b <- withr::with_seed(7L, masque:::alias_levels(x, "trt_"))$map
  expect_identical(a, b)
})

test_that("randomised aliasing stays a frequency-preserving bijection", {
  set.seed(2)
  x <- factor(sample(levels(alias_vocab()), 300L, replace = TRUE))
  res <- withr::with_seed(31L, masque:::alias_levels(x, "trt_"))
  expect_setequal(names(res$map), levels(x))
  expect_equal(length(unique(unname(res$map))), length(levels(x)))
  expect_equal(
    unname(table(res$x)[unname(res$map[levels(x)])]),
    unname(table(x)[levels(x)])
  )
  inv <- stats::setNames(names(res$map), unname(res$map))
  expect_identical(unname(inv[as.character(res$x)]), as.character(x))
})

test_that("the factor level order of an aliased column leaks no ordering", {
  x <- alias_vocab()
  res <- withr::with_seed(5L, masque:::alias_levels(x, "trt_"))
  # Levels of the output are the alias vocabulary in its own sorted order,
  # so reading `levels()` says nothing about the original ordering.
  expect_identical(levels(res$x), sprintf("trt_%03d", seq_len(6L)))
})

test_that("mask(collaborate) produces a seed-dependent treatment map", {
  df <- data.frame(
    variety = alias_vocab(),
    yield = c(3.1, 4.2, 2.8, 5.0, 3.7, 4.4),
    stringsAsFactors = FALSE
  )
  r <- propose_roles(df, detect = FALSE)
  r$role[r$col == "variety"] <- "treatment"
  r$role[r$col == "yield"] <- "outcome"
  r <- roles_validate(r, df, mode = "collaborate")

  map_for <- function(s) {
    m <- suppressWarnings(
      mask(df, r, mode = "collaborate", seed = s)
    )
    recipe(m)@level_maps$variety
  }
  m1 <- map_for(1L)
  m2 <- map_for(999L)
  expect_false(identical(m1, m2))
  # And the round-trip still inverts under either seed.
  expect_setequal(names(m1), levels(df$variety))
  expect_setequal(unname(m1), sprintf("trt_%03d", seq_len(6L)))
})
