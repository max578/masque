#' Collaborate-mode opaque aliasing of categorical levels
#'
#' Replaces the level vocabulary with opaque aliases of the form
#' `<prefix>_001`, `<prefix>_002`, ..., assigned to the levels by a
#' **random permutation** drawn from the RNG stream `mask()` has already
#' seeded. The alias vocabulary itself is fixed and sorted; which level
#' receives which alias is not.
#'
#' Used by `mask(mode = "collaborate")` on `treatment` and categorical
#' `covariate` columns.
#'
#' @section Why the assignment is randomised:
#' An alias map that follows the levels' sort order is invertible without
#' the recipe by anyone who can guess the vocabulary. Variety rosters, N-rate
#' ladders and site codes are routinely public, and under a sort-order map
#' the k-th alias is by construction the k-th member of the sorted
#' vocabulary, so a holder of the synthetic recovers the whole map by
#' sorting a candidate list. Drawing the assignment from a uniform random
#' permutation removes that: for a k-level column there are `factorial(k)`
#' equally likely maps, and the vocabulary alone no longer says which alias
#' is which.
#'
#' Two consequences follow, and both are the caller's to manage:
#'
#' * The permutation comes from the seeded stream, so `mask(seed = s)`
#'   reproduces the same map. **Treat the seed as recipe-grade confidential
#'   material**: published alongside the synthetic it re-opens the inversion
#'   for anyone who can also reproduce the draw. `mask(seed = NULL)` gives a
#'   fresh map on every call and is the safer setting where reproducibility
#'   is not required.
#' * Randomising the assignment hides the ordering, not the level
#'   frequencies, which are preserved by design. A vocabulary whose
#'   frequencies are known and distinct is still matchable one level at a
#'   time; `audit_mask()` reports the per-column level counts so that
#'   exposure is visible rather than implicit. This is a re-identification
#'   cost, not a differential-privacy guarantee.
#'
#' @param x A factor, character, or logical vector.
#' @param prefix Character scalar used as the alias prefix (e.g., `"trt"`
#'   for treatment, `"<col>_L"` for covariate level).
#' @return A list with elements:
#'   \itemize{
#'     \item `x`: a vector of the same type and length, with aliased values.
#'       For a factor, the levels are the alias vocabulary in its own sorted
#'       order, so the level order carries no trace of the original one.
#'     \item `map`: a named character vector `original -> alias`.
#'   }
#' @keywords internal
#' @noRd
alias_levels <- function(x, prefix) {
  if (!is.character(prefix) || length(prefix) != 1L || !nzchar(prefix)) {
    cli::cli_abort("`prefix` must be a non-empty character scalar.")
  }

  if (is.factor(x)) {
    lvls <- levels(x)
    if (length(lvls) == 0L) {
      return(list(x = x, map = stats::setNames(character(), character())))
    }
    alias_pool <- .alias_pool(prefix, length(lvls))
    map <- stats::setNames(alias_pool[.alias_order(length(lvls))], lvls)
    out <- factor(unname(map[as.character(x)]), levels = alias_pool)
    return(list(x = out, map = map))
  }
  if (is.character(x) || is.logical(x)) {
    x_chr <- as.character(x)
    uvals <- sort(unique(stats::na.omit(x_chr)))
    if (length(uvals) == 0L) {
      return(list(x = x, map = stats::setNames(character(), character())))
    }
    alias_pool <- .alias_pool(prefix, length(uvals))
    map <- stats::setNames(alias_pool[.alias_order(length(uvals))], uvals)
    out <- unname(ifelse(is.na(x_chr), NA_character_, map[x_chr]))
    return(list(x = out, map = map))
  }

  cli::cli_abort(
    paste0(
      "alias_levels() supports factor, character, or logical; ",
      "got {.cls {class(x)[1]}}."
    )
  )
}

# The sorted alias vocabulary for `n` levels. Width is at least three
# digits so the historical `trt_001` spelling is unchanged, and grows with
# the level count so the codes sort in numeric order.
.alias_pool <- function(prefix, n) {
  width <- max(3L, nchar(as.character(n)))
  pool <- sprintf(paste0("%s%0", width, "d"), prefix, seq_len(n))
  if (anyDuplicated(pool)) {
    cli::cli_abort("Aliasing produced duplicate labels (internal bug).")
  }
  pool
}

# Uniform random permutation of the alias index. Drawn from the ambient
# RNG stream, which mask() has seeded via with_rng_state(); a one-level
# column needs no draw and takes none, so adding an alias to a
# single-level column does not move the stream for the columns after it.
.alias_order <- function(n) {
  if (n <= 1L) {
    return(seq_len(n))
  }
  sample.int(n)
}

is_aliasable_level_vector <- function(x) {
  is.factor(x) || is.character(x) || is.logical(x)
}
