# A conditional clone must not rebuild a row's value from a tiny design level,
# and the audit must see a clone that tracks the original row by row.

.fx_pairs <- function(n = 400L, seed = 2L) {
  withr::with_seed(seed, {
    d <- data.frame(
      gen = paste0("G", sample(20L, n, TRUE)),
      rep = paste0("R", rep(1:4, length.out = n)),
      pairid = paste0("P", rep(seq_len(n / 2L), each = 2L))
    )
    u <- rep(stats::rnorm(n / 2L, 0, 2), each = 2L)
    d$y <- 10 + u + stats::rnorm(n, 0, 0.2)
    d$z <- 3 + 0.5 * u + stats::rnorm(n, 0, 0.2)
    d
  })
}

.fx_pair_roles <- function(d) {
  r <- propose_roles(d, mode = "collaborate", detect = FALSE)
  r <- set_role(r, c("rep", "pairid"), role = "design", action = "keep")
  r <- set_role(r, "gen", role = "treatment", action = "alias")
  set_role(r, c("y", "z"), role = "outcome", action = "scramble")
}

test_that("a two-row design level gives no shift that rebuilds the value", {
  d <- .fx_pairs()
  r <- .fx_pair_roles(d)
  for (cnd in list(TRUE, "design")) {
    m <- suppressWarnings(mask(d, r, mode = "collaborate", conditional = cnd,
                               seed = 1L, quiet = TRUE))
    expect_lt(abs(stats::cor(d$y, synthetic(m)$y)), 0.5)
  }
})

test_that("a design level of ample rows still carries its shift", {
  d <- .fx_pairs(400L)
  withr::with_seed(5L, {
    d$env <- rep(paste0("E", 1:8), each = 50L)
    d$y <- rep(stats::rnorm(8L, 0, 3), each = 50L) + stats::rnorm(400L)
  })
  d$pairid <- NULL
  r <- propose_roles(d, mode = "collaborate", detect = FALSE)
  r <- set_role(r, c("rep", "env"), role = "design", action = "keep")
  r <- set_role(r, "gen", role = "treatment", action = "alias")
  r <- set_role(r, c("y", "z"), role = "outcome", action = "scramble")
  m <- suppressWarnings(mask(d, r, mode = "collaborate", conditional = "design",
                             seed = 1L, quiet = TRUE))
  env_sd <- function(x) stats::sd(tapply(x$y, x$env, mean))
  expect_lt(abs(env_sd(synthetic(m)) / env_sd(d) - 1), 0.2)
})

test_that("the audit raises HIGH when a clone tracks the original row by row", {
  withr::local_seed(4L)
  n <- 300L
  k <- 5L
  d <- data.frame(
    gen = paste0("G", sample(4L, n, TRUE)),
    block = paste0("B", rep(seq_len(n / k), each = k))
  )
  d$y <- rep(stats::rnorm(n / k, 0, 5), each = k) + stats::rnorm(n, 0, 0.05)
  r <- propose_roles(d, mode = "collaborate", detect = FALSE)
  r <- set_role(r, "block", role = "design", action = "keep")
  r <- set_role(r, "gen", role = "treatment", action = "alias")
  r <- set_role(r, "y", role = "outcome", action = "scramble")
  m <- suppressWarnings(mask(d, r, mode = "collaborate", conditional = "design",
                             seed = 1L, quiet = TRUE))
  expect_gt(stats::cor(d$y, synthetic(m)$y), 0.95)
  expect_identical(m@audit$leakage_class[m@audit$col == "y"], "high")
  expect_error(handover(m, file.path(withr::local_tempdir(), "p")),
               class = "masque_blocked_write")
  # Falsifier: the marginal clone of the same table is not flagged.
  g <- suppressWarnings(mask(d, r, mode = "collaborate", seed = 1L, quiet = TRUE))
  expect_false(identical(g@audit$leakage_class[g@audit$col == "y"], "high"))
})

