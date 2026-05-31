#' Save a masque recipe to disk
#'
#' Writes the recipe to a single `.rds` file. The default is
#' **runtime-minimal**:
#' no simulator state (copula covariance, raw margins) is written, only the
#' translation maps, factor metadata, storage classes, integrity fingerprint,
#' and warnings. This keeps the saved artefact small and reduces the
#' information that would leak if the recipe file alone were shared.
#'
#' `include_simulator = TRUE` is accepted but is currently a no-op: the
#' recipe does not carry simulator state. The flag is reserved for a
#' future release that will let [read_recipe()] regenerate fresh
#' synthetic samples without access to the original data (see
#' `vignette("roadmap")`).
#'
#' Recipes are at least as sensitive as the original data. Protect the saved
#' file at the same security class as the original.
#'
#' @param rec A `masque_recipe` object, e.g. from `recipe(m)`.
#' @param path File path. By convention, `.rds` extension.
#' @param include_simulator Logical. Reserved for a future release.
#'   Currently a no-op (recipe is always written runtime-minimal).
#'
#' @return `path`, invisibly.
#'
#' @examples
#' r <- propose_roles(iris)
#' r$role[r$col == "Sepal.Length"] <- "outcome"
#' m <- mask(iris, r, mode = "collaborate", seed = 1)
#' tmp <- tempfile(fileext = ".rds")
#' save_recipe(recipe(m), tmp)
#' rec2 <- read_recipe(tmp)
#'
#' @seealso [read_recipe()], [recipe()].
#' @export
save_recipe <- function(rec, path, include_simulator = FALSE) {
  if (!S7::S7_inherits(rec, masque_recipe)) {
    cli::cli_abort(
      "`rec` must be a {.cls masque_recipe} object; got {.cls {class(rec)[1]}}."
    )
  }
  if (!is.character(path) || length(path) != 1L || !nzchar(path)) {
    cli::cli_abort("`path` must be a single non-empty string.")
  }
  if (!is.logical(include_simulator) || length(include_simulator) != 1L) {
    cli::cli_abort("`include_simulator` must be a single logical.")
  }
  # include_simulator is currently a no-op (recipe carries no simulator state).
  saveRDS(rec, file = path, version = 3L)
  invisible(path)
}

#' Read a masque recipe from disk
#'
#' Loads a recipe written by [save_recipe()]. Validates that the file
#' contains a `masque_recipe` and informs (does not error) if the recipe
#' was written by a different package version than the one currently
#' installed.
#'
#' @param path File path.
#'
#' @return A `masque_recipe` object.
#'
#' @seealso [save_recipe()], [recipe()].
#' @export
read_recipe <- function(path) {
  if (!is.character(path) || length(path) != 1L) {
    cli::cli_abort("`path` must be a single string.")
  }
  if (!file.exists(path)) {
    cli::cli_abort("File not found: {.file {path}}.")
  }
  rec <- readRDS(path)
  if (!S7::S7_inherits(rec, masque_recipe)) {
    cli::cli_abort(
      "File at {.file {path}} does not contain a {.cls masque_recipe}."
    )
  }
  current <- as.character(utils::packageVersion("masque"))
  if (!identical(rec@masque_version, current)) {
    cli::cli_inform(c(
      i = paste0(
        "Recipe was written by masque {rec@masque_version}; ",
        "current is {current}."
      ),
      "*" = paste0(
        "Cross-version compatibility is not yet validated. ",
        "Proceed with care."
      )
    ))
  }
  rec
}
