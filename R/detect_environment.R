# Explicit and conservative automatic environment handling for detect_design().
# User-supplied bases bypass name priors; automatic candidates remain bounded
# to the validated Phase 2 vocabulary and abstain on weak or competing evidence.

ENVIRONMENT_MIN_COVERAGE <- 0.8
SITE_MIN_REPLICATED_LEVEL_FRACTION <- 0.5
CONNECTIVITY_MAX_DENSE_CELLS <- 5000000
GROUP_MIN_CONFINED_FRACTION <- 0.8
GROUP_MAX_SHARED_FRACTION <- 0.05

.empty_per_env <- function() {
  data.frame(
    env = character(),
    class_label = character(),
    score = numeric(),
    treatment_col = character(),
    block_cols = character(),
    spatial_cols = character(),
    n_rows = integer(),
    n_treatments = integer(),
    stringsAsFactors = FALSE
  )
}

.connectivity_not_computed <- function(reason = "no treatment basis") {
  list(
    status = "not_computed",
    components = NA_integer_,
    component_sizes = data.frame(
      component = integer(),
      n_env = integer(),
      n_treatments = integer()
    ),
    overlap = list(),
    reason = reason
  )
}

.scope_unknown <- function() {
  list(
    scope_label = "uncertain",
    scope_status = "uncertain",
    scope_confidence = "none",
    is_met = NA,
    env_cols = character(),
    env_method = character(),
    n_env = NA_integer_,
    group_cols = character(),
    connectivity = .connectivity_not_computed("environment unresolved"),
    per_env = .empty_per_env(),
    within_design_label = "unresolved"
  )
}

.scope_disabled <- function() {
  out <- .scope_unknown()
  out$scope_label <- "disabled"
  out$scope_status <- "disabled"
  out$connectivity <- .connectivity_not_computed("MET detection disabled")
  out
}

.abort_invalid_environment <- function(message, ..., .envir = parent.frame()) {
  cli::cli_abort(
    message,
    ...,
    class = "masque_invalid_environment",
    .envir = .envir
  )
}

.validate_environment_arg <- function(df, env) {
  if (is.null(env)) {
    return(list(mode = "automatic", cols = character()))
  }
  if (is.logical(env) && length(env) == 1L && !is.na(env) && !env) {
    return(list(mode = "disabled", cols = character()))
  }
  if (!is.character(env) || length(env) == 0L || anyNA(env) ||
    any(!nzchar(env))) {
    .abort_invalid_environment(c(
      "`env` must be `NULL`, `FALSE`, or one or more column names.",
      "i" = paste0(
        "Supply a character vector such as {.val env} or ",
        "{.val {c('site', 'year')}}."
      )
    ))
  }
  if (anyDuplicated(env)) {
    duplicates <- unique(env[duplicated(env)])
    .abort_invalid_environment(
      "`env` contains duplicate column name(s): {.field {duplicates}}."
    )
  }

  missing_cols <- setdiff(env, names(df))
  if (length(missing_cols) > 0L) {
    .abort_invalid_environment(
      "Environment column(s) not found in `df`: {.field {missing_cols}}."
    )
  }

  all_missing <- env[vapply(df[env], function(x) all(is.na(x)), logical(1L))]
  if (length(all_missing) > 0L) {
    .abort_invalid_environment(
      "Environment column(s) are all-missing: {.field {all_missing}}."
    )
  }

  list(mode = "explicit", cols = env)
}

.interaction_key <- function(df, cols) {
  if (length(cols) == 1L) {
    return(factor(df[[cols]], exclude = NA))
  }
  args <- c(
    unname(df[cols]),
    list(drop = TRUE, lex.order = TRUE, sep = ":")
  )
  do.call(interaction, args)
}