test_that("the design clone's residual matches an owner's negative control", {
  # A permutation moves a real treatment effect into the residual. The design
  # clone does the same, so negatives on the two sides share a denominator.
  withr::local_seed(8L)
  d <- expand.grid(gen = paste0("G", 1:10), rep = paste0("R", 1:6),
                   stringsAsFactors = FALSE)
  d$y <- as.numeric(factor(d$gen)) * 1.8 + as.numeric(factor(d$rep)) +
    stats::rnorm(nrow(d))
  r <- propose_roles(d, mode = "local", detect = FALSE)
  r <- set_role(r, "rep", role = "design", action = "keep")
  r <- set_role(r, "gen", role = "treatment", action = "keep")
  r <- set_role(r, "y", role = "outcome", action = "scramble")
  rms <- function(x) stats::anova(stats::lm(y ~ rep + gen, x))["Residuals", "Mean Sq"]
  own <- controls(d, r, control_spec(on = "gen", strata = "rep", n = 40L, seed = 3L),
                  seed = 11L)
  owner_rms <- vapply(1:40, function(i) rms(control_table(own, "negative", i)), numeric(1))
  clone_rms <- vapply(1:40, function(s) {
    rms(synthetic(suppressWarnings(mask(d, r, seed = s, quiet = TRUE, conditional = "design"))))
  }, numeric(1))
  expect_gt(rms(d) * 5, 1)
  expect_gt(mean(owner_rms), 5 * rms(d))
  expect_lt(abs(mean(clone_rms) / mean(owner_rms) - 1), 0.25)
})

test_that("big environment means in large cells grade medium, not high", {
  withr::local_seed(6L)
  d <- expand.grid(env = paste0("E", 1:10), plot = 1:40, stringsAsFactors = FALSE)
  d$gen <- paste0("G", sample(10L, nrow(d), TRUE))
  d$y <- rep(stats::rnorm(10L, 0, 30), times = 40L) + stats::rnorm(nrow(d))
  d$plot <- NULL
  r <- propose_roles(d, mode = "collaborate", detect = FALSE)
  r <- set_role(r, "env", role = "design", action = "keep")
  r <- set_role(r, "gen", role = "treatment", action = "alias")
  r <- set_role(r, "y", role = "outcome", action = "scramble")
  m <- suppressWarnings(mask(d, r, mode = "collaborate", conditional = "design",
                             seed = 1L, quiet = TRUE))
  expect_gt(stats::cor(d$y, synthetic(m)$y), 0.95)
  expect_identical(m@audit$leakage_class[m@audit$col == "y"], "medium")
})

test_that("three- and four-row levels that track their rows are HIGH and blocked", {
  for (k in 3:4) {
    n <- 240L
    withr::with_seed(k, {
      d <- data.frame(
        gen = paste0("G", sample(10L, n, TRUE)),
        lv = paste0("L", rep(seq_len(n / k), each = k))
      )
      d$y <- rep(stats::rnorm(n / k, 0, 3), each = k) + stats::rnorm(n, 0, 0.2)
    })
    r <- propose_roles(d, mode = "collaborate", detect = FALSE)
    r <- set_role(r, "lv", role = "design", action = "keep")
    r <- set_role(r, "gen", role = "treatment", action = "alias")
    r <- set_role(r, "y", role = "outcome", action = "scramble")
    m <- suppressWarnings(mask(d, r, mode = "collaborate", conditional = "design",
                               seed = 1L, quiet = TRUE))
    expect_gt(abs(stats::cor(d$y, synthetic(m)$y)), 0.9)
    expect_identical(m@audit$leakage_class[m@audit$col == "y"], "high")
    expect_error(
      handover(m, file.path(withr::local_tempdir(), "p")),
      class = "masque_blocked_write"
    )
  }
})

