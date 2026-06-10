#' Mask a tabular dataset into a structurally faithful development surrogate
#'
#' Takes one data frame and a user-edited `roles` tibble (from
#' [propose_roles()]) and produces a synthetic clone whose experimental
#' design, explicitly-kept columns, and NA pattern are preserved, while
#' outcome and numeric-covariate values are re-simulated via a Gaussian
#' copula and non-numeric covariate values are row-permuted. Returns a
#' `masque` S7 object holding the
#' synthetic data and a private `masque_recipe`.
#'
#' `mode = "local"` keeps original column / level vocabularies and warns
#' that the synthetic is for owner development only. `mode = "collaborate"`
#' opaque-aliases treatment and categorical-covariate level vocabularies
#' (`trt_001`, `<col>_L01`) and drops `ignore` columns; the resulting
#' synthetic can be passed to a collaborator while the recipe stays
#' private. In `collaborate` mode, numeric draws are jittered within
#' their measurement resolution, integer columns are stochastically
#' rounded, and [audit_mask()] runs automatically.
#'
#' @section Behaviour by role:
#'
#' \describe{
#'   \item{`design`}{Byte-identical pass-through.}
#'   \item{`keep`}{Intentional byte-identical pass-through in both modes.}
#'   \item{`treatment`}{Local: pass-through (optional opt-in seeded
#'     permutation via `roles$mask_levels = "permute"`). Collaborate:
#'     opaque alias `trt_NNN`. Designs with two or more treatment factors
#'     (factorial, split-plot) are supported; each factor is aliased
#'     independently as `<col>_trt_NNN` so the labels stay distinct.}
#'   \item{`outcome` + numeric `covariate`}{Re-simulated jointly via a
#'     Gaussian copula on global Pearson covariance. Empirical-quantile
#'     marginals (type 1: returns observed values).}
#'   \item{non-numeric `covariate`}{Row-permuted within non-NA positions.
#'     Date/time classes are preserved. Local: categorical vocabulary
#'     preserved. Collaborate: factor / character / logical levels receive
#'     opaque aliases `<col>_LNN`.}
#'   \item{`ignore`}{Local: passes through. Collaborate: dropped.}
#' }
#'
#' RNG state is preserved across the call.
#'
#' @param df A data frame.
#' @param roles A tibble produced by [propose_roles()] (possibly edited).
#'   May optionally include a `mask_levels` column (`"permute"` enables
#'   local-mode seeded permutation on the treatment column).
#' @param mode Either `"local"` (default) or `"collaborate"`.
#' @param seed Optional integer for reproducibility.
#' @param ... Currently ignored.
#'
#' @return A `masque` S7 object. Use [synthetic()] and [recipe()] to
#'   extract the components.
#'
#' @examples
#' r <- propose_roles(iris)
#' r$role[r$col == "Sepal.Length"] <- "outcome"
#' m <- suppressWarnings(mask(iris, r, seed = 1))
#' head(synthetic(m))
#'
#' @seealso [propose_roles()], [roles_validate()], [synthetic()],
#'   [recipe()], [reveal_maps()].
#'
#' @export
mask <- function(df,
                 roles,
                 mode = c("local", "collaborate"),
                 seed = NULL,
                 ...) {
  # Belt-and-braces RNG hygiene: any RNG perturbation inside mask() is
  # rolled back when the function exits, regardless of which path produced
  # it. The inner with_rng_state still controls per-step reproducibility.
  withr::local_preserve_seed()

  if (!is.data.frame(df)) {
    cli::cli_abort("`df` must be a data frame; got {.cls {class(df)[1]}}.")
  }
  mode <- match.arg(mode)
  roles_validate(roles, df)
  roles <- roles[match(names(df), roles$col), , drop = FALSE]

  opts <- mode_defaults(mode)

  result <- with_rng_state(seed, .mask_orchestrate(df, roles, mode, opts))
  synth <- result$synth
  level_maps <- result$level_maps
  warnings_acc <- result$warnings

  # NA-mask preservation cell-by-cell (only over columns retained)
  retained <- intersect(names(df), names(synth))
  for (col in retained) {
    nm <- is.na(df[[col]])
    if (any(nm)) {
      synth[[col]][nm] <- NA
    }
  }

  if (identical(mode, "local")) {
    msg <- paste0(
      "local mode: synthetic data is for owner development only, ",
      "not external sharing."
    )
    warning(msg, call. = FALSE)
    warnings_acc <- c(warnings_acc, msg)
  }

  # Collaborate mode: auto-run audit and propagate high-leakage warnings
  audit_tbl <- NULL
  if (identical(mode, "collaborate")) {
    # Audit needs a temporary synth-as-tibble + a temporary recipe with the
    # level_maps we collected so far.
    .tmp_rec <- masque_recipe(
      masque_version  = as.character(utils::packageVersion("masque")),
      created_at      = Sys.time(),
      mode            = mode,
      seed            = if (is.null(seed)) NULL else as.integer(seed),
      roles           = as.data.frame(roles),
      column_name_map = NULL,
      level_maps      = level_maps,
      storage_classes = list(),
      factor_meta     = list(),
      warnings        = character(),
      integrity_fp    = ""
    )
    audit_tbl <- .compute_audit(df, synth, .tmp_rec, mode)
    high_leaks <- audit_tbl$col[audit_tbl$leakage_class == "high"]
    if (length(high_leaks)) {
      msg <- sprintf(
        "audit_mask() flagged HIGH leakage on column(s): %s",
        paste(high_leaks, collapse = ", ")
      )
      warning(msg, call. = FALSE)
      warnings_acc <- c(warnings_acc, msg)
    }
  }

  # Build the recipe.
  storage_classes <- lapply(df, function(col) class(col))

  factor_meta <- list()
  for (col in names(df)) {
    if (is.factor(df[[col]])) {
      factor_meta[[col]] <- list(
        levels  = levels(df[[col]]),
        ordered = is.ordered(df[[col]])
      )
    }
  }

  rec <- masque_recipe(
    masque_version  = as.character(utils::packageVersion("masque")),
    created_at      = Sys.time(),
    mode            = mode,
    seed            = if (is.null(seed)) NULL else as.integer(seed),
    roles           = as.data.frame(roles),
    column_name_map = NULL,
    level_maps      = level_maps,
    storage_classes = storage_classes,
    factor_meta     = factor_meta,
    warnings        = warnings_acc,
    integrity_fp    = digest::digest(is.na(df), algo = "sha256")
  )

  masque(
    synthetic = tibble::as_tibble(synth),
    recipe    = rec,
    mode      = mode,
    audit     = audit_tbl
  )
}