.treatment_basis <- function(out, roles, env_cols) {
  treatment_cols <- character()
  if (!is.null(roles) && all(c("col", "role") %in% names(roles))) {
    treatment_cols <- roles$col[roles$role == "treatment"]
    treatment_cols <- intersect(treatment_cols, out@candidates$cols)
  }
  if (length(treatment_cols) == 0L) {
    treatment_cols <- out@candidates$trt_user
  }
  if (length(treatment_cols) == 0L &&
    length(out@candidates$trt_named) == 1L) {
    treatment_cols <- out@candidates$trt_named
  }
  if (length(treatment_cols) == 0L) {
    exact_aliases <- out@candidates$factors[
      grepl(
        "^(gen|geno|genotype|cultivar|variety|trt|treatment)$",
        out@candidates$factors,
        ignore.case = TRUE,
        perl = TRUE
      )
    ]
    if (length(exact_aliases) == 1L) {
      treatment_cols <- exact_aliases
    }
  }
  setdiff(unique(treatment_cols), env_cols)
}

.environment_candidate <- function(cols, method, confidence, rank) {
  list(
    cols = cols,
    method = method,
    confidence = confidence,
    rank = as.integer(rank)
  )
}

.evaluate_environment_candidate <- function(df, candidate, treatment_key,
                                            allow_no_treatment = FALSE) {
  env_complete <- stats::complete.cases(df[candidate$cols])
  coverage <- mean(env_complete)
  env_key <- .interaction_key(df, candidate$cols)
  n_env <- nlevels(env_key)
  n_observed <- sum(!is.na(env_key))

  structurally_valid <- coverage >= ENVIRONMENT_MIN_COVERAGE &&
    n_env >= 2L && n_env < n_observed
  max_env_per_treatment <- NA_integer_
  replicated_level_fraction <- NA_real_
  if (is.null(treatment_key)) {
    treatment_valid <- isTRUE(allow_no_treatment)
  } else {
    counts <- table(env_key, treatment_key, useNA = "no")
    incidence <- counts > 0L
    max_env_per_treatment <- if (ncol(incidence) == 0L) {
      0L
    } else {
      as.integer(max(colSums(incidence)))
    }
    treatment_valid <- max_env_per_treatment >= 2L
    if (identical(candidate$method, "site") && nrow(counts) > 0L) {
      replicated_level_fraction <- mean(rowSums(counts >= 2L) > 0L)
      if (replicated_level_fraction <
        SITE_MIN_REPLICATED_LEVEL_FRACTION) {
        candidate$confidence <- "medium"
      }
    }
  }

  candidate$coverage <- coverage
  candidate$n_env <- as.integer(n_env)
  candidate$n_observed <- as.integer(n_observed)
  candidate$max_env_per_treatment <- max_env_per_treatment
  candidate$replicated_level_fraction <- replicated_level_fraction
  candidate$valid <- structurally_valid && treatment_valid
  candidate
}

.equivalent_environment_partition <- function(df, left_cols, right_cols) {
  left <- .interaction_key(df, left_cols)
  right <- .interaction_key(df, right_cols)
  if (!identical(is.na(left), is.na(right))) {
    return(FALSE)
  }
  joint <- interaction(left, right, drop = TRUE, lex.order = TRUE)
  nlevels(joint) == nlevels(left) && nlevels(joint) == nlevels(right)
}

