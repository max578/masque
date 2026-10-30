#' Internal: build the audit data.table for a (df, synth, recipe, mode) tuple
#'
#' Called by `mask()` in `collaborate` mode and by `audit_mask()` on demand.
#' Returns a data.table with one row per column of the original data frame;
#' the table-level checks sit in its `"joint"` attribute.
#'
#' @keywords internal
#' @noRd
.compute_audit <- function(df, synth, rec, mode, linked = character()) {
  cols <- rec@roles$col
  has_action <- "action" %in% names(rec@roles)
  # Columns coarsened in place by the geomask. Retained, but displaced and
  # site-grouped, so they are not "kept as-is".
  coarsened <- unlist(lapply(rec@coords, function(cr) c(cr$lat, cr$lon)),
                      use.names = FALSE)
  if (is.null(coarsened)) coarsened <- character()
  na_pattern_uniq <- .global_na_pattern_uniqueness(df)
  strata <- .audit_strata(df, rec)
  design_cols <- intersect(
    rec@roles$col[rec@roles$role == "design"], names(df)
  )

  rows <- lapply(cols, function(col) {
    i <- which(rec@roles$col == col)
    role <- rec@roles$role[i]
    kind <- rec@roles$kind[i]
    action <- if (has_action) rec@roles$action[i] else NA_character_
    pii <- isTRUE(rec@roles$pii_suspected[i])

    in_synth <- col %in% names(synth)
    map <- rec@level_maps[[col]]
    alias_status <- if (!in_synth) {
      "dropped"
    } else if (is.null(map)) {
      "passthrough"
    } else if (length(map) > 0L && all(unname(map) %in% names(map))) {
      # A permutation maps the vocabulary onto itself: the labels moved,
      # but every real label is still visible.
      "permuted"
    } else {
      "aliased"
    }

    n <- nrow(df)
    x <- df[[col]]
    two_valued <- kind %in% .numeric_kinds() &&
      length(unique(x[!is.na(x)])) == 2L

    exact_match_pct <- NA_real_
    comparable_n <- NA_integer_
    if (in_synth && kind %in% c("numeric", "integer")) {
      y <- synth[[col]]
      comparable <- !is.na(x) & !is.na(y)
      comparable_n <- as.integer(sum(comparable))
      if (comparable_n > 0L) {
        matched <- comparable & (x == y)
        exact_match_pct <- 100 * sum(matched) / comparable_n
      }
    }

    # Same-row match against a permutation baseline: categorical, date and
    # two-valued columns, compared in the original label space.
    same <- NULL
    if (in_synth && (two_valued ||
      kind %in% c(.categorical_kinds(), .date_kinds()))) {
      groups <- if (two_valued && .audit_numeric_resimulated(action)) {
        strata
      }
      same <- .same_row_stats(
        x, synth[[col]], map,
        groups = groups,
        units = .constant_unit(x, df, setdiff(design_cols, col))
      )
    }

    n_unique_levels <- NA_integer_
    freq_min <- NA_integer_
    if (kind %in% c("factor", "character", "logical")) {
      x_clean <- x[!is.na(x)]
      n_unique_levels <- length(unique(x_clean))
      tbl <- table(x_clean)
      freq_min <- if (length(tbl)) as.integer(min(tbl)) else NA_integer_
    }

    na_pct <- 100 * sum(is.na(x)) / n

    is_coarsened <- col %in% coarsened
    leakage_class <- .classify_leakage(
      role = role, kind = kind, action = action, pii = pii, mode = mode,
      in_synth = in_synth, alias_status = alias_status,
      exact_match_pct = exact_match_pct, freq_min = freq_min,
      n_unique_levels = n_unique_levels, n_rows = n,
      coarsened = is_coarsened,
      same_row_excess = if (is.null(same)) NA_real_ else same$excess,
      same_row_sd = if (is.null(same)) NA_real_ else same$sd,
      two_valued = two_valued, linked = col %in% linked
    )

    notes <- .audit_notes(
      role, kind, action, pii, alias_status, mode, leakage_class,
      exact_match_pct, freq_min, coarsened = is_coarsened,
      same = if (col %in% linked) NULL else same, two_valued = two_valued
    )

    data.table::data.table(
      col                    = col,
      role                   = role,
      action                 = if (is.na(action)) "" else action,
      kind                   = kind,
      leakage_class          = leakage_class,
      n_unique_levels        = n_unique_levels,
      freq_min               = freq_min,
      exact_match_pct        = exact_match_pct,
      comparable_n           = comparable_n,
      na_pct                 = na_pct,
      na_pattern_uniqueness  = na_pattern_uniq,
      alias_status           = alias_status,
      notes                  = notes,
      same_row_pct           = if (is.null(same)) NA_real_ else same$observed,
      baseline_pct           = if (is.null(same)) NA_real_ else same$baseline,
      excess_pct             = if (is.null(same)) NA_real_ else same$excess
    )
  })

  audit <- data.table::rbindlist(rows)
  joint <- .joint_audit(df, synth, rec, mode, audit, linked, strata)
  data.table::setattr(audit, "joint", joint)
  audit
}

