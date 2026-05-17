# detect_design(): public verb + S7 design_summary class.
#
# Pure orchestration: gather candidates (R/detect_candidates.R), run the
# rule engine (R/detect_rules.R), apply a simpler-design tie-break, and
# wrap the result in an S7 design_summary object.

#' Detect the experimental-design structure of a data frame
#'
#' Inspects `df` and returns an S7 [design_summary] describing the most
#' likely experimental design — one of `"CRD"`, `"RCBD"`,
#' `"IBD/alpha-lattice"`, `"row-column"`, `"split-plot"`, `"factorial"`,
#' or `"none"` (observational / no detectable design).
#'
#' Detection runs six independent rules; each returns a score in
#' \eqn{[0, 1]}. The orchestrator picks the highest-scoring class above
#' `threshold`. Ties within `tie_delta` are broken in favour of the
#' simpler design (CRD < RCBD < factorial < IBD < row-column <
#' split-plot).
#'
#' The detector never edits `df`. Its job is to recommend a role
#' assignment, surface the evidence, and (optionally) draw a sanity
#' check via [plot()].
#'
#' @param df A data frame.
#' @param roles Optional roles tibble (as returned by [propose_roles()]).
#'   When supplied, columns roled `outcome` / `ignore` are excluded from
#'   factor candidates, and any column roled `treatment` is forced as the
#'   working treatment.
#' @param interactive If `TRUE`, when the top-2 rule scores are within
#'   `tie_delta` the user is asked to choose between them via
#'   [cli::cli_menu()]. Default `FALSE`.
#' @param threshold Minimum top-rule score for a class to be reported.
#'   Below this, `class_label` is `"none"`. Default `0.5`.
#' @param tie_delta Score difference within which two rules are treated
#'   as tied. Default `0.02` — tight enough that 0.05-point score
#'   differences (the typical name-bonus / coverage gap) are decisive.
#'
#' @return A [design_summary] S7 object. See [design_summary] for slots.
#'
#' @examples
#' # Classic alpha-lattice (24 genotypes, 3 reps, 6 blocks per rep).
#' if (requireNamespace("agridat", quietly = TRUE)) {
#'   d  <- agridat::john.alpha
#'   ds <- detect_design(d)
#'   print(ds)
#' }
#'
#' # Observational data frame -> class_label "none".
#' detect_design(mtcars)
#'
#' @seealso [propose_roles()] for the role tibble that feeds detection,
#'   [plot.masque::design_summary] for the sanity-check visualisation.
#'
#' @export
detect_design <- function(df,
                          roles       = NULL,
                          interactive = FALSE,
                          threshold   = 0.5,
                          tie_delta   = 0.02) {
  if (!is.data.frame(df)) {
    cli::cli_abort("`df` must be a data frame; got {.cls {class(df)[1]}}.")
  }
  if (nrow(df) < 2L || ncol(df) == 0L) {
    cli::cli_abort("`df` must have at least 2 rows and 1 column.")
  }

  cands <- .propose_candidates(df, roles = roles)

  # Run every rule; collect score + result.
  results <- lapply(.rules_all, function(rule) rule(df, cands))
  names(results) <- names(.rules_all)
  scores <- vapply(results, `[[`, numeric(1L), "score")

  picked <- .pick_top_class(scores, threshold = threshold,
                            tie_delta = tie_delta)

  warnings_msgs <- character(0L)

  # Interactive tie-break.
  if (interactive && !is.na(picked) && length(scores) > 1L) {
    ordered <- sort(scores, decreasing = TRUE)
    top2    <- names(ordered)[1:2]
    if (abs(ordered[1L] - ordered[2L]) <= tie_delta && top2[1L] != top2[2L]) {
      chosen <- .interactive_tie_break(top2, scores, results, df)
      if (!is.na(chosen)) picked <- chosen
    }
  }

  if (is.na(picked)) {
    return(.design_summary_none(scores, cands))
  }

  result <- results[[picked]]
  .build_design_summary(picked, result, scores, cands, warnings_msgs)
}

# Pick the top class label using a simpler-is-better tie-break.
.pick_top_class <- function(scores, threshold, tie_delta) {
  if (length(scores) == 0L) return(NA_character_)
  top <- max(scores)
  if (top < threshold) return(NA_character_)

  # Order from simpler to more complex.
  order_simpler <- c("CRD", "RCBD", "factorial",
                     "IBD/alpha-lattice", "row-column", "split-plot")
  contenders <- names(scores)[scores >= top - tie_delta]
  # Filter to contenders in the simpler-order list, then pick the earliest.
  contenders_ord <- order_simpler[order_simpler %in% contenders]
  if (length(contenders_ord) == 0L) {
    return(names(which.max(scores)))
  }
  contenders_ord[1L]
}