.automatic_environment_candidates <- function(df, treatment_cols,
                                              roles = NULL) {
  cols <- names(df)
  reserved_pattern <- paste0(
    "^(rep[0-9]*|block|row|col|column|range|plot|plotno|",
    "trial|experiment|study|panel|population|cohort)$"
  )
  reserved <- cols[
    grepl(reserved_pattern, cols, ignore.case = TRUE, perl = TRUE)
  ]
  role_exclusions <- character()
  if (!is.null(roles) && all(c("col", "role") %in% names(roles))) {
    role_exclusions <- roles$col[
      roles$role %in% c("outcome", "id", "text", "other", "ignore", "keep")
    ]
    if ("action" %in% names(roles)) {
      role_exclusions <- union(
        role_exclusions,
        roles$col[!is.na(roles$action) & roles$action == "drop"]
      )
    }
    if ("pii_suspected" %in% names(roles)) {
      role_exclusions <- union(
        role_exclusions,
        roles$col[!is.na(roles$pii_suspected) & roles$pii_suspected]
      )
    }
  }
  available <- setdiff(
    cols,
    union(union(treatment_cols, reserved), role_exclusions)
  )

  exact <- available[
    grepl("^(env|environment)$", available, ignore.case = TRUE, perl = TRUE)
  ]
  precomposed <- available[
    grepl(
      "^(site_?year|loc_?year|location_?year)$",
      available,
      ignore.case = TRUE,
      perl = TRUE
    )
  ]
  site <- available[
    grepl(
      "^(site|location|loc|county|region|field|farm|place)$",
      available,
      ignore.case = TRUE,
      perl = TRUE
    )
  ]
  year <- available[
    grepl(
      "^(year|yr|season|harvest_?year|cycle)$",
      available,
      ignore.case = TRUE,
      perl = TRUE
    )
  ]

  candidates <- list()
  for (col in exact) {
    candidates[[length(candidates) + 1L]] <-
      .environment_candidate(col, "exact", "high", 1L)
  }
  for (col in precomposed) {
    candidates[[length(candidates) + 1L]] <-
      .environment_candidate(col, "precomposed", "high", 2L)
  }
  if (length(site) > 0L && length(year) > 0L) {
    for (site_col in site) {
      for (year_col in year) {
        candidates[[length(candidates) + 1L]] <- .environment_candidate(
          c(site_col, year_col), "site_year", "high", 3L
        )
      }
    }
  }
  for (col in site) {
    candidates[[length(candidates) + 1L]] <-
      .environment_candidate(col, "site", "high", 4L)
  }
  for (col in year) {
    candidates[[length(candidates) + 1L]] <-
      .environment_candidate(col, "year", "medium", 5L)
  }
  candidates
}

.resolve_environment <- function(df, out, roles) {
  treatment_cols <- .treatment_basis(out, roles, character())
  treatment_key <- .treatment_key(df, treatment_cols)
  candidates <- .automatic_environment_candidates(
    df, treatment_cols, roles = roles
  )
  if (length(candidates) == 0L) {
    return(list(status = "none", treatment_cols = treatment_cols))
  }

  candidates <- lapply(candidates, function(candidate) {
    allow_no_treatment <- candidate$rank == 1L
    .evaluate_environment_candidate(
      df, candidate, treatment_key,
      allow_no_treatment = allow_no_treatment
    )
  })
  candidates <- candidates[
    vapply(candidates, `[[`, logical(1L), "valid")
  ]
  if (length(candidates) == 0L) {
    return(list(status = "none", treatment_cols = treatment_cols))
  }

  best_rank <- min(vapply(candidates, `[[`, integer(1L), "rank"))
  candidate_ranks <- vapply(candidates, `[[`, integer(1L), "rank")
  best <- candidates[
    candidate_ranks == best_rank
  ]
  if (length(best) > 1L) {
    labels <- vapply(best, function(candidate) {
      paste(candidate$cols, collapse = " + ")
    }, character(1L))
    return(list(
      status = "ambiguous",
      candidates = labels,
      candidate_specs = best,
      competition_margin = 0L,
      treatment_cols = treatment_cols
    ))
  }
  runner_up <- candidate_ranks[candidate_ranks > best_rank]
  competition_margin <- if (length(runner_up) == 0L) {
    NA_integer_
  } else {
    as.integer(min(runner_up) - best_rank)
  }
  equivalent <- candidates[vapply(candidates, function(candidate) {
    candidate$rank != best_rank && .equivalent_environment_partition(
      df, best[[1L]]$cols, candidate$cols
    )
  }, logical(1L))]
  supporting_cols <- unique(unlist(
    lapply(equivalent, `[[`, "cols"),
    use.names = FALSE
  ))
  list(
    status = if (best[[1L]]$confidence == "high") "resolved" else "review",
    candidate = best[[1L]],
    competition_margin = competition_margin,
    supporting_cols = setdiff(supporting_cols, best[[1L]]$cols),
    treatment_cols = treatment_cols
  )
}

.record_environment_evidence <- function(out, details) {
  evidence <- out@evidence
  evidence$environment <- details
  out@evidence <- evidence
  out
}