# Thresholds of the excess-over-chance rules, in percentage points of rows
# (cells for the rarity check). A finding needs both the absolute excess and
# `z` standard deviations of the permutation null, so a small table's chance
# swings are not graded. Calibrated on 20 seeds, conditional and not, of
# collaborate clones of agridat::john.alpha, a 6-trial MET and a 200-row
# clinical table: ordinary clones peaked at 9.5 points (z 3.1) per column, 0
# points jointly and 2.8 cells (z 1.9) for rare crosses; leaky clones (kept
# outcome, kept binary outcome, kept visible crosses) reached 42.7 points
# (z 15.7) jointly and 8.8 cells (z 6.0).
.AUDIT_THRESHOLDS <- list(
  same_row_medium = list(excess = 10, z = 4),
  joint_medium = list(excess = 5, z = 4),
  joint_high = list(excess = 20, z = 4),
  rare_medium = list(excess = 1, z = 3),
  rare_high = list(excess = 3, z = 4)
)

# Permutations drawn for each table-level baseline, and the fixed seed they
# are drawn under (the caller's RNG state is restored afterwards).
.AUDIT_PERMUTATIONS <- 20L
.AUDIT_SEED <- 160L

# TRUE when an excess clears a threshold pair; NA never does.
.excess_clears <- function(excess, sd, rule) {
  isTRUE(is.finite(excess) && excess >= rule$excess &&
    excess >= rule$z * sd)
}

# A scrambled numeric column is re-simulated through the copula, within the
# conditioning strata when the clone is conditional.
.audit_numeric_resimulated <- function(action) {
  is.na(action) || !nzchar(action) || action == "scramble"
}

# Row strata of a conditional clone (an integer id per row), else NULL.
.audit_strata <- function(df, rec) {
  if (!isTRUE(rec@conditional)) {
    return(NULL)
  }
  used <- intersect(rec@conditioning_used, names(df))
  if (!length(used)) {
    return(NULL)
  }
  .row_group_id(df[used])
}

# Dense integer id of each row's combination of the columns in `cols` (a list
# or data frame); NA is a value like any other.
.row_group_id <- function(cols) {
  codes <- lapply(cols, function(x) match(x, unique(x)))
  data.table::frankv(codes, ties.method = "dense")
}

# For each row of `cand`, whether the same combination occurs in `ref`; both
# hold integer codes in the same columns.
.rows_found <- function(cand, ref) {
  n_ref <- nrow(ref)
  ids <- data.table::frankv(
    data.table::rbindlist(list(ref, cand)), ties.method = "dense"
  )
  ids[n_ref + seq_len(nrow(cand))] %in% ids[seq_len(n_ref)]
}

# Combinations held by exactly one row of `cand` and exactly one row of `ref`.
.singleton_overlap <- function(cand, ref) {
  n_ref <- nrow(ref)
  ids <- data.table::frankv(
    data.table::rbindlist(list(ref, cand)), ties.method = "dense"
  )
  k <- max(ids)
  in_ref <- tabulate(ids[seq_len(n_ref)], k)
  in_cand <- tabulate(ids[n_ref + seq_len(nrow(cand))], k)
  sum(in_cand == 1L & in_ref == 1L)
}

# The coarsest replicated design unit within which `x` takes one value, as an
# integer id per row; NULL when `x` varies within every design column. Such a
# column carries one value per unit, so its chance matches move unit by unit.
.constant_unit <- function(x, df, design_cols) {
  best <- NULL
  best_units <- Inf
  for (dc in design_cols) {
    u <- .row_group_id(list(df[[dc]]))
    n_units <- max(u)
    if (n_units >= best_units || n_units * 2L > length(x)) next
    distinct <- tapply(x, u, function(v) length(unique(v[!is.na(v)])))
    if (all(distinct <= 1L)) {
      best <- u
      best_units <- n_units
    }
  }
  best
}

