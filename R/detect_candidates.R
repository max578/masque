# Candidate column sets for design detection.
#
# Pure (no message / no plotting); consumed by the rule engine
# (R/detect_rules.R). Reuses col_kind() and matches_pattern() from
# R/propose_roles.R.

# Propose candidate column sets for `detect_design()`.
#
# @param df    A data frame.
# @param roles Optional roles tibble (as returned by `propose_roles()`).
#              When provided, columns already roled `outcome` / `ignore` are
#              excluded from factor / numeric candidates, and any column
#              roled `treatment` is forced into `trt_user`.
#
# @return Named list with at minimum:
#   * `n_rows`, `cols`, `kinds`, `cardinality`
#   * `factors`   character — factor-like cols (factor / character / integer /
#                 logical with 2 <= cardinality <= ceiling(sqrt(n)))
#   * `numerics`  character — numeric / integer cols that are NOT factor-like
#                 (probable outcomes / numeric covariates)
#   * `spatial`   list(row, col, n_row, n_col) or NULL
#   * `trt_named` character — factor-like cols whose names match the
#                 treatment regex from `propose_roles()`
#   * `block_named` character — factor-like cols whose names match a
#                 design / block regex
#   * `trt_user`  character — columns the user has already roled as treatment
.propose_candidates <- function(df, roles = NULL) {
  n     <- nrow(df)
  cols  <- names(df)
  kinds <- vapply(df, col_kind, character(1L))

  cardinality <- vapply(df, function(x) length(unique(stats::na.omit(x))),
                        integer(1L))

  # Factor-like classification, tier-aware:
  #   * factor      -> always (no cardinality test)
  #   * logical     -> always (2 levels)
  #   * integer /
  #     numeric     -> cardinality 2..sqrt(n) (low-card integers are
  #                   plausible labels / dose levels; high-card integers
  #                   are measurements)
  #   * character   -> cardinality 2..n/2 (allow more — text labels like
  #                   variety names commonly exceed sqrt(n))
  half_n         <- max(2L, floor(n / 2L))
  small_card_cap <- max(2L, ceiling(sqrt(max(n, 1L))))

  is_factor_like <-
    (kinds == "factor") |
    (kinds == "logical" & cardinality >= 2L) |
    (kinds %in% c("integer", "numeric") &
       cardinality >= 2L & cardinality <= small_card_cap) |
    (kinds == "character" &
       cardinality >= 2L & cardinality <= half_n)

  # Honour user roles: outcomes and ignored never become factors here.
  if (!is.null(roles) && "role" %in% names(roles)) {
    drop_factors <- roles$col[roles$role %in% c("outcome", "ignore")]
    is_factor_like <- is_factor_like & !(cols %in% drop_factors)
  }

  factors  <- cols[is_factor_like]
  numerics <- cols[kinds %in% c("numeric", "integer") & !is_factor_like]

  # Convenience subset: block-sized factors (cardinality <= sqrt(n)).
  block_factors <- cols[is_factor_like & cardinality <= small_card_cap]

  trt_named <- cols[vapply(cols, matches_pattern, logical(1L),
                           pat = TREATMENT_PATTERN)]
  trt_named <- intersect(trt_named, factors)

  # Reuse propose_roles()'s DESIGN_PATTERN — covers rep, block, row, col,
  # range, plot, site, env, trial, year, season.
  block_named <- cols[vapply(cols, matches_pattern, logical(1L),
                             pat = DESIGN_PATTERN)]
  block_named <- intersect(block_named, factors)

  trt_user <- character(0L)
  if (!is.null(roles) && "role" %in% names(roles)) {
    trt_user <- roles$col[roles$role == "treatment"]
  }

  list(
    n_rows      = n,
    cols        = cols,
    kinds       = kinds,
    cardinality   = cardinality,
    factors       = factors,
    block_factors = block_factors,
    numerics      = numerics,
    spatial     = .detect_spatial_pair(df, cols, kinds),
    trt_named   = trt_named,
    block_named = block_named,
    trt_user    = trt_user
  )
}

# Look for an (integer-like, gridded) row + col / column / range pair.
.detect_spatial_pair <- function(df, cols, kinds) {
  row_like <- cols[grepl("^(row|range)$", cols, ignore.case = TRUE) &
                   kinds %in% c("integer", "numeric")]
  col_like <- cols[grepl("^(col|column)$", cols, ignore.case = TRUE) &
                   kinds %in% c("integer", "numeric")]

  if (length(row_like) == 0L || length(col_like) == 0L) {
    return(NULL)
  }

  r_nm <- row_like[1L]
  c_nm <- col_like[1L]
  rv   <- df[[r_nm]]
  cv   <- df[[c_nm]]

  if (!.is_integer_like(rv) || !.is_integer_like(cv)) return(NULL)

  nr <- length(unique(stats::na.omit(rv)))
  nc <- length(unique(stats::na.omit(cv)))
  if (nr < 2L || nc < 2L) return(NULL)

  list(row = r_nm, col = c_nm, n_row = nr, n_col = nc)
}

.is_integer_like <- function(x) {
  if (is.integer(x)) return(TRUE)
  if (is.numeric(x)) {
    no_na <- stats::na.omit(x)
    return(length(no_na) > 0L && all(no_na == round(no_na)))
  }
  FALSE
}
