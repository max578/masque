# Unit tests for the rule engine (R/detect_rules.R) and candidate
# proposer (R/detect_candidates.R).

# Reach private symbols via masque:::.
.cands <- masque:::.propose_candidates
.rules <- masque:::.rules_all

# --- candidate proposer ------------------------------------------------------

test_that(".propose_candidates() includes factor type regardless of cardinality", {
  df <- data.frame(
    trt   = factor(rep(LETTERS[1:24], each = 3)),
    yield = rnorm(72),
    rep   = factor(rep(1:3, times = 24)),
    stringsAsFactors = FALSE
  )
  cands <- .cands(df)
  expect_true("trt" %in% cands$factors)
  expect_true("rep" %in% cands$factors)
  expect_false("yield" %in% cands$factors)
})

test_that(".propose_candidates() excludes unique-per-row columns", {
  df <- data.frame(id = 1:50, trt = factor(rep(1:5, each = 10)))
  cands <- .cands(df)
  expect_false("id" %in% cands$factors)
  expect_true( "trt" %in% cands$factors)
})

test_that(".propose_candidates() respects user-roled outcomes / ignores", {
  df <- data.frame(
    x     = factor(rep(1:5, each = 10)),
    y     = rnorm(50),
    other = factor(rep(c("a","b"), 25)),
    stringsAsFactors = FALSE
  )
  roles <- propose_roles(df, detect = FALSE)
  roles$role[roles$col == "x"]     <- "outcome"
  roles$role[roles$col == "other"] <- "ignore"
  cands <- .cands(df, roles = roles)
  expect_false("x"     %in% cands$factors)
  expect_false("other" %in% cands$factors)
})

test_that(".detect_spatial_pair() returns NULL without integer-named row+col", {
  df <- data.frame(
    rep = 1:9, row = 1:9, what = "x",
    stringsAsFactors = FALSE
  )
  expect_null(masque:::.detect_spatial_pair(df, names(df),
                                            sapply(df, masque:::col_kind)))
})

test_that(".detect_spatial_pair() finds row/col when both gridded", {
  df <- expand.grid(row = 1:4, col = 1:5)
  sp <- masque:::.detect_spatial_pair(df, names(df),
                                      sapply(df, masque:::col_kind))
  expect_equal(sp$row, "row")
  expect_equal(sp$col, "col")
  expect_equal(sp$n_row, 4L)
  expect_equal(sp$n_col, 5L)
})

# --- per-rule unit tests ----------------------------------------------------

test_that("rule_crd scores high on a balanced 1-factor design", {
  df <- data.frame(
    trt  = factor(rep(LETTERS[1:4], each = 10)),
    y    = rnorm(40),
    stringsAsFactors = FALSE
  )
  cands <- .cands(df)
  r <- .rules$CRD(df, cands)
  expect_equal(r$class_label, "CRD")
  expect_gte(r$score, 0.8)
})

test_that("rule_crd is demoted when a clear block exists", {
  df <- expand.grid(rep = 1:4, trt = factor(letters[1:5]))
  cands <- .cands(df)
  r <- .rules$CRD(df, cands)
  expect_lt(r$score, 0.5)
})

test_that("rule_rcbd requires a design-named block (would-be factorial rejected)", {
  # Two crossed treatments, neither named like a block.
  df <- expand.grid(supp = factor(c("VC","OJ")), dose = c(0.5, 1.0, 2.0))
  df <- df[rep(seq_len(nrow(df)), 10), ]
  cands <- .cands(df)
  r <- .rules$RCBD(df, cands)
  expect_equal(r$score, 0)
  expect_match(r$evidence$reason, "design-named|named-block",
               ignore.case = TRUE)
})

test_that("rule_rcbd scores high with a named block + balanced treatment", {
  df <- expand.grid(rep = 1:5, trt = factor(letters[1:4]))
  cands <- .cands(df)
  r <- .rules$RCBD(df, cands)
  expect_gte(r$score, 0.8)
  expect_equal(r$evidence$treatment_col, "trt")
  expect_equal(r$evidence$block_col, "rep")
})

test_that("rule_ibd_alpha finds the pairwise interaction (rep:block)", {
  skip_if_not_installed("agridat")
  d <- agridat::john.alpha
  cands <- .cands(d)
  r <- .rules$`IBD/alpha-lattice`(d, cands)
  expect_gte(r$score, 0.9)
  expect_setequal(r$evidence$block_basis, c("rep", "block"))
  expect_true(r$evidence$block_is_pairwise)
})

test_that("rule_row_column requires within-row/col balance, not just a grid", {
  # CRD with row/col coordinates -> grid present but trt unbalanced per row/col
  set.seed(1)
  df <- data.frame(
    trt = factor(sample(LETTERS[1:4], 32, replace = TRUE)),
    row = rep(1:4, times = 8),
    col = rep(1:8, each = 4)
  )
  cands <- .cands(df)
  r <- .rules$`row-column`(df, cands)
  # Score may be > 0 due to fill_pct base, but well below 0.85 ideal Latin.
  expect_lt(r$score, 0.85)
})

test_that("rule_split_plot needs a named block + 2 non-block-named factors", {
  # Only 1 non-block factor -> reject.
  df <- expand.grid(rep = 1:3, trt = factor(letters[1:4]))
  cands <- .cands(df)
  r <- .rules$`split-plot`(df, cands)
  expect_equal(r$score, 0)
})

test_that("rule_factorial excludes pairs where either factor is design-named", {
  df <- expand.grid(rep = 1:3, trt = factor(letters[1:4]))
  cands <- .cands(df)
  r <- .rules$factorial(df, cands)
  expect_equal(r$score, 0)            # rep is block_named -> excluded
})

test_that("rule_factorial scores high on a 2-treatment crossing", {
  df <- expand.grid(supp = factor(c("VC","OJ")), dose = c(0.5, 1.0, 2.0))
  df <- df[rep(seq_len(nrow(df)), 10), ]
  cands <- .cands(df)
  r <- .rules$factorial(df, cands)
  expect_gte(r$score, 0.7)
})
