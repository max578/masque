#' Local-mode optional seeded permutation of factor levels
#'
#' Returns a vector with the same level vocabulary but with the
#' label-to-row assignment shuffled via a deterministic seeded
#' permutation of levels. The mapping is recorded so that
#' `unmask()` (build-order step 5) can invert.
#'
#' This is the local-mode opt-in path. The collaborate-mode default
#' is `alias_levels()` (opaque rename), not permutation.
#'
#' @param x A factor (or character vector).
#' @return A list with elements:
#'   \itemize{
#'     \item `x`: the permuted vector (same type and length as input).
#'     \item `map`: a named character vector `original -> permuted` covering
#'       every level in `levels(x)` (or every unique value in a character
#'       vector).
#'   }
#' @keywords internal
#' @noRd
permute_levels <- function(x) {
  if (is.factor(x)) {
    lvls <- levels(x)
    if (length(lvls) <= 1L) {
      return(list(x = x, map = stats::setNames(lvls, lvls)))
    }
    perm <- sample(lvls, length(lvls), replace = FALSE)
    map  <- stats::setNames(perm, lvls)
    new_levels <- map
    # Re-label the factor: each value gets its mapped label, levels updated
    out <- factor(map[as.character(x)], levels = unname(perm))
    return(list(x = out, map = map))
  }
  if (is.character(x)) {
    uvals <- unique(stats::na.omit(x))
    if (length(uvals) <= 1L) {
      return(list(x = x, map = stats::setNames(uvals, uvals)))
    }
    perm <- sample(uvals, length(uvals), replace = FALSE)
    map  <- stats::setNames(perm, uvals)
    out  <- ifelse(is.na(x), NA_character_, map[as.character(x)])
    return(list(x = out, map = map))
  }
  cli::cli_abort("permute_levels() supports factor or character; got {.cls {class(x)[1]}}.")
}
