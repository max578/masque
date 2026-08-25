# synthesise_numeric_conditional.R -- Stratified numeric synthesis that
# preserves the conditional treatment -> outcome map.
#
# The default numeric path (synthesise_numeric_local) draws from one
# global Gaussian copula fitted on the pooled covariance. That preserves
# marginals and the global covariance, but it severs the treatment ->
# outcome relationship: outcomes are simulated independently of which
# treatment a row carries, and treatment labels are relabelled by a
# separate permutation. A causal model fitted on such a clone recovers a
# null effect even when the real data carry a strong one.
#
# This file fits and samples the copula *within each conditioning
# stratum* (the cross of treatment and design columns), so the synthetic
# outcomes inherit each stratum's own mean and spread. The synthetic
# rows stay in their original stratum positions, and treatment relabelling
# is bijective, so a model of outcome ~ treatment fitted on the clone
# recovers the real effect within sampling tolerance -- the same idea as
# preserving a conditional mean embedding rather than a pooled marginal.

#' Conditional Gaussian-copula synthesis for numeric columns
#'
#' Re-simulates the numeric block one conditioning stratum at a time.
#' Each stratum is the set of rows sharing a value across the supplied
#' conditioning columns (treatment plus retained design columns); within
#' a stratum the numeric columns are drawn jointly from a stratum-local
#' Gaussian copula (via `synthesise_numeric_local()`). Rows are written
#' back into their original positions, so a row's synthetic outcome stays
#' attached to the same treatment that row carries. The pooled marginal
#' and global covariance are no longer matched exactly; what is preserved
#' instead is the per-stratum conditional distribution, and therefore the
#' treatment-to-outcome map a causal model reads.
#'
#' Strata too small to fit a stratum-local copula (fewer than
#' `min_stratum` rows) are pooled into a single fallback stratum that is
#' synthesised globally, so the call never fails on a sparse cell. The
#' fallback rows still receive synthetic values; only their conditional
#' fidelity degrades gracefully toward the pooled behaviour.
#'
#' The stratum this function is handed is chosen upstream by
#' `.conditioning_ladder()`, which coarsens the conditioning set until the
#' cells are large enough rather than letting a fine cross fall wholesale
#' into the fallback. This function is therefore the last rung of that
#' ladder, not the first line of defence.
#'
#' @param x_num A data frame whose columns are all numeric or integer
#'   (the scrambled numeric block).
#' @param groups A factor or character vector of length `nrow(x_num)`
#'   giving each row's conditioning stratum. Built by [mask()] from the
#'   treatment and retained design columns.
#' @param min_stratum Integer scalar. Strata with fewer than this many
#'   non-empty rows are pooled into the global fallback stratum. Defaults
#'   to `5L`; a stratum of one or two rows cannot support an empirical
#'   marginal, let alone a copula.
#'
#' @returns A data frame with the same column names, types, and row order
#'   as `x_num`, holding the stratified synthetic values.
#' @keywords internal
#' @noRd
synthesise_numeric_conditional <- function(x_num, groups, min_stratum = 5L) {
  if (!is.data.frame(x_num)) {
    cli::cli_abort("`x_num` must be a data frame.")
  }
  if (length(groups) != nrow(x_num)) {
    cli::cli_abort(
      "`groups` must have one entry per row of `x_num`."
    )
  }
  if (ncol(x_num) == 0L || nrow(x_num) == 0L) {
    return(x_num)
  }

  # Resolve strata and pool the ones too small to synthesise on their own.
  grp <- .resolve_strata(groups, min_stratum)$strata

  # Synthesise each stratum in place ------------------------------------
  out <- x_num
  for (g in unique(grp)) {
    rows <- which(grp == g)
    block <- x_num[rows, , drop = FALSE]
    synth_block <- synthesise_numeric_local(block, n = length(rows))
    for (col in names(out)) {
      out[[col]][rows] <- synth_block[[col]]
    }
  }

  # Integer storage class survives the per-stratum assembly above only
  # when every stratum kept it; restore it once, globally, to be safe.
  for (j in seq_along(out)) {
    if (is.integer(x_num[[j]])) {
      out[[j]] <- as.integer(round(out[[j]]))
    }
  }

  out
}

