# Numeric synthesis within each treatment-by-design stratum, so a model of
# outcome ~ treatment fitted on the clone recovers the real effect.

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
#' The stratum is chosen upstream by `.conditioning_ladder()`, which coarsens
#' the conditioning set until the cells are large enough.
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

# Internal: per-row stratum key from the treatment and retained design
# columns, on original values. No conditioning columns gives one stratum.
.conditioning_groups <- function(df, cond_cols) {
  cond_cols <- intersect(cond_cols, names(df))
  if (!length(cond_cols)) {
    return(rep("__all__", nrow(df)))
  }
  parts <- lapply(cond_cols, function(col) as.character(df[[col]]))
  do.call(paste, c(parts, list(sep = "\r")))
}

# Internal: resolve stratum labels into the strata synthesised. NA labels form
# their own key; strata below `min_stratum` merge into one fallback stratum.
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

# Internal: fraction of rows pooled into the fallback under a labelling
# (0: all conditioned; 1: the pooled clone).
.stratum_fallback_frac <- function(groups, min_stratum = 5L) {
  .resolve_strata(groups, min_stratum)$fallback_frac
}

#' The conditioning ladder
#'
#' Drops design columns one at a time, in the order `ladder` sets, until every
#' cell holds `min_stratum` rows. Treatment columns are never dropped: if the
#' treatment-only rung is still too small, the ladder stops there and reports
#' the fallback fraction. Under `"hierarchy"` each dropped column is also
#' listed in `shifted` for `.design_shifts()`.
#' @noRd
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
  # Fallback rows have lost their stratum, so under the hierarchy ladder the
  # stratum columns' main effects are carried for them as shifts too.
  shifted <- if (identical(ladder, "hierarchy")) {
    cand <- c(dropped, if (isTRUE(frac > 0)) used)
    cand <- cand[vapply(cand, function(cl) .shiftable(df[[cl]]), logical(1L))]
    c(cand, .nested_pairs(intersect(cand, dropped)))
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

# Mean share of each numeric column's sum of squares a column explains,
# adjusted for its number of levels and floored at 0.
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

# A column can carry a shift when two or more levels hold two or more rows;
# single-row levels are pooled by `.collapse_singletons()`.
.shiftable <- function(v) {
  tab <- table(as.character(v))
  sum(tab >= 2L) >= 2L
}

# Pairs of dropped blocking and environment columns, as "a:b" (rep R1 in one
# county is not R1 in another). Coordinates form no pairs.
.nested_pairs <- function(cols) {
  cols <- cols[!grepl(.COORD_PATTERN, cols, ignore.case = TRUE)]
  if (length(cols) < 2L) {
    return(character())
  }
  pairs <- utils::combn(cols, 2L, simplify = FALSE)
  vapply(pairs, paste, character(1L), collapse = ":")
}

# The factor a shift term names: a column, or the interaction of a pair.
.shift_term <- function(df, term) {
  parts <- strsplit(term, ":", fixed = TRUE)[[1L]]
  if (length(parts) == 1L) {
    return(df[[parts]])
  }
  interaction(lapply(df[parts], as.character), drop = TRUE, sep = ":")
}

# Levels with a single row share one pooled level, so the shift a row
# receives is never that row's own outcome.
.collapse_singletons <- function(v) {
  v <- as.character(v)
  tab <- table(v)
  single <- names(tab)[tab < 2L]
  v[v %in% single] <- ".singleton"
  factor(v)
}

#' Shifts for the dropped terms
#'
#' Per row and numeric column, the least-squares effect of each shifted term,
#' fitted beside the kept stratum. It is subtracted before the within-stratum
#' copula and added back after; a row missing any shifted term gets no shift.
#'
#' Blocking, environment and coordinate terms are shrunk by
#' `tau2 / (tau2 + sigma2 / m)`, with `tau2` the between-level variance of the
#' effects net of noise and `m` the rows per level. A stratum column shifted
#' for fallback rows carries its treatment means unshrunk.
#'
#' @returns A list: the shift matrix, the terms kept within the parameter
#'   budget, and per numeric column the factor `sqrt((n - 1) / (n - 1 - p))`
#'   that restores the error variance the fit removed (`p` counts the stratum
#'   and each term's degrees of freedom, weighted by its shrinkage).
#' @noRd
.design_shifts <- function(x_num, df, used, shifted) {
  shift <- matrix(
    0, nrow(x_num), ncol(x_num), dimnames = list(NULL, names(x_num))
  )
  inflate <- stats::setNames(rep(1, ncol(x_num)), names(x_num))
  none <- list(shift = shift, shifted = character(), inflate = inflate)
  if (!length(shifted) || !ncol(x_num) || nrow(x_num) < 3L) {
    return(none)
  }
  # The stratum enters the fit, except when a stratum column is itself
  # shifted (fallback rows), where it would absorb that effect.
  key <- factor(.conditioning_groups(df, used))
  with_stratum <- nlevels(key) >= 2L && !any(used %in% shifted)
  terms <- lapply(shifted, function(term) .shift_term(df, term))
  names(terms) <- shifted
  shifted <- shifted[vapply(terms, .shiftable, logical(1L))]
  n_fit <- min(vapply(x_num, function(y) sum(!is.na(y)), integer(1L)))
  # Over the parameter budget, pairs go first (last pair first), then
  # columns in the ladder's drop order.
  repeat {
    if (!length(shifted)) {
      return(none)
    }
    rhs <- lapply(terms[shifted], .collapse_singletons)
    if (with_stratum) {
      rhs <- c(list(.stratum = key), rhs)
    }
    rhs <- as.data.frame(rhs, check.names = FALSE, stringsAsFactors = FALSE)
    n_par <- 1L + sum(vapply(rhs, nlevels, integer(1L)) - 1L)
    if (n_par < n_fit) {
      break
    }
    is_pair <- grepl(":", shifted, fixed = TRUE)
    shifted <- if (any(is_pair)) {
      shifted[-max(which(is_pair))]
    } else {
      shifted[-1L]
    }
  }
  ok <- stats::complete.cases(rhs)
  form <- stats::as.formula(paste(
    "~", paste(sprintf("`%s`", names(rhs)), collapse = " + ")
  ))
  mm <- stats::model.matrix(form, data = rhs[ok, , drop = FALSE])
  term_of <- attr(mm, "assign")
  labels <- gsub("`", "", attr(stats::terms(form), "term.labels"), fixed = TRUE)
  shift_terms <- which(labels != ".stratum")
  n_lev <- vapply(rhs, nlevels, integer(1L))[labels]
  for (col in names(x_num)) {
    y <- x_num[[col]][ok]
    fit_rows <- !is.na(y)
    if (sum(fit_rows) <= ncol(mm)) next
    fit <- stats::lm.fit(mm[fit_rows, , drop = FALSE], y[fit_rows])
    beta <- fit$coefficients
    beta[is.na(beta)] <- 0
    sigma2 <- sum(fit$residuals^2) / max(sum(fit_rows) - fit$rank, 1L)
    p_eff <- if (with_stratum) nlevels(key) - 1 else 0
    for (t in shift_terms) {
      idx <- which(term_of == t)
      lambda <- if (labels[t] %in% used) {
        1
      } else {
        .shrinkage(c(0, beta[idx]), sigma2, sum(fit_rows) / n_lev[t])
      }
      shift[ok, col] <- shift[ok, col] +
        lambda * as.numeric(mm[, idx, drop = FALSE] %*% beta[idx])
      p_eff <- p_eff + lambda * (n_lev[t] - 1)
    }
    n <- sum(fit_rows)
    if (n - 1 > p_eff) {
      inflate[[col]] <- sqrt((n - 1) / (n - 1 - p_eff))
    }
  }
  list(shift = shift, shifted = shifted, inflate = inflate)
}

# Signal share of a term's level effects: between-level variance net of the
# noise `sigma2 / m`, over the between-level variance (0 noise, 1 strong).
.shrinkage <- function(effects, sigma2, m) {
  if (length(effects) < 2L || !is.finite(sigma2) || m <= 0) {
    return(0)
  }
  noise <- sigma2 / m
  tau2 <- max(0, stats::var(effects) - noise)
  if (tau2 <= 0) 0 else tau2 / (tau2 + noise)
}
