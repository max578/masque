#' Translate a data frame into the synthetic namespace
#'
#' Forward translation: takes an `original`-namespace data frame and
#' returns it renamed and re-labelled to match the synthetic namespace
#' produced by [mask()]. Use this to run a pipeline (trained on the
#' synthetic) against the original data without modifying pipeline code.
#'
#' Operations applied (in order):
#'
#' 1. **Drop** columns that `mask()` dropped (in `collaborate` mode this is
#'    every `ignore` column; in `local` mode no columns are dropped).
#' 2. **Subset and reorder** to the columns the recipe knows about.
#' 3. **Re-label factors / characters** for any column with a level map
#'    held by the recipe (i.e., treatment and categorical covariates in
#'    `collaborate` mode; or treatment in `local` mode with opt-in
#'    permutation).
#' 4. **Rename columns** per `recipe@column_name_map` (NULL in v0.2;
#'    reserved for v0.3+).
#'
#' Numeric columns are passed through unchanged: the synthetic-namespace
#' for numeric columns is the same as the original. NA cells in the input
#' remain NA in the output (no synthesis is performed here).
#'
#' @param original A data frame in the original namespace.
#' @param rec A `masque_recipe` object (e.g. from `recipe(m)`).
#'
#' @return A tibble in the synthetic namespace, ready for the pipeline.
#'
#' @examples
#' r <- propose_roles(iris)
#' r$role[r$col == "Sepal.Length"] <- "outcome"
#' r$role[r$col == "Species"]      <- "covariate"
#' m   <- mask(iris, r, mode = "collaborate", seed = 1)
#' rec <- recipe(m)
#' iris_in_synth_space <- apply_recipe(iris, rec)
#' head(iris_in_synth_space)
#'
#' @seealso [unmask()], [mask()].
#' @export
apply_recipe <- function(original, rec) {
  if (!is.data.frame(original)) {
    cli::cli_abort("`original` must be a data frame; got {.cls {class(original)[1]}}.")
  }
  if (!S7::S7_inherits(rec, masque_recipe)) {
    cli::cli_abort("`rec` must be a {.cls masque_recipe} object; got {.cls {class(rec)[1]}}.")
  }

  dropped <- if (identical(rec@mode, "collaborate")) {
    rec@roles$col[rec@roles$role == "ignore"]
  } else {
    character()
  }
  retained <- setdiff(rec@roles$col, dropped)

  missing_in_orig <- setdiff(retained, names(original))
  if (length(missing_in_orig)) {
    cli::cli_abort(c(
      "`original` is missing column(s) required by the recipe: {.field {missing_in_orig}}.",
      i = "Was the recipe built from a different schema?"
    ))
  }

  out <- original[, retained, drop = FALSE]

  for (col in names(rec@level_maps)) {
    if (!(col %in% names(out))) next
    out[[col]] <- .apply_level_map_forward(out[[col]], rec@level_maps[[col]])
  }

  if (!is.null(rec@column_name_map)) {
    cmap <- rec@column_name_map
    nm   <- names(out)
    hits <- nm %in% names(cmap)
    nm[hits] <- unname(unlist(cmap[nm[hits]]))
    names(out) <- nm
  }

  tibble::as_tibble(out)
}

#' Translate data from the synthetic namespace back to the original
#'
#' Inverse of [apply_recipe()]. Accepts a data frame **or** an atomic
#' vector. For atomic input, `column` must name which level map to invert.
#'
#' The most common pattern is round-tripping pipeline predictions:
#'
#' \preformatted{
#' fit                 <- my_model(synthetic(m))                # train on synthetic
#' orig_in_synth_space <- apply_recipe(original, recipe(m))     # forward
#' preds_synth         <- predict(fit, orig_in_synth_space)
#' preds_orig          <- unmask(preds_synth, recipe(m))        # inverse
#' }
#'
#' Numeric predictions are unchanged by `unmask()` (no inverse map needed).
#' For predictions that carry factor-level labels (e.g., a classifier
#' predicting a treatment), `unmask()` translates the labels back to the
#' original vocabulary.
#'
#' @param x A data frame or an atomic vector to translate from
#'   synthetic-namespace to original-namespace.
#' @param rec A `masque_recipe` object.
#' @param column Optional column name (only needed when `x` is atomic and
#'   the recipe holds multiple level maps).
#'
#' @return An object of the same type as `x`, in the original namespace.
#'
#' @seealso [apply_recipe()], [mask()].
#' @export
unmask <- function(x, rec, column = NULL) {
  if (!S7::S7_inherits(rec, masque_recipe)) {
    cli::cli_abort("`rec` must be a {.cls masque_recipe} object; got {.cls {class(rec)[1]}}.")
  }

  if (is.data.frame(x)) {
    out <- x
    if (!is.null(rec@column_name_map)) {
      cmap_inv <- stats::setNames(
        names(rec@column_name_map),
        unlist(unname(rec@column_name_map))
      )
      nm  <- names(out)
      hits <- nm %in% names(cmap_inv)
      nm[hits] <- unname(cmap_inv[nm[hits]])
      names(out) <- nm
    }
    for (col in names(rec@level_maps)) {
      if (!(col %in% names(out))) next
      out[[col]] <- .apply_level_map_inverse(out[[col]], rec@level_maps[[col]])
    }
    return(tibble::as_tibble(out))
  }

  if (is.atomic(x) && is.null(dim(x))) {
    if (length(rec@level_maps) == 0L) {
      cli::cli_abort("Recipe holds no level maps; nothing to unmask on an atomic vector.")
    }
    if (is.null(column)) {
      if (length(rec@level_maps) == 1L) {
        column <- names(rec@level_maps)[1L]
      } else {
        cli::cli_abort(c(
          "Atomic `x` with multiple level maps in the recipe; please supply {.arg column}.",
          i = "Available: {.val {names(rec@level_maps)}}."
        ))
      }
    }
    if (!(column %in% names(rec@level_maps))) {
      cli::cli_abort(c(
        "Column {.field {column}} has no level map in this recipe.",
        i = "Available: {.val {names(rec@level_maps)}}."
      ))
    }
    return(.apply_level_map_inverse(x, rec@level_maps[[column]]))
  }

  cli::cli_abort("`x` must be a data frame or atomic vector; got {.cls {class(x)[1]}}.")
}

# Internal: original-label -> synthetic-label
.apply_level_map_forward <- function(val, map) {
  if (is.factor(val)) {
    new_levels <- unname(map[levels(val)])
    val_chr    <- as.character(val)
    factor(unname(map[val_chr]), levels = unname(map[levels(val)]))
  } else if (is.character(val)) {
    unname(ifelse(is.na(val), NA_character_, map[val]))
  } else {
    # Numeric / logical / date -- no map applies
    val
  }
}

# Internal: synthetic-label -> original-label
.apply_level_map_inverse <- function(val, map) {
  inv <- stats::setNames(names(map), unname(map))
  if (is.factor(val)) {
    val_chr    <- as.character(val)
    new_levels <- unname(inv[levels(val)])
    factor(unname(inv[val_chr]), levels = new_levels)
  } else if (is.character(val)) {
    unname(ifelse(is.na(val), NA_character_, inv[val]))
  } else {
    val
  }
}