# Same-row match share of a clone column, its chance share under a random
# permutation of the original (within `groups` when given), the excess and a
# binomial SD of the chance share, counted in `units` when the column is
# constant within them.
.same_row_stats <- function(x, y, map, groups = NULL, units = NULL) {
  x_cmp <- if (is.null(map)) .audit_values(x) else as.character(x)
  y_cmp <- .audit_values(.audit_original_space(y, map))
  comparable <- !is.na(x_cmp) & !is.na(y)
  m <- sum(comparable)
  if (m == 0L) {
    return(NULL)
  }
  matched <- comparable & !is.na(y_cmp) & x_cmp == y_cmp
  observed <- 100 * sum(matched) / m

  # Chance share: sum over groups of n_gk^2 / n_g, over the comparable rows.
  g <- if (is.null(groups)) {
    rep(1L, m)
  } else {
    .row_group_id(list(groups[comparable]))
  }
  pair <- .row_group_id(list(g, x_cmp[comparable]))
  pair_n <- tabulate(pair)
  pair_group <- g[match(seq_along(pair_n), pair)]
  chance <- sum(pair_n^2 / tabulate(g)[pair_group]) / m

  m_eff <- if (is.null(units)) m else length(unique(units[comparable]))
  sd <- 100 * sqrt(chance * (1 - chance) / m_eff)
  list(
    observed = observed, baseline = 100 * chance,
    excess = observed - 100 * chance, sd = sd
  )
}

# Values comparable by equality: numbers stay numbers, the rest characters.
.audit_values <- function(x) {
  if (is.numeric(x) && !is.factor(x)) {
    return(as.numeric(x))
  }
  as.character(x)
}

# A clone column read back into the original label space through its map.
.audit_original_space <- function(y, map) {
  if (is.null(map)) {
    return(y)
  }
  inv <- stats::setNames(names(map), unname(map))
  unname(inv[as.character(y)])
}

# Table-level checks an adversary would run, each against a permutation
# baseline: same-row and whole-row joint matches over the retained content
# columns, singleton crosses of visible categorical labels, and the unit-size
# fingerprint (a note, never graded). Design, treatment, id, aliased text and
# linked columns are preserved by construction and only held fixed.
.joint_audit <- function(df, synth, rec, mode, audit, linked, strata) {
  collab <- identical(mode, "collaborate")
  coarsened <- unlist(lapply(rec@coords, function(cr) c(cr$lat, cr$lon)),
                      use.names = FALSE)
  retained <- audit$alias_status != "dropped" & !(audit$col %in% coarsened)
  structural <- audit$role %in% c("design", "treatment", "id") |
    (audit$role == "text" & audit$action == "alias") |
    audit$col %in% linked
  fixed_cols <- audit$col[retained & structural]
  content_cols <- audit$col[retained & !structural]
  n <- nrow(df)
  out <- list()

  if (length(content_cols) && n > 0L) {
    codes <- .joint_codes(df, synth, rec, c(fixed_cols, content_cols))
    groups <- lapply(content_cols, function(col) {
      i <- match(col, audit$col)
      if (audit$kind[i] %in% .numeric_kinds() &&
        .audit_numeric_resimulated(audit$action[i])) {
        strata
      }
    })
    names(groups) <- content_cols
    st <- with_rng_state(
      .AUDIT_SEED,
      .joint_match_stats(
        codes$orig, codes$clone, content_cols, groups, fixed_cols
      )
    )
    # One row is the smallest step a share can take.
    st$sd <- pmax(st$sd, 100 / n)
    labels <- c(same_row_joint = "same-row joint match",
                whole_row = "whole-row match")
    for (k in seq_along(labels)) {
      out[[length(out) + 1L]] <- .joint_row(
        check = names(labels)[k],
        cols = if (k == 1L) content_cols else c(fixed_cols, content_cols),
        observed = st$observed[k], baseline = st$baseline[k],
        sd = st$sd[k], label = labels[[k]], unit = "%",
        high = .AUDIT_THRESHOLDS$joint_high,
        medium = .AUDIT_THRESHOLDS$joint_medium, collab = collab
      )
    }
  }

  visible <- audit$col[retained &
    audit$role %in% c("covariate", "outcome") &
    audit$kind %in% .categorical_kinds() &
    audit$alias_status %in% c("passthrough", "permuted")]
  if (length(visible) >= 2L && n > 0L) {
    rare <- with_rng_state(
      .AUDIT_SEED, .rare_cross_stats(df, synth, visible)
    )
    out[[length(out) + 1L]] <- .joint_row(
      check = "rare_cross", cols = visible,
      observed = rare$observed, baseline = rare$baseline,
      # Half a cell: the null of a rare count can have no spread at all.
      sd = max(rare$sd, 0.5),
      label = "clone singleton cells also unique in the original",
      unit = " cells",
      high = .AUDIT_THRESHOLDS$rare_high,
      medium = .AUDIT_THRESHOLDS$rare_medium, collab = collab
    )
  }

  # Labels cannot tell a trial from a rep restarted within it, so the note
  # names every top-level design column whose units differ in size.
  unequal <- .unequal_unit_cols(
    df, audit$col[retained & audit$role == "design"]
  )
  if (length(unequal)) {
    out[[length(out) + 1L]] <- data.table::data.table(
      check = "unit_sizes", cols = paste(unequal, collapse = ", "),
      observed = NA_real_, baseline = NA_real_, excess = NA_real_,
      sd = NA_real_, leakage_class = "info",
      notes = sprintf(
        paste0(
          "unit sizes differ across %s; the multiset of sizes can link the ",
          "clone to a public trial list"
        ),
        paste(unequal, collapse = ", ")
      )
    )
  }

  if (!length(out)) {
    return(.joint_row_template()[0L])
  }
  data.table::rbindlist(out)
}