.empty_role_recommendations <- function() {
  data.frame(
    col = character(),
    role = character(),
    action_local = character(),
    action_collaborate = character(),
    confidence = character(),
    source = character(),
    auto_apply = logical(),
    reason = character(),
    stringsAsFactors = FALSE
  )
}

.normalise_role_recommendations <- function(rec, df) {
  if (nrow(rec) == 0L) {
    return(.empty_role_recommendations())
  }
  kinds <- vapply(rec$col, function(col) {
    if (col %in% names(df)) col_kind(df[[col]]) else "other"
  }, character(1L))
  defaults <- list(
    action_local = vapply(seq_len(nrow(rec)), function(i) {
      .default_action(rec$role[i], kinds[i], "local")
    }, character(1L)),
    action_collaborate = vapply(seq_len(nrow(rec)), function(i) {
      .default_action(rec$role[i], kinds[i], "collaborate")
    }, character(1L)),
    confidence = rep("legacy_rule", nrow(rec)),
    source = rep("design_rule", nrow(rec)),
    auto_apply = rep(TRUE, nrow(rec)),
    reason = rep("Legacy pooled-design recommendation.", nrow(rec))
  )
  for (field in names(defaults)) {
    if (!(field %in% names(rec))) {
      rec[[field]] <- defaults[[field]]
    }
  }
  rec[names(.empty_role_recommendations())]
}

.environment_role_recommendations <- function(df, cols, confidence,
                                              auto_apply, reason,
                                              preserve_only = FALSE) {
  if (length(cols) == 0L) {
    return(.empty_role_recommendations())
  }
  kinds <- vapply(df[cols], col_kind, character(1L))
  categorical <- kinds %in% .categorical_kinds()
  # `preserve_only` is the fail-safe for a suspected-but-unconfirmed
  # environment (review-required or ambiguous): keep the column byte-identical
  # in both modes rather than aliasing it. Aliasing a weak candidate is never
  # automatic; only a high-confidence environment is aliased in collaborate.
  action_collaborate <- if (preserve_only) {
    rep("keep", length(cols))
  } else {
    ifelse(categorical, "alias", "keep")
  }
  data.frame(
    col = cols,
    role = rep("design", length(cols)),
    action_local = rep("keep", length(cols)),
    action_collaborate = action_collaborate,
    confidence = rep(confidence, length(cols)),
    source = rep("environment_auto", length(cols)),
    auto_apply = rep(auto_apply, length(cols)),
    reason = rep(reason, length(cols)),
    stringsAsFactors = FALSE
  )
}

.merge_environment_recommendations <- function(out, df, cols, confidence,
                                               auto_apply, reason,
                                               preserve_only = FALSE) {
  existing <- .normalise_role_recommendations(out@recommended_roles, df)
  existing <- existing[!(existing$col %in% cols), , drop = FALSE]
  environment <- .environment_role_recommendations(
    df, cols, confidence, auto_apply, reason,
    preserve_only = preserve_only
  )
  out@recommended_roles <- rbind(existing, environment)
  out
}

