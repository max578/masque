#' Internal: build the audit tibble for a (df, synth, recipe, mode) tuple
#'
#' Called by `mask()` in `collaborate` mode and by `audit_mask()` on demand.
#' Returns a tibble with one row per column of the original data frame.
#'
#' @keywords internal
#' @noRd
.compute_audit <- function(df, synth, rec, mode) {
  cols <- rec@roles$col
  na_pattern_uniq <- .global_na_pattern_uniqueness(df)

  rows <- lapply(cols, function(col) {
    role <- rec@roles$role[rec@roles$col == col]
    kind <- rec@roles$kind[rec@roles$col == col]
    pii <- isTRUE(rec@roles$pii_suspected[rec@roles$col == col])

    in_synth <- col %in% names(synth)
    has_map <- col %in% names(rec@level_maps)
    alias_status <- if (has_map) {
      "aliased"
    } else if (!in_synth) {
      "dropped"
    } else {
      "passthrough"
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
      role = role, kind = kind, pii = pii, mode = mode,
      in_synth = in_synth, alias_status = alias_status,
      exact_match_pct = exact_match_pct, freq_min = freq_min,
      n_unique_levels = n_unique_levels, n_rows = n
    )

    notes <- .audit_notes(
      role, kind, pii, alias_status, mode, leakage_class,
      exact_match_pct, freq_min
    )

    data.frame(
      col                    = col,
      role                   = role,
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
  role, kind, pii, mode, in_synth, alias_status,
  exact_match_pct, freq_min, n_unique_levels, n_rows
) {
  # 1. PII pattern retained as not-ignored: HIGH
  if (pii && role != "ignore" && in_synth) {
    return("high")
  }

  # 2. Treatment unaliased in collaborate: HIGH
  if (role == "treatment" && mode == "collaborate" &&
    alias_status == "passthrough") {
    return("high")
  }

  # 3. Categorical covariate with a frequency-1 level in collaborate: HIGH
  if (role == "covariate" && kind %in% c("factor", "character", "logical") &&
    mode == "collaborate" && !is.na(freq_min) && freq_min == 1L) {
    return("high")
  }

  # 4. Outcome with exact-match-pct > 1% in collaborate: MEDIUM
  if (role == "outcome" && mode == "collaborate" &&
    !is.na(exact_match_pct) && exact_match_pct > 1) {
    return("medium")
  }

  # 5. Numeric covariate with exact-match-pct > 5% in collaborate: MEDIUM
  if (role == "covariate" && kind %in% c("numeric", "integer") &&
    mode == "collaborate" && !is.na(exact_match_pct) &&
    exact_match_pct > 5) {
    return("medium")
  }

  # 6. Ignore column retained in local: LOW (informational)
  if (role == "ignore" && mode == "local" && in_synth) {
    return("low")
  }

  "low"
}

.audit_notes <- function(role, kind, pii, alias_status, mode, leakage_class,
                         exact_match_pct, freq_min) {
  bits <- character()
  if (pii) bits <- c(bits, "PII-pattern column name")
  if (alias_status == "aliased") bits <- c(bits, "levels aliased")
  if (alias_status == "dropped") bits <- c(bits, "dropped under collaborate")
  if (alias_status == "passthrough" && role == "treatment" &&
    mode == "collaborate") {
    bits <- c(bits, "treatment passthrough in collaborate (unexpected)")
  }
  if (!is.na(freq_min) && freq_min == 1L && role == "covariate" &&
    mode == "collaborate") {
    bits <- c(bits, "rare level (freq = 1)")
  }
  if (!is.na(exact_match_pct) && exact_match_pct > 1 &&
    mode == "collaborate") {
    bits <- c(
      bits,
      sprintf("exact-match %.1f%% (jitter due step 7)", exact_match_pct)
    )
  }
  if (length(bits) == 0L) bits <- "ok"
  paste(bits, collapse = "; ")
}
