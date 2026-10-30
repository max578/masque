# F6: after environment scope resolves, block columns come from the
# within-environment block bases, never from an environment column.
# Every expected answer below follows from how the fixture is built.

# 2 years x 4 sites x 24 genotypes x 3 reps; in each site-year-rep, six blocks
# of four, labels B1-B6 restarted in every rep. True blocks: rep : block.
.f6_two_year_met <- function() {
  set.seed(6)
  years <- c(2023L, 2024L)
  sites <- sprintf("S%d", 1:4)
  gens <- sprintf("G%02d", 1:24)
  g <- expand.grid(
    genotype = gens, rep = 1:3, site = sites, year = years,
    stringsAsFactors = FALSE, KEEP.OUT.ATTRS = FALSE
  )
  g$block <- NA_character_
  for (y in years) for (s in sites) for (r in 1:3) {
    idx <- which(g$year == y & g$site == s & g$rep == r)
    g$block[idx] <- sprintf("B%d", sample(rep(1:6, each = 4)))
  }
  g$yield <- round(3 + rnorm(nrow(g), 0, 0.35), 2)
  g[, c("year", "site", "rep", "block", "genotype", "yield")]
}

# 2 sites, complete blocks B1-B4 restarted in each site, plot P01-P24 the
# position within block. A cyclic allocation with one swap makes plot
# positions look almost like regular incomplete blocks. True blocks: block.
.f6_plot_artefact <- function() {
  set.seed(13)
  g <- expand.grid(
    plot = 1:24, block = 1:4, site = c("North", "South"),
    stringsAsFactors = FALSE, KEEP.OUT.ATTRS = FALSE
  )
  idx <- (g$plot - 1L + 6L * (g$block - 1L)) %% 24L + 1L
  b2 <- which(g$block == 2L)
  swap <- c(b2[g$plot[b2] == 1L], b2[g$plot[b2] == 19L])
  idx[swap] <- idx[rev(swap)]
  labels <- list(
    North = sample(sprintf("G%02d", 1:24)),
    South = sample(sprintf("G%02d", 1:24))
  )
  g$genotype <- vapply(
    seq_len(nrow(g)), function(i) labels[[g$site[i]]][idx[i]], character(1L)
  )
  g$block <- sprintf("B%d", g$block)
  g$plot <- sprintf("P%02d", g$plot)
  g$yield <- round(4 + rnorm(nrow(g), 0, 0.4), 2)
  g[, c("site", "block", "plot", "genotype", "yield")]
}

# 2 sites x 4 reps x 24 genotypes, six blocks of four in each rep with labels
# restarted inside each replicate. True blocks: rep : block.
.f6_restarted_lattice <- function() {
  set.seed(11)
  sites <- c("North", "South")
  gens <- sprintf("G%02d", 1:24)
  g <- expand.grid(
    plot = 1:24, rep = 1:4, site = sites,
    stringsAsFactors = FALSE, KEEP.OUT.ATTRS = FALSE
  )
  g$block <- sprintf("B%d", (g$plot - 1L) %/% 4L + 1L)
  g$genotype <- NA_character_
  for (s in sites) for (r in 1:4) {
    idx <- which(g$site == s & g$rep == r)
    g$genotype[idx] <- sample(gens)
  }
  g$yield <- round(4 + rnorm(nrow(g), 0, 0.4), 2)
  g[, c("site", "rep", "block", "plot", "genotype", "yield")]
}

# Two sites with different blocking: S1 an RCBD on rep, S2 a CRD with no rep
# recorded. There is no common block basis.
.f6_two_site_disagree <- function() {
  set.seed(12)
  gens <- sprintf("G%d", 1:8)
  s1 <- expand.grid(
    genotype = gens, rep = 1:3,
    stringsAsFactors = FALSE, KEEP.OUT.ATTRS = FALSE
  )
  s1$site <- "S1"
  s2 <- data.frame(
    genotype = sample(rep(gens, 3)), rep = NA_integer_, site = "S2",
    stringsAsFactors = FALSE
  )
  d <- rbind(s1, s2)
  d$yield <- round(5 + rnorm(nrow(d), 0, 0.5), 2)
  d[, c("site", "rep", "genotype", "yield")]
}

.f6_print <- function(x) {
  paste(capture.output(print(x), type = "message"), collapse = "\n")
}

test_that("the F6 fixtures have the structure they are built with", {
  d <- .f6_two_year_met()
  per_rep <- data.table::as.data.table(d)[
    , .(n_blocks = data.table::uniqueN(block), n = .N),
    by = .(year, site, rep)
  ]
  expect_true(all(per_rep$n_blocks == 6L) && all(per_rep$n == 24L))
  expect_true(all(table(paste(d$year, d$site, d$rep, d$block)) == 4L))

  a <- .f6_plot_artefact()
  expect_true(all(table(a$site, a$block, a$genotype) == 1L))

  r <- .f6_restarted_lattice()
  expect_true(all(table(r$site, r$rep, r$genotype) == 1L))

  s <- .f6_two_site_disagree()
  expect_true(all(is.na(s$rep[s$site == "S2"])))
  expect_true(all(table(s$site, s$genotype) == 3L))
})

test_that("a two-year MET takes rep : block, not year, as its blocks", {
  d <- .f6_two_year_met()
  for (env in list(NULL, c("site", "year"))) {
    ds <- detect_design(d, env = env)
    expect_true(isTRUE(ds@is_met))
    expect_false("year" %in% ds@block_cols)
    expect_false("site" %in% ds@block_cols)
    expect_setequal(ds@block_cols, c("rep", "block"))
    expect_identical(ds@evidence$block_revision$status, "consensus")
  }
  expect_match(.f6_print(detect_design(d)), "within-environment consensus")
})

test_that("a stray plot does not survive the block revision", {
  d <- .f6_plot_artefact()
  ds <- detect_design(d)
  expect_true(isTRUE(ds@is_met))
  expect_identical(ds@env_cols, "site")
  expect_identical(ds@block_cols, "block")
  expect_false(any(c("plot", "site") %in% ds@block_cols))
  stale <- ds@recommended_roles$col[
    ds@recommended_roles$source == "design_rule" &
      ds@recommended_roles$role == "design"
  ]
  expect_false("plot" %in% stale)
})

test_that("block labels restarted inside each replicate give rep : block", {
  ds <- detect_design(.f6_restarted_lattice())
  expect_true(isTRUE(ds@is_met))
  expect_setequal(ds@block_cols, c("rep", "block"))
  expect_false(any(c("plot", "site") %in% ds@block_cols))
})

test_that("disagreeing within-environment blocks leave block_cols empty", {
  ds <- detect_design(.f6_two_site_disagree())
  expect_true(isTRUE(ds@is_met))
  expect_identical(ds@env_cols, "site")
  expect_identical(ds@block_cols, character())
  expect_identical(ds@evidence$block_revision$status, "cleared")
  expect_match(ds@evidence$block_revision$message, "disagree")
  expect_match(.f6_print(ds), "disagree")
})

test_that("env = FALSE keeps the pooled block columns", {
  ds <- detect_design(.f6_two_year_met(), env = FALSE)
  expect_identical(ds@block_cols, "year")
  expect_null(ds@evidence$block_revision)
})
