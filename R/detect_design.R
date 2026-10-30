# detect_design() and the S7 design_summary class it returns.

#' Detect environment scope and experimental-design structure
#'
#' Inspects `df` and returns an S7 `design_summary`. Environment scope and
#' experimental-design class are separate conclusions: a table can be a
#' multi-environment trial (MET) even when its within-environment randomisation
#' cannot be recovered from the recorded columns.
#'
#' @details
#' With `env = NULL`, exact environment names and a bounded set of site-year
#' patterns are assessed conservatively. A site-only candidate auto-resolves
#' only when treatments are replicated across sites. Weak or competing
#' evidence gives an explicit uncertain result, never a guessed single
#' trial. Supply `env` to define the environment basis, or use `env = FALSE`
#' to run the pre-0.9 whole-table path exactly.
#'
#' Before the scope step, the pooled legacy detector runs six independent
#' design rules. Each returns a score in \eqn{[0, 1]}. The highest-scoring
#' class above `threshold` is one of `"CRD"`, `"RCBD"`,
#' `"IBD/alpha-lattice"`, `"row-column"`, `"split-plot"`, `"factorial"`,
#' or `"none"`. Ties within `tie_delta` favour the simpler design. For a MET,
#' per-environment classes, treatment connectivity, and near-disjoint
#' experiment groups are diagnostics only. Dense connectivity calculations
#' that exceed the package safety bound are reported as `not_computed`.
#' None of these diagnostics proves the original randomisation protocol.
#'
#' When scope resolves, `block_cols` is the block basis the environments
#' agree on, or empty when they disagree; an environment column is never a
#' block. `evidence$block_revision` records the change.
#'
#' A treatment hint found by the rules rather than by a treatment-pattern
#' name is auto-applied only when the column is crossed with a design
#' column. A column with one value per level of a design column, or with an
#' outcome-pattern name, is a covariate and not a candidate.
#'
#' The detector never edits `df`. Its job is to recommend a role
#' assignment, surface the evidence, and (optionally) draw a sanity
#' check via [plot()].
#'
#' @param df A data frame.
#' @param roles Optional roles table (as returned by [propose_roles()]).
#'   When supplied, declared roles constrain candidate generation, and columns
#'   roled `treatment` define the treatment basis.
#' @param interactive If `TRUE`, when the top-2 rule scores are within
#'   `tie_delta` the user is asked to choose between them via a cli
#'   menu. Default `FALSE`.
#' @param threshold Minimum top-rule score for a class to be reported.
#'   Below this, `class_label` is `"none"`. Default `0.5`.
#' @param tie_delta Score difference within which two rules are treated
#'   as tied. Default `0.02` -- tight enough that 0.05-point score
#'   differences (the typical name-bonus / coverage gap) are decisive.
#' @param env Environment specification. `NULL` performs conservative automatic
#'   resolution and leaves ambiguous or weak evidence unresolved. `FALSE`
#'   disables MET handling and runs the legacy whole-table path. A character
#'   vector names one or more columns whose interaction defines the environment.
#'
#' @returns An S7 `design_summary` object. Legacy design fields include
#'   `class_label`,
#'   `treatment_col`, `block_cols`, `whole_plot_col`, `sub_plot_col`,
#'   `spatial_cols`, `scores`, `evidence`, `recommended_roles`,
#'   `candidates`, and `warnings`. Scope fields include `scope_label`,
#'   `scope_status`, `scope_confidence`, `is_met`, `env_cols`, `env_method`,
#'   `n_env`, `group_cols`, `connectivity`, `per_env`, and
#'   `within_design_label`.
#'
#' @examples
#' # Classic alpha-lattice (24 genotypes, 3 reps, 6 blocks per rep).
#' if (requireNamespace("agridat", quietly = TRUE)) {
#'   d <- agridat::john.alpha
#'   ds <- detect_design(d)
#'   print(ds)
#' }
#'
#' # Observational data frame -> class_label "none".
#' detect_design(mtcars)
#'
#' # Explicit two-environment trial.
#' met <- expand.grid(
#'   env = factor(c("E1", "E2")),
#'   rep = factor(seq_len(2L)),
#'   gen = factor(c("G1", "G2", "G3"))
#' )
#' met$yield <- seq_len(nrow(met))
#' met_design <- detect_design(met, env = "env")
#' met_design@scope_label
#' met_design@connectivity$status
#'
#' @seealso [propose_roles()] for the role table that feeds detection and
#'   [plot_design_summary()] for the sanity-check visualisation.
#'
#' @export
detect_design <- function(df,
                          roles = NULL,
                          interactive = FALSE,
                          threshold = 0.5,
                          tie_delta = 0.02,
                          env = NULL) {
  if (!is.data.frame(df)) {
    cli::cli_abort("`df` must be a data frame; got {.cls {class(df)[1]}}.")
  }
  if (nrow(df) < 2L || ncol(df) == 0L) {
    cli::cli_abort("`df` must have at least 2 rows and 1 column.")
  }

  env_spec <- .validate_environment_arg(df, env)
  if (env_spec$mode == "disabled") {
    return(.detect_design_legacy(
      df = df,
      roles = roles,
      interactive = interactive,
      threshold = threshold,
      tie_delta = tie_delta,
      scope = .scope_disabled()
    ))
  }

  out <- .detect_design_legacy(
    df = df,
    roles = roles,
    interactive = interactive,
    threshold = threshold,
    tie_delta = tie_delta,
    scope = .scope_unknown(),
    revise = TRUE
  )

  if (env_spec$mode == "explicit") {
    out <- .apply_explicit_environment(
      out = out,
      df = df,
      roles = roles,
      env_cols = env_spec$cols,
      threshold = threshold,
      tie_delta = tie_delta
    )
  } else if (env_spec$mode == "automatic") {
    resolution <- .resolve_environment(df, out, roles)
    out <- .apply_automatic_environment(
      out = out,
      df = df,
      roles = roles,
      resolution = resolution,
      threshold = threshold,
      tie_delta = tie_delta
    )
  }
  out@recommended_roles <- .normalise_role_recommendations(
    out@recommended_roles, df
  )
  out@recommended_roles <- .gate_treatment_hints(out, df, roles)
  out
}