# Internal: orchestrate the per-role synthesis with the RNG state already set.
.mask_orchestrate <- function(df, roles, mode, opts) {
  synth <- df
  level_maps <- list()
  warnings <- character()

  i_treatment <- which(roles$role == "treatment")
  i_outcome <- which(roles$role == "outcome")
  i_covariate <- which(roles$role == "covariate")

  # Numeric block: outcome + numeric covariates jointly via Gaussian copula
  num_idx <- c(i_outcome, i_covariate)
  num_idx <- num_idx[roles$kind[num_idx] %in% c("numeric", "integer")]
  if (length(num_idx) >= 1L) {
    x_num <- df[, num_idx, drop = FALSE]
    x_num_new <- synthesise_numeric_local(x_num)
    # Collaborate mode: layer on within-resolution jitter + integer rounding
    if (isTRUE(opts$jitter_numeric)) {
      for (col in names(x_num_new)) {
        x_num_new[[col]] <- synthesise_numeric_collaborate(
          x_obs = df[[col]],
          x_new = x_num_new[[col]]
        )
      }
    }
    for (col in names(x_num_new)) {
      synth[[col]] <- x_num_new[[col]]
    }
  }

  # Non-numeric covariates: row-permute, then (collaborate) opaque-alias
  # factor / character / logical values.
  cat_idx <- i_covariate[
    !(roles$kind[i_covariate] %in% c("numeric", "integer"))
  ]
  for (j in cat_idx) {
    col <- roles$col[j]
    perm <- synthesise_categorical_local(df[[col]])
    if (isTRUE(opts$alias_covariate_levels) &&
      is_aliasable_level_vector(perm)) {
      res <- alias_levels(perm, prefix = paste0(col, "_L"))
      # prefix "cov_cat_L" + width-3 digit -> "cov_cat_L001"
      synth[[col]] <- res$x
      level_maps[[col]] <- res$map
    } else {
      synth[[col]] <- perm
    }
  }

  # Treatment columns: optional local permutation OR collaborate aliasing.
  # Each treatment factor (factorial / split-plot designs carry several) is
  # masked independently. A single treatment keeps the historical `trt_NNN`
  # alias prefix for recipe stability; with two or more, the column name is
  # folded into the prefix (`<col>_trt_NNN`) so the opaque labels stay
  # distinct and self-documenting, mirroring the categorical-covariate
  # convention. Level maps are keyed by column, so each inverts on its own.
  n_treatment <- length(i_treatment)
  for (j in i_treatment) {
    treat_col <- roles$col[j]
    treat_val <- df[[treat_col]]
    do_alias <- isTRUE(opts$alias_treatment_levels)
    do_perm <- (!do_alias) &&
      "mask_levels" %in% names(roles) &&
      isTRUE(roles$mask_levels[j] == "permute")
    if (do_alias && (is.factor(treat_val) || is.character(treat_val))) {
      prefix <- if (n_treatment == 1L) "trt_" else paste0(treat_col, "_trt_")
      res <- alias_levels(treat_val, prefix = prefix)
      synth[[treat_col]] <- res$x
      level_maps[[treat_col]] <- res$map
    } else if (do_perm && (is.factor(treat_val) || is.character(treat_val))) {
      res <- permute_levels(treat_val)
      synth[[treat_col]] <- res$x
      level_maps[[treat_col]] <- res$map
    }
    # else: pass through (local default)
  }

  # Ignore columns: drop in collaborate; pass-through in local
  if (isTRUE(opts$drop_ignore)) {
    i_ignore <- which(roles$role == "ignore")
    if (length(i_ignore)) {
      dropped <- roles$col[i_ignore]
      synth <- synth[, setdiff(names(synth), dropped), drop = FALSE]
      warnings <- c(
        warnings,
        sprintf(
          "Dropped %d ignore column(s) under collaborate mode: %s",
          length(dropped), paste(dropped, collapse = ", ")
        )
      )
    }
  }

  list(synth = synth, level_maps = level_maps, warnings = warnings)
}