.joint_row_template <- function() {
  data.table::data.table(
    check = character(), cols = character(), observed = numeric(),
    baseline = numeric(), excess = numeric(), sd = numeric(),
    leakage_class = character(), notes = character()
  )
}

# One graded table-level row. Local mode reports the verdict in the notes but
# grades it low.
.joint_row <- function(check, cols, observed, baseline, sd, label, unit,
                       high, medium, collab) {
  excess <- observed - baseline
  verdict <- if (.excess_clears(excess, sd, high)) {
    "high"
  } else if (.excess_clears(excess, sd, medium)) {
    "medium"
  } else {
    "low"
  }
  fmt <- if (unit == "%") "%.1f%%" else paste0("%.1f", unit)
  notes <- sprintf(
    paste0("%s ", fmt, " vs chance ", fmt, " (sd %.1f)"),
    label, observed, baseline, sd
  )
  if (!collab && verdict != "low") {
    notes <- sprintf("%s; %s in collaborate mode", notes, toupper(verdict))
  }
  data.table::data.table(
    check = check, cols = paste(cols, collapse = ", "),
    observed = observed, baseline = baseline, excess = excess, sd = sd,
    leakage_class = if (collab) verdict else "low", notes = notes
  )
}

# Integer codes of the original and the clone on a shared code space, the
# clone read back into the original labels; NA is a code of its own.
.joint_codes <- function(df, synth, rec, cols) {
  orig <- vector("list", length(cols))
  clone <- vector("list", length(cols))
  for (j in seq_along(cols)) {
    map <- rec@level_maps[[cols[j]]]
    x <- if (is.null(map)) .audit_values(df[[cols[j]]]) else
      as.character(df[[cols[j]]])
    y <- .audit_values(.audit_original_space(synth[[cols[j]]], map))
    if (is.character(x) != is.character(y)) {
      x <- as.character(x)
      y <- as.character(y)
    }
    u <- unique(c(x, y))
    orig[[j]] <- match(x, u)
    clone[[j]] <- match(y, u)
  }
  names(orig) <- names(clone) <- cols
  list(
    orig = data.table::as.data.table(orig),
    clone = data.table::as.data.table(clone)
  )
}

