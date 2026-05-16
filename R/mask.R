#' Mask a tabular dataset into a structurally faithful development surrogate
#'
#' Takes one data frame and a user-edited `roles` tibble (from
#' [propose_roles()]) and produces a synthetic clone whose experimental
#' design and NA pattern are preserved, while outcome and numeric-covariate
#' values are re-simulated via a Gaussian copula and categorical-covariate
#' values are row-permuted. Returns a `masque` S7 object holding the
#' synthetic data and a private `masque_recipe`.
#'
#' `mode = "local"` keeps original column / level vocabularies and warns
#' that the synthetic is for owner development only. `mode = "collaborate"`
#' opaque-aliases treatment and categorical-covariate level vocabularies
#' (`trt_001`, `<col>_L01`) and drops `ignore` columns; the resulting
#' synthetic can be passed to a collaborator while the recipe stays
#' private. Numeric jitter, integer stochastic rounding, and automatic
#' `audit_mask()` for collaborate mode arrive in build-order steps 6-7.
#'
#' @section Behaviour by role:
#'
#' \describe{
#'   \item{`design`}{Byte-identical pass-through.}
#'   \item{`treatment`}{Local: pass-through (optional opt-in seeded
#'     permutation via `roles$mask_levels = "permute"`). Collaborate:
#'     opaque alias `trt_NNN`.}
#'   \item{`outcome` + numeric `covariate`}{Re-simulated jointly via a
#'     Gaussian copula on global Pearson covariance. Empirical-quantile
#'     marginals (type 1: returns observed values).}
#'   \item{categorical `covariate`}{Row-permuted within non-NA positions.
#'     Local: vocabulary preserved. Collaborate: opaque alias
#'     `<col>_LNN`.}
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
  if (!is.data.frame(df)) {
    cli::cli_abort("`df` must be a data frame; got {.cls {class(df)[1]}}.")
  }
  mode <- match.arg(mode)
  roles_validate(roles, df)
  roles <- roles[match(names(df), roles$col), , drop = FALSE]

  opts <- mode_defaults(mode)

  result <- with_rng_state(seed, .mask_orchestrate(df, roles, mode, opts))
  synth        <- result$synth
  level_maps   <- result$level_maps
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
    msg <- "local mode: synthetic data is for owner development only, not external sharing."
    warning(msg, call. = FALSE)
    warnings_acc <- c(warnings_acc, msg)
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
    audit     = NULL
  )
}

# Internal: orchestrate the per-role synthesis with the RNG state already set.
.mask_orchestrate <- function(df, roles, mode, opts) {
  synth      <- df
  level_maps <- list()
  warnings   <- character()

  i_treatment <- which(roles$role == "treatment")
  i_outcome   <- which(roles$role == "outcome")
  i_covariate <- which(roles$role == "covariate")

  # Numeric block: outcome + numeric covariates jointly via Gaussian copula
  num_idx <- c(i_outcome, i_covariate)
  num_idx <- num_idx[roles$kind[num_idx] %in% c("numeric", "integer")]
  if (length(num_idx) >= 1L) {
    x_num     <- df[, num_idx, drop = FALSE]
    x_num_new <- synthesise_numeric_local(x_num)
    for (col in names(x_num_new)) {
      synth[[col]] <- x_num_new[[col]]
    }
  }

  # Categorical covariates: row-permute, then (collaborate) opaque-alias
  cat_idx <- i_covariate[!(roles$kind[i_covariate] %in% c("numeric", "integer"))]
  for (j in cat_idx) {
    col  <- roles$col[j]
    perm <- synthesise_categorical_local(df[[col]])
    if (isTRUE(opts$alias_covariate_levels) && (is.factor(perm) || is.character(perm))) {
      res <- alias_levels(perm, prefix = paste0(col, "_L"))
      # prefix "cov_cat_L" + width-3 digit -> "cov_cat_L001"
      synth[[col]] <- res$x
      level_maps[[col]] <- res$map
    } else {
      synth[[col]] <- perm
    }
  }

  # Treatment column: optional local permutation OR collaborate aliasing
  if (length(i_treatment) == 1L) {
    treat_col <- roles$col[i_treatment]
    treat_val <- df[[treat_col]]
    do_alias  <- isTRUE(opts$alias_treatment_levels)
    do_perm   <- (!do_alias) &&
                 "mask_levels" %in% names(roles) &&
                 isTRUE(roles$mask_levels[i_treatment] == "permute")
    if (do_alias && (is.factor(treat_val) || is.character(treat_val))) {
      res <- alias_levels(treat_val, prefix = "trt_")
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
      synth   <- synth[, setdiff(names(synth), dropped), drop = FALSE]
      warnings <- c(warnings,
                    sprintf("Dropped %d ignore column(s) under collaborate mode: %s",
                            length(dropped), paste(dropped, collapse = ", ")))
    }
  }

  list(synth = synth, level_maps = level_maps, warnings = warnings)
}
