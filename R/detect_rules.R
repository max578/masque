# Rule engine for design detection.
#
# Each rule is a pure function with signature
#
#   .rule_X(df, cands) -> list(
#     class_label       = character(1),     # e.g. "RCBD"
#     score             = numeric(1) in [0, 1],
#     evidence          = named list,
#     recommended_roles: a data frame of col + role, or NULL
#   )
#
# The orchestrator (detect_design.R) runs all six and picks the max above
# a threshold.

# --- helpers ---------------------------------------------------------------

# Pick a working treatment column from the candidate set.
# Priority:
#   1. User-roled treatment column (if propose_roles() result was supplied).
#   2. Name-pattern treatment (treatment / variety / cultivar / genotype...).
#   3. Highest-cardinality non-block, non-spatial factor.
#   4. Fallback: first factor.
.pick_treatment <- function(cands) {
  if (length(cands$trt_user) > 0L) {
    return(cands$trt_user[1L])
  }
  if (length(cands$trt_named) > 0L) {
    return(cands$trt_named[1L])
  }

  spatial_cols <- if (is.null(cands$spatial)) {
    character(0L)
  } else {
    c(cands$spatial$row, cands$spatial$col)
  }
  not_block <- setdiff(
    cands$factors,
    c(cands$block_named, spatial_cols)
  )
  if (length(not_block) > 0L) {
    idx <- which.max(cands$cardinality[match(not_block, cands$cols)])
    return(not_block[idx])
  }
  if (length(cands$factors) > 0L) {
    return(cands$factors[1L])
  }
  NA_character_
}

# Per-(treatment, block) incidence counts; returns a contingency table.
.incidence <- function(df, trt, blk) {
  table(df[[blk]], df[[trt]], useNA = "no")
}

# Standard deviation guarded against length 1.
.sd0 <- function(x) {
  if (length(x) < 2L) 0 else stats::sd(x)
}

# --- rules -----------------------------------------------------------------

# Rule 1: Completely Randomised Design.
# One treatment factor; reasonably balanced replication; no block structure
# that splits each treatment uniquely.
.rule_crd <- function(df, cands) {
  trt <- .pick_treatment(cands)
  if (is.na(trt)) {
    return(list(
      class_label = "CRD", score = 0,
      evidence = list(reason = "no candidate treatment"),
      recommended_roles = NULL
    ))
  }

  reps <- table(df[[trt]], useNA = "no")
  if (length(reps) < 2L || min(reps) < 2L) {
    return(list(
      class_label = "CRD", score = 0,
      evidence = list(reason = "no replication"),
      recommended_roles = NULL
    ))
  }

  # Balance: small coefficient of variation in per-treatment counts.
  cv <- .sd0(as.numeric(reps)) / mean(as.numeric(reps))
  balance <- max(0, 1 - cv)

  # Penalise CRD if a candidate block factor exists that is well-balanced
  # against this treatment (i.e., RCBD-ish).
  candidate_blocks <- setdiff(cands$factors, trt)
  block_penalty <- 0
  for (b in candidate_blocks) {
    inc <- .incidence(df, trt, b)
    if (all(dim(inc) >= 2L) && all(inc >= 1L) && .sd0(as.numeric(inc)) == 0) {
      block_penalty <- 0.6 # looks like RCBD; CRD is unlikely
      break
    }
  }

  score <- max(0, balance - block_penalty)

  list(
    class_label = "CRD",
    score = score,
    evidence = list(
      treatment_col = trt,
      n_treatments = length(reps),
      reps_min = min(reps), reps_max = max(reps),
      balance = balance,
      block_penalty = block_penalty
    ),
    recommended_roles = data.frame(
      col = trt, role = "treatment",
      stringsAsFactors = FALSE
    )
  )
}

