#' Local-mode categorical synthesis: row-permute observed values
#'
#' Preserves the level set and per-level frequencies exactly; breaks the
#' joint with all other columns by randomly permuting rows. Used for
#' factor / character / logical covariate columns in `mode = "local"`.
#' Collaborate mode applies opaque aliasing on top (build-order step 4).
#'
#' @param x An atomic vector (factor, character, or logical).
#'
#' @return A vector of the same type and length as `x`, with values
#'   permuted across rows.
#' @keywords internal
#' @noRd
synthesise_categorical_local <- function(x) {
  n <- length(x)
  if (n <= 1L) {
    return(x)
  }

  # Permute only within the non-NA positions so the NA pattern is preserved
  # automatically. `mask()` re-applies the original NA mask at orchestration
  # level, but doing it here keeps the per-column contract clean.
  na_idx <- is.na(x)
  if (all(na_idx)) {
    return(x)
  }

  out <- x
  pos_obs <- which(!na_idx)
  permuted <- pos_obs[
    sample.int(length(pos_obs), length(pos_obs), replace = FALSE)
  ]
  out[pos_obs] <- x[permuted]
  out
}
