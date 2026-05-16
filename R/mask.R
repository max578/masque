#' Mask a tabular dataset into a structurally faithful development surrogate
#'
#' Takes one data frame and a user-edited `roles` tibble (from
#' [propose_roles()]) and produces a synthetic clone whose experimental
#' design and NA pattern are preserved, while outcome and numeric-covariate
#' values are re-simulated via a Gaussian copula and categorical-covariate
#' values are row-permuted.
#'
#' This function is the single high-level verb of the package. In build-order
#' step 3 only `mode = "local"` is implemented; `mode = "collaborate"`
#' (aliasing + jitter + audit + redacted recipe print) lands in steps 4, 6
#' and 7.
#'
#' @section Behaviour by role:
#'
#' \describe{
#'   \item{`design`}{Byte-identical pass-through.}
#'   \item{`treatment`}{Pass-through in step 3 (level handling lands at step 4).}
#'   \item{`outcome` + numeric `covariate`}{Re-simulated jointly via a
#'     Gaussian copula on global Pearson Sigma. Empirical-quantile marginals
#'     (type 1: returns observed values; collaborate mode adds jitter at
#'     step 7).}
#'   \item{categorical `covariate`}{Row-permuted; level set and per-level
#'     frequencies preserved exactly.}
#'   \item{`ignore`}{Local mode passes through; collaborate mode drops at
#'     step 7.}
#' }
#'
#' The NA pattern is re-applied cell-by-cell after synthesis so
#' `is.na(synthetic) == is.na(original)`.
#'
#' RNG state is preserved across the call (no mutation of `.Random.seed`),
#' wrapped via internal `withr::with_seed()` / `with_preserve_seed()`.
#'
#' @param df A data frame.
#' @param roles A tibble produced by [propose_roles()] (possibly edited).
#' @param mode Either `"local"` (default) or `"collaborate"`.
#'   `"collaborate"` errors with a forward-reference until step 7.
#' @param seed Optional integer for reproducibility; `NULL` (default) uses
#'   whatever RNG state is current and restores it on exit.
#' @param ... Currently ignored (future hook for advanced overrides).
#'
#' @return A `masque` object (S3 list) with elements:
#'   \itemize{
#'     \item `synthetic`: tibble — the synthetic clone.
#'     \item `recipe`: `NULL` in step 3 (populated in step 4).
#'     \item `mode`: the resolved mode.
#'     \item `audit`: `NULL` in step 3 (populated in step 6).
#'     \item `seed`: the seed used (or `NULL`).
#'   }
#'   The class slot is `c("masque", "list")` for now; replaced by an S7
#'   class in step 4.
#'
#' @examples
#' r <- propose_roles(iris)
#' r$role[r$col == "Sepal.Length"] <- "outcome"
#' m <- mask(iris, r, seed = 1)
#' head(m$synthetic)
#'
#' @seealso [propose_roles()], [roles_validate()].
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
  # Defensive: align roles to df column order
  roles <- roles[match(names(df), roles$col), , drop = FALSE]

  if (mode == "collaborate") {
    cli::cli_abort(c(
      "{.code mode = \"collaborate\"} lands in build-order steps 4-7.",
      i = "Use {.code mode = \"local\"} for now."
    ))
  }

  opts <- mode_defaults(mode)

  synth <- with_rng_state(seed, {
    .mask_local_orchestrate(df, roles)
  })

  # NA-mask preservation: cell-by-cell from original
  na_mask <- is.na(df)
  for (j in seq_along(synth)) {
    if (any(na_mask[, j])) {
      synth[[j]][na_mask[, j]] <- NA
    }
  }

  structure(
    list(
      synthetic = tibble::as_tibble(synth),
      recipe    = NULL,
      mode      = mode,
      audit     = NULL,
      seed      = seed
    ),
    class = c("masque", "list")
  )
}

# Internal: orchestrate the per-role synthesis with the RNG state already set.
.mask_local_orchestrate <- function(df, roles) {
  synth <- df

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

  # Categorical covariate: row-permute (independent of numeric)
  cat_idx <- i_covariate[!(roles$kind[i_covariate] %in% c("numeric", "integer"))]
  for (j in cat_idx) {
    col <- roles$col[j]
    synth[[col]] <- synthesise_categorical_local(df[[col]])
  }

  synth
}
