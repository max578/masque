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

# --- the hierarchy ladder (0.13.0) -------------------------------------------

# A two-environment trial with eight replicates per environment: enough
# rows for site x treatment to satisfy the stratum floor, so the drop order
# is visible in the rung reached.
ladder_met <- function(seed = 20260925L) {
  set.seed(seed)
  d <- expand.grid(
    trt = factor(c("T1", "T2", "T3")),
    rep = factor(sprintf("R%d", 1:8)),
    site = factor(c("North", "South")),
    KEEP.OUT.ATTRS = FALSE
  )
  d$row <- rep(seq_len(24L), times = 2L)
  d$yield <- 10 + c(T1 = 0, T2 = 2, T3 = 4)[as.character(d$trt)] +
    c(North = 0, South = 6)[as.character(d$site)] +
    (as.integer(d$rep) - 1L) +
    stats::rnorm(nrow(d), sd = 0.8)
  d
}

ladder_met_roles <- function(d) {
  r <- propose_roles(d, detect = FALSE)
  r$role[r$col == "trt"] <- "treatment"
  r$action[r$col == "trt"] <- "keep"
  r$role[r$col %in% c("rep", "site", "row")] <- "design"
  r$action[r$col %in% c("rep", "site", "row")] <- "keep"
  r$role[r$col == "yield"] <- "outcome"
  r
}

test_that("the hierarchy ladder drops coordinates, then blocks, then environments", {
  d <- ladder_met()
  lad <- masque:::.conditioning_ladder(
    d, c("site", "rep", "row", "trt"), protect_cols = "trt",
    min_stratum = 5L, ladder = "hierarchy", x_num = d["yield"]
  )
  expect_identical(lad$used, c("trt", "site"))
  expect_identical(lad$dropped, c("row", "rep"))
  expect_setequal(lad$shifted, c("rep", "row"))
  expect_equal(lad$fallback_frac, 0)

  ord <- masque:::.order_by_hierarchy(d, c("rep", "row", "site"), d["yield"])
  expect_identical(ord, c("row", "rep", "site"))
  expect_identical(masque:::.order_by_levels(d, c("rep", "row", "site")),
    c("row", "rep", "site")
  )
})

test_that("within a tier the column explaining the least variance goes first", {
  d <- ladder_met()
  # Two blocking columns: `rep` carries a planted effect, `block` none.
  d$block <- factor(rep(c("B1", "B2"), length.out = nrow(d)))
  eta <- masque:::.variance_explained(d, c("rep", "block"), d["yield"])
  expect_gt(eta[["rep"]], eta[["block"]])
  expect_identical(
    masque:::.order_by_hierarchy(d, c("rep", "block"), d["yield"]),
    c("block", "rep")
  )
})

test_that("an environment is never dropped before its replicates", {
  d <- ladder_met()
  ord <- masque:::.order_by_hierarchy(d, c("site", "rep"), d["yield"])
  expect_identical(ord, c("rep", "site"))
  ord2 <- masque:::.order_by_hierarchy(d, c("county", "block"), NULL)
  expect_identical(ord2, c("block", "county"))
})

test_that("the design shifts reproduce the dropped columns' main effects", {
  d <- ladder_met()
  out <- masque:::.design_shifts(d["yield"], d, used = "trt",
    shifted = c("site", "rep")
  )
  expect_identical(out$shifted, c("site", "rep"))
  shift <- out$shift
  expect_identical(dim(shift), c(nrow(d), 1L))
  # The site contrast in the shift matches the planted 6 within tolerance.
  site_gap <- diff(tapply(shift[, "yield"], d$site, mean))
  expect_equal(unname(site_gap), 6, tolerance = 0.15)
  # A row with a missing design value gets no shift.
  d2 <- d
  d2$site[1L] <- NA
  shift2 <- masque:::.design_shifts(d2["yield"], d2, "trt", c("site", "rep"))$shift
  expect_equal(unname(shift2[1L, "yield"]), 0)
  # No shifted column: a zero matrix.
  expect_true(all(
    masque:::.design_shifts(d["yield"], d, "trt", character())$shift == 0
  ))
})

test_that("a level with one row never receives its own outcome as a shift", {
  d <- ladder_met()
  d$plot <- seq_len(nrow(d))
  expect_false(masque:::.shiftable(d$plot))
  expect_true(masque:::.shiftable(d$rep))
  # A column with two replicated levels and a tail of singletons: the
  # singletons share one pooled level.
  v <- c("A", "A", "B", "B", "c", "d", "e")
  expect_identical(
    as.character(masque:::.collapse_singletons(v)),
    c("A", "A", "B", "B", ".singleton", ".singleton", ".singleton")
  )
  out <- masque:::.design_shifts(d["yield"], d, "trt", c("plot", "site"))
  expect_identical(out$shifted, "site")
  expect_lte(length(unique(round(out$shift[, "yield"], 8))), 2L)
})