# Rule 2: Randomised Complete Blocks.
# Each treatment appears the same number of times in each block AND the
# block factor has a design-pattern name (rep / block / site / env /
# trial / year / season / row / col / range / plot). Without the name
# check, a 2-factor factorial would falsely fire here.
.rule_rcbd <- function(df, cands) {
  trt <- .pick_treatment(cands)
  if (is.na(trt)) {
    return(list(
      class_label = "RCBD", score = 0,
      evidence = list(reason = "no candidate treatment"),
      recommended_roles = NULL
    ))
  }

  blocks <- intersect(setdiff(cands$factors, trt), cands$block_named)
  if (length(blocks) == 0L) {
    return(list(
      class_label = "RCBD", score = 0,
      evidence = list(reason = "no design-named candidate block"),
      recommended_roles = NULL
    ))
  }

  best <- list(score = 0, block = NA_character_, evidence = list())
  for (b in blocks) {
    inc <- .incidence(df, trt, b)
    if (any(dim(inc) < 2L)) next
    if (any(inc == 0L)) next # incomplete
    constant_per_cell <- .sd0(as.numeric(inc)) == 0
    if (!constant_per_cell) next

    T_ <- ncol(inc)
    B_ <- nrow(inc)
    cell_n <- inc[1L, 1L]
    rows_covered <- T_ * B_ * cell_n
    coverage <- min(1, rows_covered / max(nrow(df), 1L))

    score <- min(1, 0.85 * coverage + 0.1) # +0.1 named-block

    if (score > best$score) {
      best <- list(
        score = score,
        block = b,
        evidence = list(
          treatment_col = trt, block_col = b,
          n_treatments = T_, n_blocks = B_,
          cell_n = cell_n, coverage = coverage
        )
      )
    }
  }

  if (best$score == 0) {
    return(list(
      class_label = "RCBD", score = 0,
      evidence = list(reason = "no balanced (treatment, named-block)"),
      recommended_roles = NULL
    ))
  }

  list(
    class_label = "RCBD",
    score = best$score,
    evidence = best$evidence,
    recommended_roles = data.frame(
      col = c(best$evidence$treatment_col, best$evidence$block_col),
      role = c("treatment", "design"),
      stringsAsFactors = FALSE
    )
  )
}

# Rule 3: Incomplete Block Design / alpha-lattice.
# Treatments appear in subsets of blocks; incidence is regular
# (constant block size k < T, constant replication r per treatment).
# Tries single factor blocks AND pairwise factor interactions, since
# alpha-lattice block labels are commonly reused across reps
# (the effective block is `rep:block`).
.rule_ibd_alpha <- function(df, cands) {
  trt <- .pick_treatment(cands)
  if (is.na(trt)) {
    return(list(
      class_label = "IBD/alpha-lattice", score = 0,
      evidence = list(reason = "no candidate treatment"),
      recommended_roles = NULL
    ))
  }

  blocks <- setdiff(cands$factors, trt)
  if (length(blocks) == 0L) {
    return(list(
      class_label = "IBD/alpha-lattice", score = 0,
      evidence = list(reason = "no candidate block"),
      recommended_roles = NULL
    ))
  }

  # Build candidate block vectors: each single factor, plus every pairwise
  # interaction of factors. Pairwise only (3+-way is rare and expensive).
  candidate_blocks <- list()
  for (b in blocks) {
    candidate_blocks[[b]] <- list(
      label    = b,
      vec      = df[[b]],
      basis    = b,
      pairwise = FALSE
    )
  }
  if (length(blocks) >= 2L) {
    pairs <- utils::combn(blocks, 2L, simplify = FALSE)
    for (pr in pairs) {
      lbl <- paste(pr, collapse = ":")
      candidate_blocks[[lbl]] <- list(
        label = lbl,
        vec = interaction(df[[pr[1L]]], df[[pr[2L]]],
          drop = TRUE, sep = ":"
        ),
        basis = pr,
        pairwise = TRUE
      )
    }
  }

  best <- list(score = 0, basis = character(0L), evidence = list())
  for (cb in candidate_blocks) {
    inc <- table(cb$vec, df[[trt]], useNA = "no")
    if (any(dim(inc) < 2L)) next

    T_ <- ncol(inc)
    B_ <- nrow(inc)
    if (B_ < 3L) next

    block_sizes <- rowSums(inc > 0L)
    rep_counts <- colSums(inc > 0L)

    k_constant <- .sd0(block_sizes) == 0
    r_constant <- .sd0(rep_counts) == 0
    k_ <- block_sizes[1L]
    r_ <- rep_counts[1L]

    if (!isTRUE(k_ < T_)) next
    if (k_ < 2L) next

    regularity <- (k_constant + r_constant) / 2
    incidence_check <- if (isTRUE(T_ * r_ == B_ * k_)) 0.15 else 0
    incomplete_room <- if (k_ / T_ < 0.9) 0.1 else 0
    name_bonus <- if (all(cb$basis %in% cands$block_named)) 0.1 else 0
    pair_bonus <- if (cb$pairwise) 0.05 else 0

    score <- min(
      1,
      0.65 * regularity + incomplete_room +
        name_bonus + incidence_check + pair_bonus
    )

    if (score > best$score) {
      best <- list(
        score = score,
        basis = cb$basis,
        evidence = list(
          treatment_col = trt,
          block_col = cb$label,
          block_basis = cb$basis,
          block_is_pairwise = cb$pairwise,
          n_treatments = T_, n_blocks = B_,
          k = k_, r = r_,
          k_constant = k_constant,
          r_constant = r_constant,
          incidence_balanced = isTRUE(T_ * r_ == B_ * k_)
        )
      )
    }
  }

  if (best$score == 0) {
    return(list(
      class_label = "IBD/alpha-lattice", score = 0,
      evidence = list(reason = "no regular incomplete block structure"),
      recommended_roles = NULL
    ))
  }

  rec_roles <- data.frame(
    col = c(best$evidence$treatment_col, best$basis),
    role = c("treatment", rep("design", length(best$basis))),
    stringsAsFactors = FALSE
  )

  list(
    class_label = "IBD/alpha-lattice",
    score = best$score,
    evidence = best$evidence,
    recommended_roles = rec_roles
  )
}

