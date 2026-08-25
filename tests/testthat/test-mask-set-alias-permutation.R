# M-01 (2026-08-25 audit): the cross-table join-key alias map must be drawn
# from the seeded permutation like every other alias map. A lexicographic,
# seed-invariant map lets a holder of the synthetic plus a candidate
# vocabulary (a variety roster) invert the assignment with no recipe.


# Self-contained fixtures (mirrors test-mask-set.R; a test file must not
# depend on another test file's globals).
.perm_set <- function() {
  list(
    trials = data.frame(
      env = rep(c("E1", "E2"), each = 6),
      gen = rep(c("Scope", "Compass", "Spartacus"), 4),
      yield = c(3.1, 2.9, 4.0, 3.7, 5.2, 5.0, 3.3, 2.8, 4.1, 3.6, 5.1, 4.9),
      stringsAsFactors = FALSE
    ),
    pedigree = data.frame(
      gen = c("Scope", "Compass", "Spartacus"),
      maturity = c("early", "mid", "late"),
      stringsAsFactors = FALSE
    )
  )
}
.perm_roles <- function(tables) {
  list(
    trials = set_role(propose_roles(tables$trials, mode = "collaborate", detect = FALSE),
                      "gen", role = "treatment"),
    pedigree = set_role(propose_roles(tables$pedigree, mode = "collaborate", detect = FALSE),
                        "gen", role = "treatment")
  )
}

shared_map_for <- function(seed) {
  s <- .perm_set()
  roles <- .perm_roles(s)
  set.seed(seed)
  groups <- .resolve_links(s, roles, links = NULL, mode = "collaborate")
  built <- .build_shared_maps(s, roles, groups, mode = "collaborate")
  built$shared_by_table$trials$gen
}

test_that("linked-key alias maps are seed-dependent permutations, not sorted", {
  m1 <- shared_map_for(1L)
  m2 <- shared_map_for(999L)
  expect_setequal(names(m1), c("Compass", "Scope", "Spartacus"))
  expect_setequal(unname(m1), unname(m2))          # same alias pool
  expect_false(anyDuplicated(unname(m1)) > 0L)     # invertible
  # Across many seeds the assignment must vary: a sorted map never does.
  maps <- vapply(seq_len(40L), function(sd) paste(shared_map_for(sd), collapse = "|"),
                 character(1L))
  expect_gt(length(unique(maps)), 1L)
})