# Legacy whole-table detector. Keep this path free of environment inference so
# `env = FALSE` remains a stable compatibility escape hatch. `revise = TRUE`
# (scoped path only) applies the candidate revisions of .propose_candidates()
# and names both split-plot factors as the treatment.
.detect_design_legacy <- function(df,
                                  roles = NULL,
                                  interactive = FALSE,
                                  threshold = 0.5,
                                  tie_delta = 0.02,
                                  scope = .scope_unknown(),
                                  revise = FALSE) {

  cands <- .propose_candidates(df, roles = roles, revise = revise)

  # Run every rule; collect score + result.
  results <- lapply(.rules_all, function(rule) rule(df, cands))
  names(results) <- names(.rules_all)
  scores <- vapply(results, `[[`, numeric(1L), "score")

  picked <- .pick_top_class(scores,
    threshold = threshold,
    tie_delta = tie_delta
  )

  warnings_msgs <- character(0L)

  # Interactive tie-break.
  if (interactive && !is.na(picked) && length(scores) > 1L) {
    ordered <- sort(scores, decreasing = TRUE)
    top2 <- names(ordered)[1:2]
    if (abs(ordered[1L] - ordered[2L]) <= tie_delta && top2[1L] != top2[2L]) {
      chosen <- .interactive_tie_break(top2, scores, results, df)
      if (!is.na(chosen)) picked <- chosen
    }
  }

  if (is.na(picked)) {
    return(.design_summary_none(scores, cands, scope = scope))
  }

  result <- results[[picked]]
  out <- .build_design_summary(
    picked, result, scores, cands, warnings_msgs,
    scope = scope
  )
  if (revise && identical(picked, "split-plot")) {
    out@treatment_col <- c(out@whole_plot_col, out@sub_plot_col)
  }
  out
}

