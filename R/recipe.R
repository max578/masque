#' Internal: the masque_recipe S7 class
#'
#' Runtime-minimal by default: stores translation maps, role assignments,
#' factor metadata, integrity fingerprint, and warnings. Does NOT store
#' simulator state (Sigma, raw observed margins) unless extended at save
#' time via `include_simulator = TRUE` (build-order step 5).
#'
#' Print methods (defined in R/recipe_print.R) redact `level_maps` by
#' default. Use `reveal_maps()` for an explicit, audited reveal.
#'
#' Not exported. Constructed only via `mask()`.
#'
#' @keywords internal
#' @noRd
masque_recipe <- S7::new_class(
  "masque_recipe",
  properties = list(
    masque_version  = S7::class_character,
    created_at      = S7::class_POSIXct,
    mode            = S7::class_character,
    seed            = S7::new_property(
      class   = S7::new_union(S7::class_integer, NULL),
      default = NULL
    ),
    roles           = S7::class_data.frame,
    column_name_map = S7::new_property(
      class   = S7::new_union(S7::class_list, NULL),
      default = NULL
    ),
    level_maps      = S7::new_property(class = S7::class_list, default = list()),
    storage_classes = S7::new_property(class = S7::class_list, default = list()),
    factor_meta     = S7::new_property(class = S7::class_list, default = list()),
    warnings        = S7::new_property(class = S7::class_character, default = character()),
    integrity_fp    = S7::class_character
  )
)

#' Internal: the masque S7 class
#'
#' Container returned by [mask()]. Holds the synthetic data frame, the
#' (private) recipe, the resolved mode, and (post step 6) the audit
#' tibble. Users interact via the accessors [synthetic()] and [recipe()];
#' the S7 class itself is intentionally not exported.
#'
#' @keywords internal
#' @noRd
masque <- S7::new_class(
  "masque",
  properties = list(
    synthetic = S7::class_data.frame,
    recipe    = masque_recipe,
    mode      = S7::class_character,
    audit     = S7::new_property(
      class   = S7::new_union(S7::class_data.frame, NULL),
      default = NULL
    )
  )
)

#' Extract the synthetic data from a masque object
#'
#' @param m A `masque` object returned by [mask()].
#' @return A tibble: the synthetic data frame.
#' @examples
#' r <- propose_roles(iris)
#' r$role[r$col == "Sepal.Length"] <- "outcome"
#' m <- suppressWarnings(mask(iris, r, seed = 1))
#' head(synthetic(m))
#' @seealso [recipe()], [mask()].
#' @export
synthetic <- function(m) {
  if (!S7::S7_inherits(m, masque)) {
    cli::cli_abort("`m` must be a {.cls masque} object; got {.cls {class(m)[1]}}.")
  }
  m@synthetic
}

#' Extract the recipe from a masque object
#'
#' The recipe is **private**: at least as sensitive as the original data.
#' Never share alongside the synthetic. By default `print(recipe(m))`
#' redacts all level maps; use [reveal_maps()] for an explicit reveal.
#'
#' @param m A `masque` object returned by [mask()].
#' @return A `masque_recipe` S7 object.
#' @examples
#' r <- propose_roles(iris)
#' r$role[r$col == "Sepal.Length"] <- "outcome"
#' m <- suppressWarnings(mask(iris, r, seed = 1))
#' recipe(m)
#' @seealso [synthetic()], [reveal_maps()], [mask()].
#' @export
recipe <- function(m) {
  if (!S7::S7_inherits(m, masque)) {
    cli::cli_abort("`m` must be a {.cls masque} object; got {.cls {class(m)[1]}}.")
  }
  m@recipe
}