.apply_automatic_environment <- function(out, df, roles, resolution,
                                         threshold, tie_delta) {
  if (resolution$status == "none") {
    return(out)
  }
  if (resolution$status == "ambiguous") {
    out@scope_status <- "ambiguous"
    out@warnings <- c(
      out@warnings,
      sprintf(
        "Environment scope is ambiguous between: %s.",
        paste(resolution$candidates, collapse = ", ")
      )
    )
    candidate_cols <- unique(unlist(
      lapply(resolution$candidate_specs, `[[`, "cols"),
      use.names = FALSE
    ))
    out <- .merge_environment_recommendations(
      out, df, candidate_cols, "ambiguous", TRUE,
      paste0(
        "Competing environment candidates preserved as design/keep; ",
        "pass `env =` to choose the environment basis."
      ),
      preserve_only = TRUE
    )
    return(.record_environment_evidence(out, list(
      source = "automatic",
      status = "ambiguous",
      candidates = resolution$candidates,
      competition_margin = resolution$competition_margin
    )))
  }

  candidate <- resolution$candidate
  if (resolution$status == "review") {
    env_key <- .interaction_key(df, candidate$cols)
    out@scope_status <- "review_required"
    out@scope_confidence <- candidate$confidence
    out@env_cols <- candidate$cols
    out@env_method <- candidate$method
    out@n_env <- as.integer(nlevels(env_key))
    out@warnings <- c(
      out@warnings,
      sprintf(
        "Possible environment basis `%s` requires explicit review.",
        paste(candidate$cols, collapse = " + ")
      )
    )
    out <- .merge_environment_recommendations(
      out, df, candidate$cols, candidate$confidence, TRUE,
      paste0(
        "Suspected environment preserved as design/keep pending explicit ",
        "review; pass `env =` to enable environment-aware masking."
      ),
      preserve_only = TRUE
    )
    return(.record_environment_evidence(out, list(
      source = "automatic",
      status = "review_required",
      cols = candidate$cols,
      method = candidate$method,
      confidence = candidate$confidence,
      competition_margin = resolution$competition_margin,
      coverage = candidate$coverage,
      n_env = candidate$n_env,
      max_env_per_treatment = candidate$max_env_per_treatment,
      replicated_level_fraction = candidate$replicated_level_fraction
    )))
  }

  out <- .apply_explicit_environment(
    out = out,
    df = df,
    roles = roles,
    env_cols = candidate$cols,
    threshold = threshold,
    tie_delta = tie_delta
  )
  out@env_method <- candidate$method
  out@scope_confidence <- candidate$confidence
  recommendation_cols <- unique(c(candidate$cols, resolution$supporting_cols))
  out <- .merge_environment_recommendations(
    out, df, recommendation_cols, candidate$confidence, TRUE,
    "High-confidence environment basis or equivalent supporting column."
  )
  .record_environment_evidence(out, list(
    source = "automatic",
    status = "detected",
    cols = candidate$cols,
    method = candidate$method,
    confidence = candidate$confidence,
    competition_margin = resolution$competition_margin,
    supporting_cols = resolution$supporting_cols,
    coverage = candidate$coverage,
    n_env = candidate$n_env,
    max_env_per_treatment = candidate$max_env_per_treatment,
    replicated_level_fraction = candidate$replicated_level_fraction
  ))
}

.treatment_key <- function(df, treatment_cols) {
  if (length(treatment_cols) == 0L) {
    return(NULL)
  }
  .interaction_key(df, treatment_cols)
}

.incidence_connectivity <- function(env_key, treatment_key) {
  if (is.null(treatment_key)) {
    return(.connectivity_not_computed())
  }

  n_env <- nlevels(factor(env_key, exclude = NA))
  n_treatments <- nlevels(factor(treatment_key, exclude = NA))
  incidence_cells <- as.double(n_env) * as.double(n_treatments)
  adjacency_cells <- as.double(n_env) * as.double(n_env)
  if (max(incidence_cells, adjacency_cells) >
    CONNECTIVITY_MAX_DENSE_CELLS) {
    reason <- sprintf(
      paste0(
        "%d environments x %d treatments requires up to %.0f dense cells; ",
        "limit is %.0f"
      ),
      n_env, n_treatments,
      max(incidence_cells, adjacency_cells),
      CONNECTIVITY_MAX_DENSE_CELLS
    )
    return(.connectivity_not_computed(reason))
  }

  incidence <- table(env_key, treatment_key, useNA = "no") > 0L
  if (nrow(incidence) == 0L || ncol(incidence) == 0L) {
    return(.connectivity_not_computed("no complete environment-treatment rows"))
  }

  adjacency <- tcrossprod(incidence) > 0L
  env_component <- integer(nrow(adjacency))
  component <- 0L
  for (start in seq_len(nrow(adjacency))) {
    if (env_component[start] != 0L) next
    component <- component + 1L
    pending <- start
    env_component[start] <- component
    while (length(pending) > 0L) {
      current <- pending[1L]
      pending <- pending[-1L]
      neighbours <- which(adjacency[current, ] & env_component == 0L)
      if (length(neighbours) > 0L) {
        env_component[neighbours] <- component
        pending <- c(pending, neighbours)
      }
    }
  }

  treatment_component <- vapply(seq_len(ncol(incidence)), function(j) {
    attached <- which(incidence[, j])
    if (length(attached) == 0L) NA_integer_ else env_component[attached[1L]]
  }, integer(1L))
  component_ids <- seq_len(component)
  component_sizes <- data.frame(
    component = component_ids,
    n_env = vapply(component_ids, function(i) {
      sum(env_component == i)
    }, integer(1L)),
    n_treatments = vapply(component_ids, function(i) {
      sum(treatment_component == i, na.rm = TRUE)
    }, integer(1L))
  )

  environments_per_treatment <- colSums(incidence)
  n_treatments <- length(environments_per_treatment)
  overlap <- list(
    one_environment = mean(environments_per_treatment == 1L),
    two_environments = mean(environments_per_treatment == 2L),
    three_or_more = mean(environments_per_treatment >= 3L),
    zero_cell_fraction = mean(!incidence),
    n_treatments = n_treatments
  )

  list(
    status = if (component == 1L) "connected" else "disconnected",
    components = component,
    component_sizes = component_sizes,
    overlap = overlap,
    reason = character()
  )
}