# A treatment hint from the design rules stays auto-applied only for a
# treatment-pattern name, a user treatment, or a column crossed with a design
# column; otherwise auto_apply becomes FALSE and the reason says why.
.gate_treatment_hints <- function(out, df, roles) {
  rec <- out@recommended_roles
  hints <- which(
    rec$role == "treatment" & rec$source == "design_rule" & rec$auto_apply
  )
  if (length(hints) == 0L) {
    return(rec)
  }
  named <- union(
    out@candidates$trt_user,
    names(df)[matches_pattern(names(df), TREATMENT_PATTERN)]
  )
  units <- .design_unit_cols(df, roles, extra = out@env_cols)
  for (i in hints) {
    col <- rec$col[i]
    if (col %in% named) next
    problem <- .treatment_evidence_problem(df, col, setdiff(units, col))
    if (!is.na(problem)) {
      rec$auto_apply[i] <- FALSE
      rec$reason[i] <- sprintf("Not applied: %s.", problem)
    }
  }
  rec
}

# Why a column found by the design rules is not a treatment, or NA.
.treatment_evidence_problem <- function(df, col, units) {
  x <- df[[col]]
  if (matches_pattern(col, DESIGN_PATTERN)) {
    return("a design-pattern name")
  }
  if (is.numeric(x) && any(table(x) < 2L)) {
    return("a numeric column with values seen once is a measurement")
  }
  if (length(units) == 0L) {
    return("no design column in the table crosses it")
  }
  unit <- .constant_within_unit(df, col, units)
  if (!is.na(unit)) {
    return(sprintf(
      "one value per level of design column %s (a unit-level covariate)",
      unit
    ))
  }
  crossed <- vapply(units, function(unit) {
    .crossed_with_unit(df, col, unit)
  }, logical(1L))
  if (!any(crossed)) {
    return("not crossed with any design column")
  }
  NA_character_
}

# Pick the top class label using a simpler-is-better tie-break.
.pick_top_class <- function(scores, threshold, tie_delta) {
  if (length(scores) == 0L) {
    return(NA_character_)
  }
  top <- max(scores)
  if (top < threshold) {
    return(NA_character_)
  }

  # Order from simpler to more complex.
  order_simpler <- c(
    "CRD", "RCBD", "factorial",
    "IBD/alpha-lattice", "row-column", "split-plot"
  )
  contenders <- names(scores)[scores >= top - tie_delta]
  # Filter to contenders in the simpler-order list, then pick the earliest.
  contenders_ord <- order_simpler[order_simpler %in% contenders]
  if (length(contenders_ord) == 0L) {
    return(names(which.max(scores)))
  }
  contenders_ord[1L]
}

# Interactive choice between two near-tied classes, via utils::menu().
.interactive_tie_break <- function(top2, scores, results, df) {
  if (!interactive()) {
    return(top2[1L])
  }

  choices <- vapply(top2, function(nm) {
    ev <- results[[nm]]$evidence
    short <- if (!is.null(ev$treatment_col)) {
      sprintf("treatment=%s", ev$treatment_col)
    } else {
      ""
    }
    sprintf("%s (score=%.2f) %s", nm, scores[[nm]], short)
  }, character(1L))

  cli::cli_alert_info("Two designs are close. Which fits better?")
  pick <- tryCatch(
    utils::menu(
      choices = choices, graphics = FALSE,
      title = "Pick one (0 to accept the simpler default)"
    ),
    error = function(e) 0L
  )
  if (is.null(pick) || !is.numeric(pick) || pick < 1L || pick > length(top2)) {
    return(top2[1L])
  }
  top2[pick]
}