# Rule 4: Row-Column design.
# Spatial pair (row, col) exists AND treatment is structurally balanced
# WITHIN rows and WITHIN columns (Latin-square / Youden / row-column
# lattice signature). Bare presence of (row, col) is not enough -- it just
# means plot positions were recorded, which is also true of CRD trials.
.rule_row_column <- function(df, cands) {
  if (is.null(cands$spatial)) {
    return(list(
      class_label = "row-column", score = 0,
      evidence = list(reason = "no spatial pair"),
      recommended_roles = NULL
    ))
  }

  sp <- cands$spatial
  if (sp$n_row < 2L || sp$n_col < 2L) {
    return(list(
      class_label = "row-column", score = 0,
      evidence = list(reason = "degenerate grid"),
      recommended_roles = NULL
    ))
  }

  cells_filled <- nrow(unique(df[, c(sp$row, sp$col), drop = FALSE]))
  cells_total <- sp$n_row * sp$n_col
  fill_pct <- cells_filled / cells_total

  trt <- .pick_treatment(cands)
  if (is.na(trt)) {
    # Grid present but no treatment to balance against -> weak signal.
    return(list(
      class_label = "row-column",
      score = 0.3 * fill_pct,
      evidence = list(
        row_col = sp$row, col_col = sp$col,
        n_row = sp$n_row, n_col = sp$n_col,
        fill_pct = fill_pct,
        balance_note = "no treatment factor for balance check"
      ),
      recommended_roles = data.frame(
        col = c(sp$row, sp$col),
        role = c("design", "design"),
        stringsAsFactors = FALSE
      )
    ))
  }

  # Structural balance: in a true row-column design every treatment appears
  # the same number of times in every row, and the same in every column.
  cv <- function(m) {
    v <- as.numeric(m)
    if (length(v) == 0L || mean(v) == 0) {
      return(Inf)
    }
    .sd0(v) / mean(v)
  }
  inc_row <- table(df[[sp$row]], df[[trt]], useNA = "no")
  inc_col <- table(df[[sp$col]], df[[trt]], useNA = "no")
  row_balance <- max(0, 1 - cv(inc_row))
  col_balance <- max(0, 1 - cv(inc_col))

  score <- min(1, 0.3 * fill_pct + 0.35 * row_balance + 0.35 * col_balance)

  rec <- data.frame(
    col = c(sp$row, sp$col, trt),
    role = c("design", "design", "treatment"),
    stringsAsFactors = FALSE
  )

  list(
    class_label = "row-column",
    score = score,
    evidence = list(
      row_col      = sp$row,
      col_col      = sp$col,
      n_row        = sp$n_row,
      n_col        = sp$n_col,
      cells_filled = cells_filled,
      cells_total  = cells_total,
      fill_pct     = fill_pct,
      row_balance  = row_balance,
      col_balance  = col_balance
    ),
    recommended_roles = rec
  )
}