.roles_for_slice <- function(roles, cols) {
  if (is.null(roles) || !("col" %in% names(roles))) {
    return(NULL)
  }
  out <- roles[roles$col %in% cols, , drop = FALSE]
  for (attribute in c("design", "proposed_actions")) {
    attr(out, attribute) <- NULL
  }
  out
}

.one_per_env_summary <- function(df, rows, env_label, env_cols, roles,
                                 treatment_cols, threshold, tie_delta) {
  slice <- droplevels(df[rows, , drop = FALSE])
  candidate_cols <- setdiff(names(slice), env_cols)
  is_constant <- vapply(slice[candidate_cols], function(x) {
    length(unique(stats::na.omit(x))) <= 1L
  }, logical(1L))
  candidate_cols <- candidate_cols[!is_constant]
  slice <- slice[, candidate_cols, drop = FALSE]

  if (nrow(slice) < 2L || ncol(slice) == 0L) {
    return(data.frame(
      env = env_label, class_label = "none", score = 0,
      treatment_col = paste(treatment_cols, collapse = " + "),
      block_cols = "", spatial_cols = "", n_rows = nrow(slice),
      n_treatments = 0L, stringsAsFactors = FALSE
    ))
  }

  slice_roles <- .roles_for_slice(roles, names(slice))
  detected <- .detect_design_legacy(
    slice,
    roles = slice_roles,
    interactive = FALSE,
    threshold = threshold,
    tie_delta = tie_delta,
    scope = .scope_disabled()
  )
  treatment_present <- intersect(treatment_cols, names(slice))
  n_treatments <- if (length(treatment_present) == 0L) {
    0L
  } else {
    length(unique(stats::na.omit(.interaction_key(slice, treatment_present))))
  }
  score <- if (detected@class_label %in% names(detected@scores)) {
    unname(detected@scores[[detected@class_label]])
  } else if (length(detected@scores) > 0L) {
    max(detected@scores)
  } else {
    0
  }

  data.frame(
    env = env_label,
    class_label = detected@class_label,
    score = score,
    treatment_col = paste(treatment_present, collapse = " + "),
    block_cols = paste(detected@block_cols, collapse = " : "),
    spatial_cols = paste(detected@spatial_cols, collapse = " x "),
    n_rows = nrow(slice),
    n_treatments = as.integer(n_treatments),
    stringsAsFactors = FALSE
  )
}

.per_environment_summary <- function(df, env_key, env_cols, roles,
                                     treatment_cols, threshold, tie_delta) {
  env_levels <- levels(env_key)
  rows_by_env <- split(seq_len(nrow(df)), env_key, drop = TRUE)
  rows <- lapply(env_levels, function(env_label) {
    .one_per_env_summary(
      df = df,
      rows = rows_by_env[[env_label]],
      env_label = env_label,
      env_cols = env_cols,
      roles = roles,
      treatment_cols = treatment_cols,
      threshold = threshold,
      tie_delta = tie_delta
    )
  })
  if (length(rows) == 0L) .empty_per_env() else do.call(rbind, rows)
}

