#' Candidate column sets for `detect_design()`
#'
#' @param df A data frame.
#' @param roles Optional roles table from `propose_roles()`. Columns roled as
#'   outcome, id, text or unsupported, or dropped, are left out of the
#'   candidates; a column roled `treatment` goes into `trt_user`.
#' @param revise If `TRUE` (the scoped path of `detect_design()`), outcome-
#'   pattern names and columns constant within a design unit leave the
#'   factors, and a treatment-pattern name is a treatment candidate whatever
#'   its cardinality. `FALSE` keeps the legacy candidate sets.
#' @returns A named list: `n_rows`, `cols`, `kinds`, `cardinality`, and the
#'   candidate sets `factors`, `numerics`, `spatial` (row and column
#'   coordinates, or `NULL`), `trt_named`, `block_named` and `trt_user`.
#'   With `revise = TRUE` it also holds `excluded`, the reason per column
#'   left out.
#' @noRd
.propose_candidates <- function(df, roles = NULL, revise = FALSE) {
  n <- nrow(df)
  cols <- names(df)
  kinds <- vapply(df, col_kind, character(1L))

  cardinality <- vapply(
    df, function(x) length(unique(stats::na.omit(x))),
    integer(1L)
  )

  # Factor-like: factors and logicals always; integer or numeric with 2 to
  # sqrt(n) values; character with 2 to n/2 (variety names often pass sqrt(n)).
  half_n <- max(2L, floor(n / 2L))
  small_card_cap <- max(2L, ceiling(sqrt(max(n, 1L))))

  in_small_range <- cardinality >= 2L & cardinality <= small_card_cap
  in_half_range <- cardinality >= 2L & cardinality <= half_n
  is_factor_like <-
    (kinds == "factor") |
      (kinds == "logical" & cardinality >= 2L) |
      (kinds %in% c("integer", "numeric") & in_small_range) |
      (kinds == "character" & in_half_range)

  # Columns roled outcome, id, text, unsupported or drop never become design
  # candidates (keep / ignore in roles tables from masque 0.5.0 and earlier).
  drop_candidates <- character(0L)
  if (!is.null(roles) && "role" %in% names(roles)) {
    drop_candidates <- roles$col[
      roles$role %in% c("outcome", "id", "text", "other", "keep", "ignore")
    ]
    if ("action" %in% names(roles)) {
      drop_candidates <- union(
        drop_candidates,
        roles$col[!is.na(roles$action) & roles$action == "drop"]
      )
    }
    is_factor_like <- is_factor_like & !(cols %in% drop_candidates)
  }

  excluded <- character(0L)
  if (revise) {
    excluded <- .excluded_candidates(df, cols[is_factor_like], roles)
    is_factor_like <- is_factor_like & !(cols %in% names(excluded))
  }

  factors <- cols[is_factor_like]
  numerics <- cols[
    kinds %in% c("numeric", "integer") &
      !is_factor_like &
      !(cols %in% drop_candidates)
  ]

  # Convenience subset: block-sized factors (cardinality <= sqrt(n)).
  block_factors <- cols[is_factor_like & cardinality <= small_card_cap]

  trt_named <- cols[vapply(cols, matches_pattern, logical(1L),
    pat = TREATMENT_PATTERN
  )]
  # Revised: a named treatment with many levels (an augmented trial) counts.
  named_ok <- if (revise) {
    cardinality >= 2L & cardinality < n &
      kinds %in% c(.categorical_kinds(), .numeric_kinds()) &
      !(cols %in% drop_candidates)
  } else {
    is_factor_like
  }
  trt_named <- intersect(trt_named, cols[named_ok])

  # Reuse propose_roles()'s DESIGN_PATTERN -- covers rep, block, row, col,
  # range, plot, site, env, trial, year, season.
  block_named <- cols[vapply(cols, matches_pattern, logical(1L),
    pat = DESIGN_PATTERN
  )]
  block_named <- intersect(block_named, factors)

  trt_user <- character(0L)
  if (!is.null(roles) && "role" %in% names(roles)) {
    trt_user <- roles$col[roles$role == "treatment"]
  }

  out <- list(
    n_rows = n,
    cols = cols,
    kinds = kinds,
    cardinality = cardinality,
    factors = factors,
    block_factors = block_factors,
    numerics = numerics,
    spatial = .detect_spatial_pair(df, cols, kinds),
    trt_named = trt_named,
    block_named = block_named,
    trt_user = trt_user
  )
  if (revise) {
    out$excluded <- excluded
  }
  out
}

