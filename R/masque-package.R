#' masque: Structurally Faithful Development Surrogates for Tabular Data
#'
#' `masque` turns a confidential tabular dataset -- a single table, a
#' folder of files, or a multi-sheet workbook -- into a structurally
#' faithful synthetic clone suitable for pipeline development.
#' Experimental-design columns and the NA pattern are preserved exactly;
#' treatment and categorical-covariate level vocabularies are optionally
#' aliased; outcome and numeric-covariate values are re-simulated via a
#' Gaussian copula that preserves the global covariance structure. A
#' private `recipe` round-trips a pipeline written against the synthetic
#' clone onto the original data.
#'
#' @section Getting started:
#' [masque()] is the one-call front door: it reads the input, proposes a
#' per-column masking plan (a `role` and an `action` for each column;
#' see [propose_roles()] and [set_role()]), masks, audits, and optionally
#' writes the result. A single table flows through [mask()]; a folder,
#' workbook, or named list flows through [mask_set()], which aliases
#' shared keys identically across tables so the synthetic set still
#' joins. [apply_recipe()] and [unmask()] re-target a finished pipeline
#' onto the original data.
#'
#' @section Honest claim:
#' `masque` is **not** a differential-privacy or anonymisation tool. Its outputs
#' are development surrogates: structurally faithful enough that pipeline code
#' runs unchanged, controlled enough that raw values are not exposed in
#' collaborate mode. See `vignette("confidentiality", package = "masque")` for
#' the full threat model and limitations.
#'
#' @section Two modes:
#' - `mode = "local"`: owner's realistic dev surrogate; preserves names and
#'   level vocabularies; may emit observed values; not for external sharing.
#' - `mode = "collaborate"`: opaque aliasing for treatment and
#'   categorical-covariate levels; within-resolution jitter on numerics;
#'   integers stochastically rounded; `audit_mask()` auto-runs at construction.
#'
#' @keywords internal
"_PACKAGE"
