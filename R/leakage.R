#' Internal: build the audit tibble for a (df, synth, recipe, mode) tuple
#'
#' Called by `mask()` in `collaborate` mode and by `audit_mask()` on demand.
#' Returns a tibble with one row per column of the original data frame.
#'
#' @keywords internal
#' @noRd
.compute_audit <- function(df, synth, rec, mode) {
  cols <- rec@roles$col
  has_action <- "action" %in% names(rec@roles)
  na_pattern_uniq <- .global_na_pattern_uniqueness(df)

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

    n_unique_levels <- NA_integer_
    freq_min <- NA_integer_
    if (kind %in% c("factor", "character", "logical")) {
      x_clean <- x[!is.na(x)]
      n_unique_levels <- length(unique(x_clean))
      tbl <- table(x_clean)
      freq_min <- if (length(tbl)) as.integer(min(tbl)) else NA_integer_
    }

    na_pct <- 100 * sum(is.na(x)) / n

    leakage_class <- .classify_leakage(
      role = role, kind = kind, action = action, pii = pii, mode = mode,
      in_synth = in_synth, alias_status = alias_status,
      exact_match_pct = exact_match_pct, freq_min = freq_min,
      n_unique_levels = n_unique_levels, n_rows = n
    )

    notes <- .audit_notes(
      role, kind, action, pii, alias_status, mode, leakage_class,
      exact_match_pct, freq_min
    )

    data.frame(
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
      stringsAsFactors       = FALSE
    )
  })

  tibble::as_tibble(do.call(rbind, rows))
}

.global_na_pattern_uniqueness <- function(df) {
  if (nrow(df) == 0L) {
    return(NA_real_)
  }
  na_mat <- is.na(df)
  patterns <- apply(na_mat, 1L, function(r) paste(as.integer(r), collapse = ""))
  freqs <- table(patterns)
  sum(freqs == 1L) / nrow(df)
}

.classify_leakage <- function(
  role, kind, action, pii, mode, in_synth, alias_status,
  exact_match_pct, freq_min, n_unique_levels, n_rows
) {
  collab <- identical(mode, "collaborate")

  # 1. PII pattern retained in the synthetic: HIGH across the trust
  #    boundary (even aliased - retention itself is the finding),
  #    MEDIUM when the surrogate stays with the owner.
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

  # 4. Outcome with exact-match-pct > 1% in collaborate: MEDIUM
  if (role == "outcome" && collab &&
    !is.na(exact_match_pct) && exact_match_pct > 1) {
    return("medium")
  }

  # 5. Numeric covariate with exact-match-pct > 5% in collaborate: MEDIUM
  if (role == "covariate" && kind %in% c("numeric", "integer") &&
    collab && !is.na(exact_match_pct) && exact_match_pct > 5) {
    return("medium")
  }

  # 6. Non-design column kept as-is in collaborate: MEDIUM. Real values
  #    cross the trust boundary; design exposure is the documented
  #    exception (structural fidelity is the package contract).
  if (collab && !is.na(action) && action == "keep" && role != "design" &&
    in_synth) {
    return("medium")
  }

  "low"
}

.audit_notes <- function(role, kind, action, pii, alias_status, mode,
                         leakage_class, exact_match_pct, freq_min) {
  collab <- identical(mode, "collaborate")
  bits <- character()
  if (pii) bits <- c(bits, "PII-pattern column name")
  if (alias_status == "aliased") bits <- c(bits, "levels aliased")
  if (alias_status == "permuted") {
    bits <- c(bits, "labels permuted; vocabulary visible")
  }
  if (alias_status == "dropped") bits <- c(bits, "dropped")
  if (alias_status == "passthrough" && !is.na(action) && action == "keep" &&
    role != "design" && collab) {
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
  if (!is.na(exact_match_pct) && exact_match_pct > 1 && collab) {
    bits <- c(bits, sprintf("exact-match %.1f%%", exact_match_pct))
  }
  if (length(bits) == 0L) bits <- "ok"
  paste(bits, collapse = "; ")
}
