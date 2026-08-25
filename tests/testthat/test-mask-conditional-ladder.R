# Audit finding M-02 -- the conditioning ladder.
#
# `conditional = TRUE` used to take the finest available stratum (treatment
# crossed with EVERY surviving design column) and, when that stratum was too
# thin, pool the whole numeric block into one global fallback. On a replicated
# factorial -- the package's own anchor design -- every cell holds a single
# row, so 100 per cent of rows took the fallback and the clone became the
# pooled copula while the recipe still asserted `conditional = TRUE`.
#
# The gate below is the treatment sum-of-squares fraction (eta-squared) of the
# clone measured against the source.
#
# ORACLE. The numeric block here holds a single column, so masque's
# conditional path reduces to drawing, within each stratum, an independent
# sample with replacement from that stratum's observed values (an
# empirical-quantile inverse at `type = 1` on uniform probabilities is
# exactly a draw from the stratum's empirical distribution). The reference
# distribution of eta-squared under that mechanism is therefore the
# stratified nonparametric bootstrap, implemented below in base R
# (`sample()`), independently of any masque code. The source eta-squared is
# computed by `stats::aov()` -- R Core's implementation, not masque's.
#
# BEFORE THIS FIX, on the fixture below: source eta-squared 0.8588, clone
# 0.0042, oracle envelope [0.780, 0.925]. The audit measured the same
# collapse as 0.804 -> 0.019 on its own 6 x 3 x 4 fixture.

# A replicated 2 x 3 factorial with a planted treatment effect: three N
# rates crossed with two varieties in twelve blocks, 72 rows. The finest
# conditioning stratum (n_rate x variety x block) holds exactly one row.
ladder_factorial <- function(n_block = 12L, effect = 4, sd = 1.5,
                             seed = 20260825L) {
  set.seed(seed)
  d <- expand.grid(
    n_rate  = factor(c("N0", "N60", "N120"), levels = c("N0", "N60", "N120")),
    variety = factor(c("V1", "V2")),
    block   = factor(sprintf("B%02d", seq_len(n_block))),
    KEEP.OUT.ATTRS = FALSE
  )
  mu <- c(N0 = 0, N60 = effect, N120 = 2 * effect)[as.character(d$n_rate)]
  vv <- c(V1 = 0, V2 = 1)[as.character(d$variety)]
  d$yield <- 6 + mu + vv + stats::rnorm(nrow(d), sd = sd)
  d[, c("n_rate", "variety", "block", "yield")]
}

ladder_roles <- function(df) {
  r <- propose_roles(df, detect = FALSE)
  r$role[r$col == "n_rate"] <- "treatment"
  r$action[r$col == "n_rate"] <- "keep"
  r$role[r$col == "variety"] <- "design"
  r$action[r$col == "variety"] <- "keep"
  r$role[r$col == "block"] <- "design"
  r$action[r$col == "block"] <- "keep"
  r$role[r$col == "yield"] <- "outcome"
  r
}

# eta-squared via stats::aov (independent implementation).
.eta2_aov <- function(d) {
  ss <- summary(stats::aov(yield ~ n_rate, data = d))[[1L]][["Sum Sq"]]
  ss[1L] / sum(ss)
}

# The same quantity in closed form, used inside the bootstrap loop for
# speed. Checked against stats::aov in the first test below.
.eta2_fast <- function(y, g) {
  gm <- mean(y)
  mu <- tapply(y, g, mean)
  nn <- tapply(y, g, length)
  sum(nn * (mu - gm)^2) / sum((y - gm)^2)
}

# Stratified nonparametric bootstrap: resample the response with
# replacement within each conditioning cell, leaving the design columns
# in place. Base R only.
.strat_boot_eta2 <- function(d, cells, B = 2000L, seed = 99L) {
  set.seed(seed)
  idx <- split(seq_len(nrow(d)), interaction(d[cells], drop = TRUE))
  y0 <- d$yield
  g <- d$n_rate
  vapply(seq_len(B), function(b) {
    y <- y0
    for (cell in idx) y[cell] <- y0[sample(cell, length(cell), replace = TRUE)]
    .eta2_fast(y, g)
  }, numeric(1))
}

test_that("the closed-form eta-squared agrees with stats::aov", {
  d <- ladder_factorial()
  expect_equal(.eta2_fast(d$yield, d$n_rate), .eta2_aov(d))
})

test_that(
  "conditional clone of a replicated factorial keeps the source eta-squared",
  {
    d <- ladder_factorial()
    r <- ladder_roles(d)

    eta_src <- .eta2_aov(d)
    # The planted effect dominates: the source is a strong-effect trial.
    expect_gt(eta_src, 0.7)

    m <- suppressWarnings(
      mask(d, r, mode = "local", seed = 1, conditional = TRUE)
    )
    eta_clone <- .eta2_aov(as.data.frame(synthetic(m)))

    # Oracle envelope from the stratified nonparametric bootstrap at the
    # ladder rung the fix settles on (n_rate x variety). Two-sided at the
    # 0.1 / 99.9 percentiles: both the clone and the envelope are drawn
    # under fixed seeds, so the gate is deterministic, and the envelope is
    # a 998-per-mille interval rather than a 95 per cent one so that an
    # honest implementation has room to differ from the idealised
    # resampler without tripping the gate.
    env <- stats::quantile(
      .strat_boot_eta2(d, c("n_rate", "variety")),
      probs = c(0.001, 0.999), names = FALSE
    )
    expect_gt(eta_clone, env[1L])
    expect_lt(eta_clone, env[2L])
  }
)

test_that("the ladder coarsens the stratum and records the rung reached", {
  d <- ladder_factorial()
  r <- ladder_roles(d)
  m <- suppressWarnings(
    mask(d, r, mode = "local", seed = 1, conditional = TRUE)
  )
  rec <- recipe(m)

  # What was requested is unchanged: treatment plus every retained design
  # column.
  expect_identical(rec@conditioning_cols, c("n_rate", "variety", "block"))
  # What was used is the coarsened rung: `block`, the finest design column,
  # is dropped so the cells reach `min_stratum`.
  expect_identical(rec@conditioning_used, c("n_rate", "variety"))
  # And no row is left in the pooled fallback.
  expect_equal(rec@fallback_frac, 0)
})

test_that("dropping a rung raises a classed masque_conditional_degraded", {
  d <- ladder_factorial()
  r <- ladder_roles(d)
  expect_warning(
    mask(d, r, mode = "local", seed = 1, conditional = TRUE),
    class = "masque_conditional_degraded"
  )
})

test_that("a stratum that already holds enough rows is not degraded", {
  set.seed(3)
  n <- 240L
  d <- data.frame(
    arm = factor(rep(c("ctrl", "treat"), each = n / 2L)),
    yield = 10 + 5 * rep(c(0, 1), each = n / 2L) + stats::rnorm(n, sd = 2)
  )
  r <- propose_roles(d, detect = FALSE)
  r$role[r$col == "arm"] <- "treatment"
  r$action[r$col == "arm"] <- "keep"
  r$role[r$col == "yield"] <- "outcome"

  warned <- character()
  m <- withCallingHandlers(
    mask(d, r, mode = "local", seed = 1, conditional = TRUE),
    warning = function(w) {
      warned <<- c(warned, class(w)[1L])
      invokeRestart("muffleWarning")
    }
  )
  expect_false("masque_conditional_degraded" %in% warned)
  rec <- recipe(m)
  expect_identical(rec@conditioning_used, rec@conditioning_cols)
  expect_equal(rec@fallback_frac, 0)
})
