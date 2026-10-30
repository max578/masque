#' Save a masque recipe to disk
#'
#' Writes the recipe to a single `.rds` file. The default is
#' **runtime-minimal**:
#' no simulator state (copula covariance, raw margins) is written, only the
#' translation maps, factor metadata, storage classes, integrity fingerprint,
#' and warnings. This keeps the saved artefact small and reduces the
#' information that would leak if the recipe file alone were shared.
#'
#' `include_simulator = TRUE` is accepted and has no effect: the recipe
#' does not carry simulator state.
#'
#' Recipes are at least as sensitive as the original data. Protect the saved
#' file at the same security class as the original. Note that
#' `save_recipe()` writes plain R serialisation - it does not encrypt.
#' The saved recipe is a re-identification key: store it under your
#' organisation's access controls and key-management practice, not
#' alongside the synthetic output.
#'
#' @param rec A `masque_recipe`, or the `masque_recipe_set` bundle of a
#'   [mask_set()] result, e.g. from `recipe(m)`.
#' @param path File path. By convention, `.rds` extension.
#' @param include_simulator Logical. Has no effect; the recipe is always
#'   written without simulator state.
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
  if (!.is_recipe_like(rec)) {
    cli::cli_abort(
      paste0(
        "`rec` must be a {.cls masque_recipe} or {.cls masque_recipe_set} ",
        "object; got {.cls {class(rec)[1]}}."
      ),
      class = c("masque_bad_recipe_refusal", "orchestra_refusal")
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
#' contains a `masque_recipe` or a `masque_recipe_set` bundle and informs
#' (does not error) if it was written by a different package version than
#' the one currently installed. Bundles are read from masque 0.16.0 on.
#'
#' @param path File path.
#'
#' @return A `masque_recipe`, or a `masque_recipe_set` bundle.
#'
#' @examples
#' r <- propose_roles(iris)
#' r$role[r$col == "Sepal.Length"] <- "outcome"
#' m <- mask(iris, r, mode = "collaborate", seed = 1)
#' tmp <- tempfile(fileext = ".rds")
#' save_recipe(recipe(m), tmp)
#' rec2 <- read_recipe(tmp)
#' rec2
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
  if (!.is_recipe_like(rec)) {
    cli::cli_abort(
      c(
        paste0(
          "File at {.file {path}} does not contain a masque recipe; ",
          "found {.cls {class(rec)[1]}}."
        ),
        i = paste0(
          "{.fn read_recipe} reads a {.cls masque_recipe}, or a ",
          "{.cls masque_recipe_set} bundle from masque 0.16.0 on, as ",
          "written by {.fn save_recipe}."
        )
      ),
      class = c("masque_bad_recipe_file_refusal", "orchestra_refusal")
    )
  }
  what <- if (S7::S7_inherits(rec, masque_recipe_set)) {
    "masque_recipe_set"
  } else {
    "masque_recipe"
  }
  current <- as.character(utils::packageVersion("masque"))
  if (!identical(rec@masque_version, current)) {
    cli::cli_inform(c(
      i = paste0(
        "This {.cls {what}} was written by masque {rec@masque_version}; ",
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

# A single recipe or a set bundle: the objects save_recipe() writes.
.is_recipe_like <- function(x) {
  S7::S7_inherits(x, masque_recipe) || S7::S7_inherits(x, masque_recipe_set)
}