# Observed, mean and SD (in percent of rows) of the same-row joint match over
# `content` and the whole-row match over every column, against clones whose
# content columns are independent permutations of the original's.
.joint_match_stats <- function(orig, clone, content, groups, fixed) {
  n <- nrow(orig)
  same_row <- function(cand) {
    ok <- rep(TRUE, n)
    for (col in content) ok <- ok & cand[[col]] == orig[[col]]
    mean(ok)
  }
  # Fixed columns that identify every row leave a clone row one candidate,
  # its own original row: the whole-row share is then the same-row share.
  unique_key <- length(fixed) > 0L &&
    anyDuplicated(.row_group_id(lapply(fixed, function(f) orig[[f]]))) == 0L
  whole_row <- function(cand) {
    same_fixed <- all(vapply(fixed, function(f) {
      identical(cand[[f]], orig[[f]])
    }, logical(1L)))
    if (unique_key && same_fixed) {
      return(same_row(cand))
    }
    mean(.rows_found(cand, orig))
  }
  observed <- c(same_row(clone), whole_row(clone))
  draws <- vapply(seq_len(.AUDIT_PERMUTATIONS), function(b) {
    cand <- data.table::copy(orig)
    for (col in content) {
      data.table::set(
        cand, j = col,
        value = orig[[col]][.permute_rows(n, groups[[col]])]
      )
    }
    c(same_row(cand), whole_row(cand))
  }, numeric(2L))
  list(
    observed = 100 * observed,
    baseline = 100 * rowMeans(draws),
    sd = 100 * apply(draws, 1L, stats::sd)
  )
}

# A random row order, within `groups` when given.
.permute_rows <- function(n, groups = NULL) {
  idx <- seq_len(n)
  if (is.null(groups)) {
    return(idx[sample.int(n)])
  }
  as.integer(stats::ave(idx, groups, FUN = function(g) {
    g[sample.int(length(g))]
  }))
}

# Clone cells (combinations of the visible categorical labels) holding exactly
# one row whose combination is also a single row in the original, against
# the same count for independent permutations of the original columns.
.rare_cross_stats <- function(df, synth, cols) {
  orig <- vector("list", length(cols))
  clone <- vector("list", length(cols))
  for (j in seq_along(cols)) {
    x <- as.character(df[[cols[j]]])
    y <- as.character(synth[[cols[j]]])
    u <- unique(c(x, y))
    orig[[j]] <- match(x, u)
    clone[[j]] <- match(y, u)
  }
  names(orig) <- names(clone) <- sprintf("v%d", seq_along(cols))
  orig <- data.table::as.data.table(orig)
  clone <- data.table::as.data.table(clone)
  overlap <- function(cand) .singleton_overlap(cand, orig)
  n <- nrow(orig)
  draws <- vapply(seq_len(.AUDIT_PERMUTATIONS), function(b) {
    cand <- data.table::copy(orig)
    for (col in names(cand)) {
      data.table::set(cand, j = col, value = orig[[col]][sample.int(n)])
    }
    as.numeric(overlap(cand))
  }, numeric(1L))
  list(
    observed = as.numeric(overlap(clone)),
    baseline = mean(draws), sd = stats::sd(draws)
  )
}

# Retained design columns, not nested in another, whose units differ in size.
.unequal_unit_cols <- function(df, design_cols) {
  ids <- lapply(design_cols, function(dc) .row_group_id(list(df[[dc]])))
  names(ids) <- design_cols
  out <- character()
  for (dc in design_cols) {
    sizes <- tabulate(ids[[dc]])
    if (length(sizes) < 2L || length(unique(sizes)) == 1L) next
    nested <- vapply(setdiff(design_cols, dc), function(other) {
      length(unique(ids[[other]])) < length(sizes) &&
        all(tapply(ids[[other]], ids[[dc]], function(v) {
          length(unique(v))
        }) == 1L)
    }, logical(1L))
    if (!any(nested)) out <- c(out, dc)
  }
  out
}

# Share of rows whose NA pattern no other row shares, grouped on the NA matrix.
.global_na_pattern_uniqueness <- function(df) {
  n <- nrow(df)
  if (n == 0L) {
    return(NA_real_)
  }
  if (ncol(df) == 0L) {
    return(if (n == 1L) 1 else 0)
  }
  pattern <- data.table::frankv(lapply(df, is.na), ties.method = "dense")
  sum(tabulate(pattern) == 1L) / n
}