# Factor candidates that are covariates, as a named vector of reasons: an
# outcome-pattern name, or one value per unit of a design column.
.excluded_candidates <- function(df, candidates, roles = NULL) {
  units <- .design_unit_cols(df, roles)
  user_treatment <- character(0L)
  if (!is.null(roles) && all(c("col", "role") %in% names(roles))) {
    user_treatment <- roles$col[roles$role == "treatment"]
  }
  protected <- union(units, user_treatment)
  out <- character(0L)
  for (col in setdiff(candidates, protected)) {
    if (matches_pattern(col, TREATMENT_PATTERN) ||
      matches_pattern(col, DESIGN_PATTERN)) {
      next
    }
    if (matches_pattern(col, OUTCOME_PATTERN)) {
      out[[col]] <- "outcome-pattern name"
      next
    }
    unit <- .constant_within_unit(df, col, setdiff(units, col))
    if (!is.na(unit)) {
      out[[col]] <- sprintf("one value per level of design column %s", unit)
    }
  }
  out
}

# Design-pattern names and columns roled design (the roles table wins) with at
# least two levels and two rows per level on average.
.design_unit_cols <- function(df, roles = NULL, extra = character(0L)) {
  cols <- names(df)
  design <- cols[matches_pattern(cols, DESIGN_PATTERN)]
  if (!is.null(roles) && all(c("col", "role") %in% names(roles))) {
    dropped <- if ("action" %in% names(roles)) {
      roles$col[!is.na(roles$action) & roles$action == "drop"]
    } else {
      character(0L)
    }
    design <- union(
      setdiff(design, roles$col[roles$role != "design"]),
      roles$col[roles$role == "design"]
    )
    design <- setdiff(design, dropped)
  }
  design <- intersect(union(design, extra), cols)
  replicated <- vapply(design, function(col) {
    x <- df[[col]]
    n_levels <- data.table::uniqueN(x, na.rm = TRUE)
    n_levels >= 2L && sum(!is.na(x)) >= 2L * n_levels
  }, logical(1L))
  design[replicated]
}

# The first unit column within whose every level `col` takes at most one
# non-missing value, or NA when there is none.
.constant_within_unit <- function(df, col, units) {
  for (unit in units) {
    pairs <- .unit_value_pairs(df, col, unit)
    if (nrow(pairs) > 0L &&
      data.table::uniqueN(pairs, by = c("unit", "value")) ==
        data.table::uniqueN(pairs, by = "unit")) {
      return(unit)
    }
  }
  NA_character_
}

# Crossed: some value of `col` in two or more units, and some unit holding two
# or more values.
.crossed_with_unit <- function(df, col, unit) {
  pairs <- .unit_value_pairs(df, col, unit)
  n_pairs <- data.table::uniqueN(pairs, by = c("unit", "value"))
  n_pairs > data.table::uniqueN(pairs, by = "unit") &&
    n_pairs > data.table::uniqueN(pairs, by = "value")
}

# Complete (unit, value) rows for one candidate and one unit column.
.unit_value_pairs <- function(df, col, unit) {
  pairs <- data.frame(
    unit = df[[unit]], value = df[[col]], stringsAsFactors = FALSE
  )
  pairs[stats::complete.cases(pairs), , drop = FALSE]
}

# Look for an (integer-like, gridded) row + col / column / range pair.
.detect_spatial_pair <- function(df, cols, kinds) {
  row_like <- cols[
    grepl("^(row|range)$", cols, ignore.case = TRUE) &
      kinds %in% c("integer", "numeric")
  ]
  col_like <- cols[
    grepl("^(col|column)$", cols, ignore.case = TRUE) &
      kinds %in% c("integer", "numeric")
  ]

  if (length(row_like) == 0L || length(col_like) == 0L) {
    return(NULL)
  }

  r_nm <- row_like[1L]
  c_nm <- col_like[1L]
  rv <- df[[r_nm]]
  cv <- df[[c_nm]]

  if (!.is_integer_like(rv) || !.is_integer_like(cv)) {
    return(NULL)
  }

  nr <- length(unique(stats::na.omit(rv)))
  nc <- length(unique(stats::na.omit(cv)))
  if (nr < 2L || nc < 2L) {
    return(NULL)
  }

  list(row = r_nm, col = c_nm, n_row = nr, n_col = nc)
}

.is_integer_like <- function(x) {
  if (is.integer(x)) {
    return(TRUE)
  }
  if (is.numeric(x)) {
    no_na <- stats::na.omit(x)
    return(length(no_na) > 0L && all(no_na == round(no_na)))
  }
  FALSE
}