.within_design_label <- function(per_env) {
  if (nrow(per_env) == 0L) {
    return("unresolved")
  }
  labels <- unique(per_env$class_label)
  if (length(labels) == 1L) labels else "mixed"
}

.empty_group_diagnostics <- function() {
  data.frame(
    col = character(),
    n_groups = integer(),
    n_treatments = integer(),
    confined_fraction = numeric(),
    shared_treatments = integer(),
    status = character(),
    stringsAsFactors = FALSE
  )
}

.detect_grouping <- function(df, env_cols, treatment_key) {
  if (is.null(treatment_key)) {
    return(list(cols = character(), diagnostics = .empty_group_diagnostics()))
  }
  pattern <- "^(trial|experiment|study|panel|population|cohort)$"
  candidates <- setdiff(
    names(df)[grepl(pattern, names(df), ignore.case = TRUE, perl = TRUE)],
    env_cols
  )
  if (length(candidates) == 0L) {
    return(list(cols = character(), diagnostics = .empty_group_diagnostics()))
  }

  rows <- lapply(candidates, function(candidate) {
    group_key <- factor(df[[candidate]], exclude = NA)
    incidence <- table(group_key, treatment_key, useNA = "no") > 0L
    groups_per_treatment <- colSums(incidence)
    n_treatments <- length(groups_per_treatment)
    shared <- sum(groups_per_treatment > 1L)
    confined_fraction <- if (n_treatments == 0L) {
      0
    } else {
      mean(groups_per_treatment == 1L)
    }
    max_shared <- max(
      1L,
      as.integer(floor(GROUP_MAX_SHARED_FRACTION * n_treatments))
    )
    eligible <- nrow(incidence) >= 2L &&
      confined_fraction >= GROUP_MIN_CONFINED_FRACTION &&
      shared <= max_shared
    status <- if (!eligible) {
      "interleaved"
    } else if (shared == 0L) {
      "exact_partition"
    } else {
      "near_partition"
    }
    data.frame(
      col = candidate,
      n_groups = nrow(incidence),
      n_treatments = n_treatments,
      confined_fraction = confined_fraction,
      shared_treatments = as.integer(shared),
      status = status,
      stringsAsFactors = FALSE
    )
  })
  diagnostics <- do.call(rbind, rows)
  list(
    cols = diagnostics$col[
      diagnostics$status %in% c("exact_partition", "near_partition")
    ],
    diagnostics = diagnostics
  )
}

.apply_explicit_environment <- function(out, df, roles, env_cols,
                                        threshold, tie_delta) {
  env_key <- .interaction_key(df, env_cols)
  n_env <- nlevels(env_key)
  treatment_cols <- .treatment_basis(out, roles, env_cols)
  treatment_key <- .treatment_key(df, treatment_cols)
  connectivity <- .incidence_connectivity(env_key, treatment_key)
  per_env <- .per_environment_summary(
    df = df,
    env_key = env_key,
    env_cols = env_cols,
    roles = roles,
    treatment_cols = treatment_cols,
    threshold = threshold,
    tie_delta = tie_delta
  )

  out@scope_label <- if (n_env >= 2L) {
    "multi_environment"
  } else {
    "single_environment"
  }
  out@scope_status <- "detected"
  out@scope_confidence <- "high"
  out@is_met <- n_env >= 2L
  out@env_cols <- env_cols
  out@env_method <- if (length(env_cols) == 1L) "user" else "user_composite"
  out@n_env <- as.integer(n_env)
  grouping <- .detect_grouping(df, env_cols, treatment_key)
  out@group_cols <- grouping$cols
  evidence <- out@evidence
  evidence$grouping <- grouping$diagnostics
  out@evidence <- evidence
  out@connectivity <- connectivity
  out@per_env <- per_env
  out@within_design_label <- .within_design_label(per_env)
  if (length(treatment_cols) > 0L) {
    out@treatment_col <- treatment_cols
  }
  out
}