test_that("a tracking subset of small levels is seen among many single rows", {
  withr::local_seed(14L)
  sizes <- c(rep(3L, 30L), rep(1L, 310L))
  d <- data.frame(lv = rep(sprintf("L%03d", seq_along(sizes)), sizes))
  d$gen <- paste0("G", sample(10L, nrow(d), TRUE))
  d$y <- rep(stats::rnorm(length(sizes), 0, 3), sizes) + stats::rnorm(nrow(d), 0, 0.2)
  r <- propose_roles(d, mode = "collaborate", detect = FALSE)
  r <- set_role(r, "lv", role = "design", action = "keep")
  r <- set_role(r, "gen", role = "treatment", action = "alias")
  r <- set_role(r, "y", role = "outcome", action = "scramble")
  m <- suppressWarnings(mask(d, r, mode = "collaborate", conditional = "design",
                             seed = 1L, quiet = TRUE))
  overall <- stats::cor(d$y, synthetic(m)$y)
  expect_lt(abs(overall), 0.7)
  # The overall figure alone reads low; the rows of the small levels do not.
  expect_identical(m@audit$leakage_class[m@audit$col == "y"], "medium")
})

test_that("a lone small level is not shifted to its own value", {
  withr::local_seed(12L)
  n <- 300L
  d <- data.frame(
    gen = paste0("G", sample(5L, n + 1L, TRUE)),
    lv = c(paste0("L", rep(seq_len(n / 10L), each = 10L)), "rare")
  )
  d$y <- rep(stats::rnorm(n / 10L + 1L, 10, 1), c(rep(10L, n / 10L), 1L)) +
    stats::rnorm(n + 1L, 0, 0.2)
  d$y[n + 1L] <- 24
  d$env <- rep(c("a", "b", "c"), length.out = n + 1L)
  r <- propose_roles(d, mode = "collaborate", detect = FALSE)
  r <- set_role(r, c("lv", "env"), role = "design", action = "keep")
  r <- set_role(r, "gen", role = "treatment", action = "alias")
  r <- set_role(r, "y", role = "outcome", action = "scramble")
  rare <- vapply(1:12, function(s) {
    synthetic(suppressWarnings(mask(d, r, mode = "collaborate", conditional = "design",
                                    seed = s, quiet = TRUE)))$y[n + 1L]
  }, numeric(1))
  expect_lt(abs(mean(rare) - 10), 6)
})

test_that("strong sites do not block a design clone; within-cell tracking does", {
  sim <- function(site_sd, within_share) {
    withr::with_seed(21L, {
      d <- expand.grid(site = paste0("S", 1:6), rep = paste0("R", 1:3), block = paste0("B", 1:5),
                       plot = 1:6, stringsAsFactors = FALSE)
      d$block <- paste(d$site, d$rep, d$block, sep = "_")
      d$rep <- paste(d$site, d$rep, sep = "_")
      d$plot <- NULL
      d$gen <- paste0("G", sample(30L, nrow(d), TRUE))
      s <- stats::setNames(stats::rnorm(6L, 0, site_sd), paste0("S", 1:6))
      b <- stats::setNames(stats::rnorm(90L, 0, within_share), unique(d$block))
      d$y <- s[d$site] + b[d$block] + stats::rnorm(nrow(d), 0, 1)
      d
    })
  }
  run <- function(d) {
    r <- propose_roles(d, mode = "collaborate", detect = FALSE)
    r <- set_role(r, c("site", "rep", "block"), role = "design", action = "keep")
    r <- set_role(r, "gen", role = "treatment", action = "alias")
    r <- set_role(r, "y", role = "outcome", action = "scramble")
    m <- suppressWarnings(mask(d, r, mode = "collaborate", conditional = "design",
                               seed = 1L, quiet = TRUE))
    m@audit$leakage_class[m@audit$col == "y"]
  }
  expect_false(identical(run(sim(25, 0.3)), "high"))
  expect_identical(run(sim(1, 15)), "high")
})