test_that("rows in the pooled fallback keep the stratum's main effect", {
  # Three replicates per genotype: the treatment-only rung is below the
  # floor of five, so without a shift the genotype means would be lost.
  set.seed(11)
  d <- expand.grid(
    gen = factor(sprintf("G%02d", 1:20)), rep = factor(c("R1", "R2", "R3")),
    KEEP.OUT.ATTRS = FALSE
  )
  g_eff <- stats::rnorm(20, sd = 3)
  d$yield <- 50 + g_eff[as.integer(d$gen)] +
    c(R1 = 0, R2 = 2, R3 = 4)[as.character(d$rep)] + stats::rnorm(nrow(d))
  r <- propose_roles(d, detect = FALSE)
  r$role[r$col == "gen"] <- "treatment"
  r$action[r$col == "gen"] <- "keep"
  r$role[r$col == "rep"] <- "design"
  r$action[r$col == "rep"] <- "keep"
  r$role[r$col == "yield"] <- "outcome"
  m <- suppressWarnings(mask(d, r, mode = "local", seed = 5L, conditional = TRUE))
  rec <- recipe(m)
  expect_equal(rec@fallback_frac, 1)
  expect_setequal(rec@conditioning_shifted, c("rep", "gen"))
  gm_o <- tapply(d$yield, d$gen, mean)
  gm_s <- tapply(synthetic(m)$yield, synthetic(m)$gen, mean)
  expect_gt(cor(gm_o, gm_s[names(gm_o)]), 0.9)
  # Under the levels ladder the same clone carries no genotype signal.
  m0 <- suppressWarnings(
    mask(d, r, mode = "local", seed = 5L, conditional = TRUE, ladder = "levels")
  )
  gm_0 <- tapply(synthetic(m0)$yield, synthetic(m0)$gen, mean)
  expect_lt(abs(cor(gm_o, gm_0[names(gm_o)])), 0.6)
})

test_that("mask(ladder = 'hierarchy') keeps the environment effect of a MET", {
  d <- ladder_met()
  r <- ladder_met_roles(d)
  fit <- function(x) anova(stats::lm(yield ~ site + site:rep + trt, data = x))
  f_orig <- fit(d)
  m <- suppressWarnings(
    mask(d, r, mode = "local", seed = 3L, conditional = TRUE)
  )
  rec <- recipe(m)
  expect_identical(rec@ladder, "hierarchy")
  expect_identical(rec@conditioning_used, c("trt", "site"))
  expect_identical(rec@conditioning_dropped, c("row", "rep"))
  expect_setequal(rec@conditioning_shifted, c("rep", "row"))
  f_clone <- fit(as.data.frame(synthetic(m)))
  # Floor 0.4: the clone re-draws each cell's six-to-eight residuals, and
  # site:rep in the original is half replicate signal and half noise df.
  expect_gt(f_clone["site", "F value"], 0.4 * f_orig["site", "F value"])
  expect_gt(f_clone["site:rep", "F value"], 0.4 * f_orig["site:rep", "F value"])
  expect_gt(f_clone["trt", "F value"], 0.4 * f_orig["trt", "F value"])
  # The degradation warning names the shift.
  expect_warning(
    mask(d, r, mode = "local", seed = 3L, conditional = TRUE),
    "carried into the clone as an additive shift"
  )
})

test_that("ladder = 'levels' is the 0.12.0 ladder and records no shift", {
  d <- ladder_met()
  r <- ladder_met_roles(d)
  m <- suppressWarnings(
    mask(d, r, mode = "local", seed = 3L, conditional = TRUE, ladder = "levels")
  )
  rec <- recipe(m)
  expect_identical(rec@ladder, "levels")
  expect_identical(rec@conditioning_used, c("trt", "site"))
  expect_identical(rec@conditioning_shifted, character())
  # With no shift, the dropped rep effect is gone from the clone.
  f_clone <- anova(stats::lm(yield ~ site + site:rep + trt, data = synthetic(m)))
  f_orig <- anova(stats::lm(yield ~ site + site:rep + trt, data = d))
  expect_lt(f_clone["site:rep", "F value"], 0.5 * f_orig["site:rep", "F value"])
})

test_that("a bad ladder value is a typed refusal", {
  d <- ladder_met()
  r <- ladder_met_roles(d)
  err <- tryCatch(mask(d, r, seed = 1L, ladder = "steps"), error = function(e) e)
  expect_true(inherits(err, "masque_bad_ladder_refusal"))
  expect_true(inherits(err, "orchestra_refusal"))
})