.build_design_summary <- function(label, result, scores, cands, warnings_msgs,
                                  scope = .scope_unknown()) {
  ev <- result$evidence %||% list()

  treatment_col <- ev$treatment_col %||% character(0L)
  # `block_cols` always holds the BASIS columns (real names in df).
  # The label (e.g., "rep:block") lives in evidence$block_col for printing.
  block_cols <- character(0L)
  if (!is.null(ev$block_basis)) {
    block_cols <- ev$block_basis
  } else if (!is.null(ev$block_col)) {
    block_cols <- ev$block_col
  }
  whole_plot_col <- ev$whole_plot_col %||% character(0L)
  sub_plot_col <- ev$sub_plot_col %||% character(0L)
  spatial_cols <- character(0L)
  if (!is.null(ev$row_col) && !is.null(ev$col_col)) {
    spatial_cols <- c(ev$row_col, ev$col_col)
  }
  if (label == "factorial" && !is.null(ev$factor_a) && !is.null(ev$factor_b)) {
    treatment_col <- c(ev$factor_a, ev$factor_b)
  }

  design_summary(
    class_label = label,
    treatment_col = treatment_col,
    block_cols = block_cols,
    whole_plot_col = whole_plot_col,
    sub_plot_col = sub_plot_col,
    spatial_cols = spatial_cols,
    scores = scores,
    evidence = ev,
    recommended_roles = data.table::as.data.table(
      result$recommended_roles %||% .empty_recommended_roles()
    ),
    candidates = cands,
    warnings = warnings_msgs,
    scope_label = scope$scope_label,
    scope_status = scope$scope_status,
    scope_confidence = scope$scope_confidence,
    is_met = scope$is_met,
    env_cols = scope$env_cols,
    env_method = scope$env_method,
    n_env = scope$n_env,
    group_cols = scope$group_cols,
    connectivity = scope$connectivity,
    per_env = data.table::as.data.table(scope$per_env),
    within_design_label = scope$within_design_label
  )
}

.design_summary_none <- function(scores, cands, scope = .scope_unknown()) {
  design_summary(
    class_label       = "none",
    treatment_col     = character(0L),
    block_cols        = character(0L),
    whole_plot_col    = character(0L),
    sub_plot_col      = character(0L),
    spatial_cols      = character(0L),
    scores            = scores,
    evidence          = list(reason = "max rule score below threshold"),
    recommended_roles = data.table::as.data.table(.empty_recommended_roles()),
    candidates        = cands,
    warnings          = character(0L),
    scope_label       = scope$scope_label,
    scope_status      = scope$scope_status,
    scope_confidence  = scope$scope_confidence,
    is_met            = scope$is_met,
    env_cols          = scope$env_cols,
    env_method        = scope$env_method,
    n_env             = scope$n_env,
    group_cols        = scope$group_cols,
    connectivity      = scope$connectivity,
    per_env           = data.table::as.data.table(scope$per_env),
    within_design_label = scope$within_design_label
  )
}

.empty_recommended_roles <- function() {
  data.frame(
    col = character(0L), role = character(0L),
    stringsAsFactors = FALSE
  )
}

# A tiny null-coalescer used in a handful of places.
`%||%` <- function(a, b) {
  if (is.null(a) || (is.atomic(a) && length(a) == 0L)) b else a
}

# S7 design_summary class returned by detect_design(); not exported, no Rd.
#' @keywords internal
#' @noRd
design_summary <- S7::new_class(
  "design_summary",
  package = "masque",
  properties = list(
    class_label       = S7::class_character,
    treatment_col     = S7::class_character,
    block_cols        = S7::class_character,
    whole_plot_col    = S7::class_character,
    sub_plot_col      = S7::class_character,
    spatial_cols      = S7::class_character,
    scores            = S7::class_numeric,
    evidence          = S7::class_list,
    recommended_roles = S7::class_data.frame,
    candidates        = S7::class_list,
    warnings          = S7::class_character,
    scope_label       = S7::class_character,
    scope_status      = S7::class_character,
    scope_confidence  = S7::class_character,
    is_met            = S7::class_logical,
    env_cols          = S7::class_character,
    env_method        = S7::class_character,
    n_env             = S7::class_integer,
    group_cols        = S7::class_character,
    connectivity      = S7::class_list,
    per_env           = S7::class_data.frame,
    within_design_label = S7::class_character
  )
)