# Internal: build the per-row conditioning stratum label from the
# treatment and retained design columns.
#
# The stratum is the interaction of every conditioning column, encoded as
# a single character key. Conditioning columns absent from the data
# (none survived, or none were nominated) yield a single "all rows"
# stratum, in which case the conditional path collapses to the global
# copula and the caller can fall back cleanly. The labels here are the
# *original* values; because treatment relabelling later is bijective,
# the stratum identity is unchanged by it.
.conditioning_groups <- function(df, cond_cols) {
  cond_cols <- intersect(cond_cols, names(df))
  if (!length(cond_cols)) {
    return(rep("__all__", nrow(df)))
  }
  parts <- lapply(cond_cols, function(col) as.character(df[[col]]))
  do.call(paste, c(parts, list(sep = "\r")))
}

# Internal: resolve a vector of stratum labels into the strata actually
# synthesised, and report how many rows lost their own stratum on the way.
#
# A row whose group label is NA cannot be pooled into a real stratum, so
# it is keyed separately; that key is then subject to the same size test
# as any other. Strata below `min_stratum` are merged into one fallback
# stratum, which is synthesised from its own pooled rows.
.resolve_strata <- function(groups, min_stratum = 5L) {
  grp <- as.character(groups)
  if (!length(grp)) {
    return(list(strata = grp, fallback_frac = 0))
  }
  grp[is.na(grp)] <- ".__na_group__"
  counts <- table(grp)
  small <- names(counts)[counts < min_stratum]
  is_fallback <- grp %in% small
  grp[is_fallback] <- ".__fallback__"
  list(strata = grp, fallback_frac = mean(is_fallback))
}

# Internal: the fraction of rows that would be pooled into the fallback
# under a given stratum labelling. 0 means every row is conditioned on its
# own stratum; 1 means the conditional clone is the pooled clone.
.stratum_fallback_frac <- function(groups, min_stratum = 5L) {
  .resolve_strata(groups, min_stratum)$fallback_frac
}

# Internal: the conditioning ladder.
#
# The finest conditioning set -- treatment crossed with every retained
# design column -- is the one a caller means by `conditional = TRUE`, but
# on a replicated factorial it is also the one that puts a single row in
# every cell. Pooling that wholesale hands back the marginal clone under a
# conditional label. Instead, coarsen: drop design columns one at a time,
# finest first, until the cells reach `min_stratum`.
#
# Two rules govern the ladder:
#
#   * Treatment columns are never dropped. They carry the assignment whose
#     effect the conditional clone exists to preserve, so if even the
#     treatment-only rung leaves cells below `min_stratum` the ladder stops
#     there and reports the residual fallback fraction rather than
#     conditioning on nothing.
#   * Design columns are dropped in decreasing order of distinct values.
#     The finest column is the one fragmenting the cells, and dropping it
#     buys the largest gain in cell size per unit of conditional structure
#     given up. Ties are broken by column order, so the ladder is
#     deterministic.
#
# Coarsening can only merge cells, so the fallback fraction is
# non-increasing down the ladder: the first rung that reaches zero is also
# the finest one that does.
#
# Returns the rung used, the columns given up, the fallback fraction at
# that rung, and the row-wise stratum labels it implies.
.conditioning_ladder <- function(df, cond_cols, protect_cols,
                                 min_stratum = 5L) {
  cond_cols <- intersect(names(df), cond_cols)
  protect <- intersect(cond_cols, protect_cols)
  droppable <- setdiff(cond_cols, protect)
  if (length(droppable) > 1L) {
    n_lev <- vapply(droppable, function(cl) {
      length(unique(as.character(df[[cl]])))
    }, integer(1))
    droppable <- droppable[order(-n_lev, match(droppable, names(df)))]
  }

  used <- cond_cols
  frac <- NA_real_
  for (k in seq_len(length(droppable) + 1L)) {
    kept <- if (k == 1L) droppable else droppable[-seq_len(k - 1L)]
    used <- intersect(names(df), c(protect, kept))
    frac <- .stratum_fallback_frac(
      .conditioning_groups(df, used), min_stratum
    )
    if (frac <= 0) {
      break
    }
  }

  list(
    used          = used,
    dropped       = setdiff(cond_cols, used),
    fallback_frac = frac,
    min_stratum   = as.integer(min_stratum),
    groups        = .conditioning_groups(df, used)
  )
}
