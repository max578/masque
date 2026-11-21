# conditional = "design" and an explicit conditioning partition (N04).

.fx_blocks <- function(seed = 1L) {
  withr::with_seed(seed, {
    d <- expand.grid(
      rep = paste0("R", 1:3), block = paste0("B", 1:4), plot = 1:6,
      stringsAsFactors = FALSE
    )
    d$block <- paste(d$rep, d$block, sep = "_")
    d$gen <- paste0("G", sample(rep(1:8, length.out = nrow(d))))
    blk <- stats::setNames(stats::rnorm(12L, 0, 3), unique(d$block))
    gen <- stats::setNames(stats::rnorm(8L, 0, 3), paste0("G", 1:8))
    d$y <- 50 + blk[d$block] + gen[d$gen] + stats::rnorm(nrow(d))
    d$plot <- NULL
    d
  })
}

.fx_block_roles <- function(d) {
  r <- propose_roles(d, detect = FALSE)
  r <- set_role(r, c("rep", "block"), role = "design", action = "keep")
  r <- set_role(r, "gen", role = "treatment", action = "keep")
  set_role(r, "y", role = "outcome", action = "scramble")
}

.mask_q <- function(...) {
  suppressWarnings(mask(..., mode = "local", quiet = TRUE))
}

test_that("conditional = 'design' carries design means and nulls treatment", {
  d <- .fx_blocks()
  r <- .fx_block_roles(d)
  block_sd <- function(x) stats::sd(tapply(x$y, x$block, mean))
  gen_sd <- function(x) stats::sd(tapply(x$y, x$gen, mean))
  runs <- lapply(1:30, function(s) {
    synthetic(.mask_q(d, r, seed = s, conditional = "design"))
  })
  b <- vapply(runs, block_sd, numeric(1))
  g <- vapply(runs, gen_sd, numeric(1))
  expect_lt(abs(mean(b) / block_sd(d) - 1), 0.15)
  # The real genotype spread is about 3; a null clone holds only sampling noise.
  expect_lt(mean(g), 0.5 * gen_sd(d))

  # Falsifier: TRUE keeps the genotype spread, FALSE loses the block spread.
  cond <- synthetic(.mask_q(d, r, seed = 1L, conditional = TRUE))
  expect_gt(gen_sd(cond), 0.7 * gen_sd(d))
  marg <- lapply(1:10, function(s) {
    synthetic(.mask_q(d, r, seed = s, conditional = FALSE))
  })
  # A pooled clone's block means hold only noise: sd(y) / sqrt(6 plots).
  expect_lt(mean(vapply(marg, block_sd, numeric(1))),
            1.1 * stats::sd(d$y) / sqrt(6))
  expect_gt(block_sd(d), 1.5 * stats::sd(d$y) / sqrt(6))
})

test_that("the recipe records the design partition without the treatment", {
  d <- .fx_blocks()
  m <- .mask_q(d, .fx_block_roles(d), seed = 2L, conditional = "design")
  rec <- recipe(m)
  expect_true(rec@conditional)
  expect_setequal(rec@conditioning_cols, c("rep", "block"))
  expect_false("gen" %in% rec@conditioning_used)
  expect_match(.recipe_fidelity_line(rec), "treatment effect not carried")
})

test_that("an explicit partition is used, and TRUE is unchanged by the option", {
  d <- .fx_blocks()
  r <- .fx_block_roles(d)
  a <- .mask_q(d, r, seed = 3L, conditional = c("rep", "block"))
  b <- .mask_q(d, r, seed = 3L, conditional = "design")
  expect_identical(synthetic(a), synthetic(b))

  e <- .mask_q(d, r, seed = 3L, conditional = "rep")
  expect_identical(recipe(e)@conditioning_used, "rep")
  # gen x rep holds three rows a cell: the treatment stays, rep is given up.
  f <- .mask_q(d, r, seed = 3L, conditional = c("gen", "rep"))
  expect_setequal(recipe(f)@conditioning_cols, c("gen", "rep"))
  expect_identical(recipe(f)@conditioning_used, "gen")

  t1 <- .mask_q(d, r, seed = 3L, conditional = TRUE)
  t2 <- .mask_q(d, r, seed = 3L, conditional = c("rep", "block", "gen"))
  expect_identical(
    data.table::setcolorder(data.table::copy(synthetic(t1)), names(d)),
    data.table::setcolorder(data.table::copy(synthetic(t2)), names(d))
  )
})

