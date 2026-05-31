#' Collaborate-mode opaque aliasing of factor levels
#'
#' Replaces the level vocabulary with opaque aliases of the form
#' `<prefix>_001`, `<prefix>_002`, ... in lexicographic order of the
#' original levels. The aliasing is deterministic given the level order
#' and prefix — no randomness — so a fresh `mask()` call with the same
#' input yields the same aliases.
#'
#' Used by `mask(mode = "collaborate")` on `treatment` and categorical
#' `covariate` columns.
#'
#' @param x A factor or character vector.
#' @param prefix Character scalar used as the alias prefix (e.g., `"trt"`
#'   for treatment, `"<col>_L"` for covariate level).
#' @return A list with elements:
#'   \itemize{
#'     \item `x`: a vector of the same type and length, with aliased values.
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
    width <- max(3L, nchar(as.character(length(lvls))))
    aliases <- sprintf(paste0("%s%0", width, "d"), prefix, seq_along(lvls))
    if (anyDuplicated(aliases)) {
      cli::cli_abort("Aliasing produced duplicate labels (internal bug).")
    }
    map <- stats::setNames(aliases, lvls)
    out <- factor(unname(map[as.character(x)]), levels = unname(aliases))
    return(list(x = out, map = map))
  }
  if (is.character(x)) {
    uvals <- sort(unique(stats::na.omit(x)))
    if (length(uvals) == 0L) {
      return(list(x = x, map = stats::setNames(character(), character())))
    }
    width <- max(3L, nchar(as.character(length(uvals))))
    aliases <- sprintf(paste0("%s%0", width, "d"), prefix, seq_along(uvals))
    if (anyDuplicated(aliases)) {
      cli::cli_abort("Aliasing produced duplicate labels (internal bug).")
    }
    map <- stats::setNames(aliases, uvals)
    out <- unname(ifelse(is.na(x), NA_character_, map[as.character(x)]))
    return(list(x = out, map = map))
  }

  cli::cli_abort(
    "alias_levels() supports factor or character; got {.cls {class(x)[1]}}."
  )
}