.classify_leakage <- function(
  role, kind, action, pii, mode, in_synth, alias_status,
  exact_match_pct, freq_min, n_unique_levels, n_rows, coarsened = FALSE,
  same_row_excess = NA_real_, same_row_sd = NA_real_, two_valued = FALSE,
  linked = FALSE
) {
  collab <- identical(mode, "collaborate")

  # 0. A coordinate jittered in place is retained but displaced: MEDIUM.
  if (isTRUE(coarsened) && in_synth) {
    return(if (collab) "medium" else "low")
  }

  # 1. PII retained in the synthetic, even aliased: HIGH across the trust
  #    boundary, MEDIUM when the synthetic stays with the owner.
  if (pii && in_synth) {
    return(if (collab) "high" else "medium")
  }

  # 2. Treatment vocabulary visible in collaborate: HIGH. Both a plain
  #    pass-through and a label permutation expose every real label.
  if (role == "treatment" && collab &&
    alias_status %in% c("passthrough", "permuted")) {
    return("high")
  }

  # 3. Categorical covariate with a frequency-1 level in collaborate: HIGH
  if (role == "covariate" && kind %in% c("factor", "character", "logical") &&
    collab && !is.na(freq_min) && freq_min == 1L) {
    return("high")
  }

  # 4. Outcome with exact-match-pct > 1% in collaborate: MEDIUM. A two-valued
  #    column matches its own cell by chance about half the time; rule 5b
  #    grades it on the excess over that chance instead.
  if (role == "outcome" && collab && !isTRUE(two_valued) &&
    !is.na(exact_match_pct) && exact_match_pct > 1) {
    return("medium")
  }

  # 5. Numeric covariate with exact-match-pct > 5% in collaborate: MEDIUM
  if (role == "covariate" && kind %in% c("numeric", "integer") &&
    collab && !isTRUE(two_valued) &&
    !is.na(exact_match_pct) && exact_match_pct > 5) {
    return("medium")
  }

  # 5b. Content column returned to its own row beyond chance in collaborate:
  #     MEDIUM. Structural and linked columns match by construction.
  if (collab && in_synth && !isTRUE(linked) &&
    !(role %in% c("design", "treatment", "id")) &&
    .excess_clears(
      same_row_excess, same_row_sd, .AUDIT_THRESHOLDS$same_row_medium
    )) {
    return("medium")
  }

  # 6. Non-design column kept as-is in collaborate mode: MEDIUM. Design
  #    columns are exempt, since keeping them is the point of the package.
  if (collab && !is.na(action) && action == "keep" && role != "design" &&
    in_synth) {
    return("medium")
  }

  "low"
}

.audit_notes <- function(role, kind, action, pii, alias_status, mode,
                         leakage_class, exact_match_pct, freq_min,
                         coarsened = FALSE, same = NULL, two_valued = FALSE) {
  collab <- identical(mode, "collaborate")
  bits <- character()
  if (pii && !isTRUE(coarsened)) bits <- c(bits, "PII-pattern column name")
  if (isTRUE(coarsened)) {
    bits <- c(bits, "coordinate coarsened in place by the geomask")
  }
  if (alias_status == "aliased") bits <- c(bits, "levels aliased")
  if (alias_status == "permuted") {
    bits <- c(bits, "labels permuted; vocabulary visible")
  }
  if (alias_status == "dropped") bits <- c(bits, "dropped")
  if (alias_status == "passthrough" && !is.na(action) && action == "keep" &&
    role != "design" && collab && !isTRUE(coarsened)) {
    bits <- c(bits, "kept as-is - visible to collaborators")
  }
  if (alias_status == "passthrough" &&
    (role == "date" || kind %in% c("date", "datetime")) &&
    (is.na(action) || action == "scramble")) {
    bits <- c(bits, "date/time row-permuted")
  }
  if (alias_status == "passthrough" && role == "treatment" && collab) {
    bits <- c(bits, "treatment passthrough in collaborate (unexpected)")
  }
  if (!is.na(freq_min) && freq_min == 1L && role == "covariate" && collab) {
    bits <- c(bits, "rare level (freq = 1)")
  }
  if (!is.na(exact_match_pct) && exact_match_pct > 1 && collab &&
    !isTRUE(two_valued)) {
    bits <- c(bits, sprintf("exact-match %.1f%%", exact_match_pct))
  }
  if (!is.null(same) && !(role %in% c("design", "treatment", "id")) &&
    isTRUE(same$excess >= .AUDIT_THRESHOLDS$same_row_medium$excess)) {
    bits <- c(bits, sprintf(
      "same-row %.1f%% vs chance %.1f%%", same$observed, same$baseline
    ))
  }
  if (length(bits) == 0L) bits <- "ok"
  paste(bits, collapse = "; ")
}