test_that("structure is preserved and the recipe round-trips", {
  d <- .fx_blocks()
  d$y[c(3L, 40L)] <- NA
  r <- .fx_block_roles(d)
  m <- .mask_q(d, r, seed = 4L, conditional = "design")
  s <- synthetic(m)
  expect_identical(s$rep, d$rep)
  expect_identical(s$block, d$block)
  expect_identical(s$gen, d$gen)
  expect_identical(is.na(s$y), is.na(d$y))
  expect_identical(apply_recipe(d, recipe(m))$gen, s$gen)
})

test_that("the ladder coarsens a thin design partition and warns", {
  d <- .fx_blocks()
  d$row <- seq_len(nrow(d))
  r <- propose_roles(d, detect = FALSE)
  r <- set_role(r, c("rep", "block", "row"), role = "design", action = "keep")
  r <- set_role(r, "gen", role = "treatment", action = "keep")
  r <- set_role(r, "y", role = "outcome", action = "scramble")
  expect_warning(
    m <- mask(d, r, mode = "local", seed = 5L, quiet = TRUE,
              conditional = "design"),
    class = "masque_conditional_degraded"
  )
  expect_false("row" %in% recipe(m)@conditioning_used)
})

test_that("with no design column left the design option warns and pools", {
  d <- .fx_blocks()
  r <- propose_roles(d, detect = FALSE)
  r <- set_role(r, c("rep", "block"), role = "covariate", action = "scramble")
  r <- set_role(r, "gen", role = "treatment", action = "keep")
  r <- set_role(r, "y", role = "outcome", action = "scramble")
  expect_warning(
    m <- mask(d, r, mode = "local", seed = 6L, quiet = TRUE,
              conditional = "design"),
    class = "masque_conditional_degraded"
  )
  expect_length(recipe(m)@conditioning_used, 0L)
})

test_that("a bad partition is refused by class", {
  d <- .fx_blocks()
  r <- .fx_block_roles(d)
  cls <- "masque_bad_conditional_refusal"
  expect_error(.mask_q(d, r, conditional = "nope"), class = cls)
  expect_error(.mask_q(d, r, conditional = c("rep", "y")), class = cls)
  expect_error(.mask_q(d, r, conditional = character()), class = cls)
  expect_error(.mask_q(d, r, conditional = NA_character_), class = cls)
  expect_error(.mask_q(d, r, conditional = c("rep", "rep")), class = cls)
  expect_error(.mask_q(d, r, conditional = 1), class = cls)
  r2 <- set_role(r, "rep", role = "design", action = "drop")
  expect_error(.mask_q(d, r2, conditional = "rep"), class = cls)
})

test_that("the design option leaves linked events unstratified by treatment", {
  n <- 200L
  d <- withr::with_seed(8L, data.frame(
    arm = rep(c("a", "b"), length.out = n),
    centre = rep(c("c1", "c2", "c3", "c4"), each = n / 4L),
    t1 = stats::rexp(n, 0.2)
  ))
  d$t2 <- d$t1 + withr::with_seed(9L, stats::rexp(n, 0.1))
  d$s1 <- withr::with_seed(10L, stats::rbinom(n, 1L, ifelse(d$arm == "a", 0.9, 0.1)))
  d$s2 <- 1L
  r <- propose_roles(d, detect = FALSE)
  r <- set_role(r, "centre", role = "design", action = "keep")
  r <- set_role(r, "arm", role = "treatment", action = "keep")
  r <- set_role(r, c("t1", "t2", "s1", "s2"), role = "outcome", action = "scramble")
  ev <- list(list(time = c("t1", "t2"), status = c("s1", "s2")))
  gap <- function(m) {
    s <- synthetic(m)
    abs(mean(s$s1[s$arm == "a"]) - mean(s$s1[s$arm == "b"]))
  }
  des <- .mask_q(d, r, seed = 1L, conditional = "design", events = ev)
  tru <- .mask_q(d, r, seed = 1L, conditional = TRUE, events = ev)
  expect_lt(gap(des), 0.25)
  expect_gt(gap(tru), 0.6)
})