# Rule 5: Split-plot.
# A block B contains multiple whole-plot units, each holding all sub-plot
# levels. Identified by: B is a design-named factor; W and S are both
# treatment-like (NOT design-named); lw < ls; within each (B, W) cell,
# every S level appears exactly once.
.rule_split_plot <- function(df, cands) {
  if (length(cands$factors) < 3L) {
    return(list(
      class_label = "split-plot", score = 0,
      evidence = list(reason = "need >= 3 factor candidates"),
      recommended_roles = NULL
    ))
  }

  block_candidates <- cands$block_named
  trt_candidates <- setdiff(cands$factors, cands$block_named)
  if (length(block_candidates) == 0L || length(trt_candidates) < 2L) {
    return(list(
      class_label = "split-plot", score = 0,
      evidence = list(reason = "need a named block + 2 treatment factors"),
      recommended_roles = NULL
    ))
  }

  best <- list(score = 0)
  for (block_col in block_candidates) {
    trt_pairs <- utils::combn(trt_candidates, 2L, simplify = FALSE)
    for (pr in trt_pairs) {
      # Order so that the smaller-cardinality one is the whole-plot.
      cards <- cands$cardinality[match(pr, cands$cols)]
      if (cards[1L] == cards[2L]) next
      whole_col <- pr[which.min(cards)]
      sub_col <- pr[which.max(cards)]

      W <- df[[whole_col]]
      S <- df[[sub_col]]
      B <- df[[block_col]]
      lw <- length(unique(stats::na.omit(W)))
      ls <- length(unique(stats::na.omit(S)))
      lb <- length(unique(stats::na.omit(B)))
      if (lw < 2L || ls < 2L || lb < 2L) next

      # Defining split-plot signature: within each block, each whole-plot
      # level pairs with each sub-plot level exactly once.
      tbl <- table(W, S, B, useNA = "no")
      expected_cells <- lw * ls * lb
      filled <- sum(tbl > 0L)
      uniform <- .sd0(as.numeric(tbl[tbl > 0L])) == 0
      coverage <- filled / expected_cells

      score <- 0.6 * coverage + 0.3 * uniform + 0.1 # block was named
      score <- min(1, score)

      if (score > best$score) {
        best <- list(
          score = score,
          evidence = list(
            block_col = block_col,
            whole_plot_col = whole_col,
            sub_plot_col = sub_col,
            n_block = lb, n_whole = lw, n_sub = ls,
            coverage = coverage, uniform = uniform
          ),
          recommended_roles = data.frame(
            col = c(block_col, whole_col, sub_col),
            role = c("design", "treatment", "treatment"),
            stringsAsFactors = FALSE
          )
        )
      }
    }
  }

  if (best$score == 0) {
    return(list(
      class_label = "split-plot", score = 0,
      evidence = list(
        reason = "no consistent (block, whole-plot, sub-plot) trio"
      ),
      recommended_roles = NULL
    ))
  }

  list(
    class_label = "split-plot",
    score = best$score,
    evidence = best$evidence,
    recommended_roles = best$recommended_roles
  )
}

# Rule 6: Factorial.
# Two or more treatment-named (or at least non-block-named) factors are
# fully crossed and roughly balanced. Hard-excludes block-named factors:
# we explicitly require BOTH factors to look like treatments, otherwise
# a blocked single-treatment design would fire here.
.rule_factorial <- function(df, cands) {
  trt_like <- setdiff(cands$factors, cands$block_named)
  if (length(trt_like) < 2L) {
    return(list(
      class_label = "factorial", score = 0,
      evidence = list(reason = "need >= 2 non-block-named factors"),
      recommended_roles = NULL
    ))
  }

  best <- list(score = 0)
  pairs <- utils::combn(trt_like, 2L, simplify = FALSE)
  for (pr in pairs) {
    a <- pr[1L]
    b <- pr[2L]
    inc <- table(df[[a]], df[[b]], useNA = "no")
    if (any(dim(inc) < 2L)) next
    if (any(inc == 0L)) next # not fully crossed
    cv <- .sd0(as.numeric(inc)) / mean(as.numeric(inc))
    balance <- max(0, 1 - cv)
    reps <- as.integer(inc[1L, 1L])
    if (reps < 1L) next

    # Bonus when at least one factor is name-pattern treatment.
    name_bonus <- 0.1 * (a %in% cands$trt_named) +
      0.1 * (b %in% cands$trt_named)
    score <- min(1, 0.7 * balance + name_bonus)

    if (score > best$score) {
      best <- list(
        score = score,
        evidence = list(
          factor_a = a, factor_b = b,
          reps = reps, balance = balance,
          name_bonus = name_bonus
        ),
        recommended_roles = data.frame(
          col = c(a, b),
          role = c("treatment", "treatment"),
          stringsAsFactors = FALSE
        )
      )
    }
  }

  if (best$score == 0) {
    return(list(
      class_label = "factorial", score = 0,
      evidence = list(reason = "no fully-crossed balanced treatment-pair"),
      recommended_roles = NULL
    ))
  }

  list(
    class_label = "factorial",
    score = best$score,
    evidence = best$evidence,
    recommended_roles = best$recommended_roles
  )
}

# Ordered registry. Order matters for tie-breaking in detect_design().
.rules_all <- list(
  CRD                  = .rule_crd,
  RCBD                 = .rule_rcbd,
  `IBD/alpha-lattice`  = .rule_ibd_alpha,
  `row-column`         = .rule_row_column,
  `split-plot`         = .rule_split_plot,
  factorial            = .rule_factorial
)