# Interactive disambiguation between two near-tied classes.
.interactive_tie_break <- function(top2, scores, results, df) {
  choices <- vapply(top2, function(nm) {
    ev <- results[[nm]]$evidence
    short <- if (!is.null(ev$treatment_col)) {
      sprintf("treatment=%s", ev$treatment_col)
    } else {
      ""
    }
    sprintf("%s (score=%.2f) %s", nm, scores[[nm]], short)
  }, character(1L))

  ans <- tryCatch(
    cli::cli_menu(
      choices = choices,
      title   = "Two designs are close. Which fits better?",
      not_interactive = top2[1L]
    ),
    error = function(e) NULL
  )
  if (is.null(ans) || is.na(ans)) return(NA_character_)
  top2[ans]
}

.build_design_summary <- function(label, result, scores, cands, warnings_msgs) {
  ev <- result$evidence %||% list()

  treatment_col  <- ev$treatment_col %||% character(0L)
  block_cols     <- character(0L)
  if (!is.null(ev$block_col))   block_cols <- c(block_cols, ev$block_col)
  if (!is.null(ev$block_basis)) block_cols <- unique(c(block_cols, ev$block_basis))
  whole_plot_col <- ev$whole_plot_col %||% character(0L)
  sub_plot_col   <- ev$sub_plot_col   %||% character(0L)
  spatial_cols <- character(0L)
  if (!is.null(ev$row_col) && !is.null(ev$col_col)) {
    spatial_cols <- c(ev$row_col, ev$col_col)
  }
  if (label == "factorial" && !is.null(ev$factor_a) && !is.null(ev$factor_b)) {
    treatment_col <- c(ev$factor_a, ev$factor_b)
  }

  design_summary(
    class_label       = label,
    treatment_col     = treatment_col,
    block_cols        = block_cols,
    whole_plot_col    = whole_plot_col,
    sub_plot_col      = sub_plot_col,
    spatial_cols      = spatial_cols,
    scores            = scores,
    evidence          = ev,
    recommended_roles = result$recommended_roles %||%
                          .empty_recommended_roles(),
    candidates        = cands,
    warnings          = warnings_msgs
  )
}

.design_summary_none <- function(scores, cands) {
  design_summary(
    class_label       = "none",
    treatment_col     = character(0L),
    block_cols        = character(0L),
    whole_plot_col    = character(0L),
    sub_plot_col      = character(0L),
    spatial_cols      = character(0L),
    scores            = scores,
    evidence          = list(reason = "max rule score below threshold"),
    recommended_roles = .empty_recommended_roles(),
    candidates        = cands,
    warnings          = character(0L)
  )
}

.empty_recommended_roles <- function() {
  data.frame(col = character(0L), role = character(0L),
             stringsAsFactors = FALSE)
}

# A tiny null-coalescer used in a handful of places.
`%||%` <- function(a, b) if (is.null(a) || (is.atomic(a) && length(a) == 0L)) b else a

#' S7 design_summary class
#'
#' Returned by [detect_design()]. Slots:
#'
#' \describe{
#'   \item{`class_label`}{One of `"none"`, `"CRD"`, `"RCBD"`,
#'     `"IBD/alpha-lattice"`, `"row-column"`, `"split-plot"`,
#'     `"factorial"`.}
#'   \item{`treatment_col`}{Character vector — the working treatment
#'     column(s). Length 0 if no treatment was identified; length 2 for
#'     factorial.}
#'   \item{`block_cols`}{Character vector — block(s) used by the winning
#'     rule.}
#'   \item{`whole_plot_col`, `sub_plot_col`}{Split-plot only.}
#'   \item{`spatial_cols`}{Length-2 character (`row`, `col`) if a
#'     spatial pair was detected; otherwise empty.}
#'   \item{`scores`}{Named numeric vector — score from every rule.}
#'   \item{`evidence`}{Named list — measurements that drove the winning
#'     rule's score.}
#'   \item{`recommended_roles`}{Data frame with two columns (`col`,
#'     `role`). Fed into [propose_roles()] when `detect = TRUE`.}
#'   \item{`candidates`}{The candidate set used (for `plot()` and
#'     debugging).}
#'   \item{`warnings`}{Character vector — non-blocking diagnostics.}
#' }
#'
#' @keywords internal
#' @export
design_summary <- S7::new_class(
  "design_summary",
  package    = "masque",
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
    warnings          = S7::class_character
  )
)
