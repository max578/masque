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

# Internal: the conditioning ladder. Drops design columns one at a time,
# in the order `ladder` sets (`.order_by_levels()` or
# `.order_by_hierarchy()`), until every cell holds `min_stratum` rows.
# Treatment columns are never dropped: if the treatment-only rung is still
# below the floor the ladder stops there and reports the residual fallback
# fraction. Under "hierarchy" every dropped column is also listed in
# `shifted`, for `.design_shifts()`.
.conditioning_ladder <- function(df, cond_cols, protect_cols,
                                 min_stratum = 5L, ladder = "levels",
                                 x_num = NULL) {
  cond_cols <- intersect(names(df), cond_cols)
  protect <- intersect(cond_cols, protect_cols)
  droppable <- setdiff(cond_cols, protect)
  if (length(droppable) > 1L) {
    droppable <- if (identical(ladder, "hierarchy")) {
      .order_by_hierarchy(df, droppable, x_num)
    } else {
      .order_by_levels(df, droppable)
    }
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
  dropped <- setdiff(droppable, used)
  shifted <- if (identical(ladder, "hierarchy")) {
    dropped[vapply(dropped, function(cl) {
      length(unique(stats::na.omit(as.character(df[[cl]])))) >= 2L
    }, logical(1L))]
  } else {
    character()
  }

  list(
    used          = used,
    dropped       = dropped,
    shifted       = shifted,
    fallback_frac = frac,
    min_stratum   = as.integer(min_stratum),
    groups        = .conditioning_groups(df, used)
  )
}

.order_by_levels <- function(df, cols) {
  n_lev <- vapply(cols, function(cl) {
    length(unique(as.character(df[[cl]])))
  }, integer(1))
  cols[order(-n_lev, match(cols, names(df)))]
}

# Column names read as a plot coordinate or as an environment. Anything
# else in the conditioning set is a blocking column.
.COORD_PATTERN <- "^(row|col|column|range|plot|plotno|x|y)$"
.ENV_PATTERN <- paste0(
  "^(env|environment|site|loc|location|year|season|county|region|state|",
  "trial|site_?year|loc_?year)$"
)

.order_by_hierarchy <- function(df, cols, x_num = NULL) {
  tier <- ifelse(
    grepl(.COORD_PATTERN, cols, ignore.case = TRUE), 1L,
    ifelse(grepl(.ENV_PATTERN, cols, ignore.case = TRUE), 3L, 2L)
  )
  n_lev <- vapply(cols, function(cl) {
    length(unique(as.character(df[[cl]])))
  }, integer(1))
  eta2 <- .variance_explained(df, cols, x_num)
  # Coordinates: finest first. Blocks and environments: least explained
  # variance first. Ties by column order.
  key <- ifelse(tier == 1L, -n_lev, eta2)
  cols[order(tier, key, match(cols, names(df)))]
}

# Mean over the numeric block of the share of each numeric column's sum of
# squares that a conditioning column explains, adjusted for its number of
# levels (twelve null blocks explain a sixth of the variance by chance)
# and floored at 0. 0 when there is no numeric block to explain.
.variance_explained <- function(df, cols, x_num = NULL) {
  if (is.null(x_num) || !ncol(x_num) || !nrow(x_num)) {
    return(stats::setNames(rep(0, length(cols)), cols))
  }
  vapply(cols, function(cl) {
    g <- as.character(df[[cl]])
    share <- vapply(x_num, function(y) {
      ok <- !is.na(y) & !is.na(g)
      n <- sum(ok)
      if (n < 3L) return(0)
      y <- y[ok]
      ss_tot <- sum((y - mean(y))^2)
      if (ss_tot <= 0) return(0)
      mu <- tapply(y, g[ok], mean)
      nn <- tapply(y, g[ok], length)
      k <- length(mu)
      if (k >= n) return(0)
      eta2 <- sum(nn * (mu - mean(y))^2) / ss_tot
      max(0, 1 - (1 - eta2) * (n - 1) / (n - k))
    }, numeric(1))
    mean(share)
  }, numeric(1))
}

# Internal: per row and numeric column, the least-squares main effect of
# each dropped design column, estimated beside the kept stratum. Subtracted
# before the within-stratum copula and added back after it. A row with a
# missing value in any dropped column gets a zero shift.
.design_shifts <- function(x_num, df, used, shifted) {
  shift <- matrix(
    0, nrow(x_num), ncol(x_num), dimnames = list(NULL, names(x_num))
  )
  if (!length(shifted) || !ncol(x_num) || nrow(x_num) < 3L) {
    return(shift)
  }
  rhs <- lapply(df[shifted], function(v) factor(as.character(v)))
  names(rhs) <- shifted
  key <- factor(.conditioning_groups(df, used))
  if (nlevels(key) >= 2L) {
    rhs <- c(list(.stratum = key), rhs)
  }
  rhs <- as.data.frame(rhs, check.names = FALSE, stringsAsFactors = FALSE)
  ok <- stats::complete.cases(rhs)
  if (sum(ok) < 3L) {
    return(shift)
  }
  form <- stats::as.formula(paste(
    "~", paste(sprintf("`%s`", names(rhs)), collapse = " + ")
  ))
  mm <- stats::model.matrix(form, data = rhs[ok, , drop = FALSE])
  term_of <- attr(mm, "assign")
  labels <- attr(stats::terms(form), "term.labels")
  is_shift <- term_of > 0L & labels[pmax(term_of, 1L)] != ".stratum"
  if (!any(is_shift)) {
    return(shift)
  }
  for (col in names(x_num)) {
    y <- x_num[[col]][ok]
    fit_rows <- !is.na(y)
    if (sum(fit_rows) <= ncol(mm)) next
    beta <- stats::lm.fit(mm[fit_rows, , drop = FALSE], y[fit_rows])$coefficients
    beta[is.na(beta)] <- 0
    shift[ok, col] <- as.numeric(mm[, is_shift, drop = FALSE] %*% beta[is_shift])
  }
  shift
}
