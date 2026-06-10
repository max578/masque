#' Translate a data frame into the synthetic namespace
#'
#' Forward translation: takes an `original`-namespace data frame and
#' returns it renamed and re-labelled to match the synthetic namespace
#' produced by [mask()]. Use this to run a pipeline (trained on the
#' synthetic) against the original data without modifying pipeline code.
#'
#' Operations applied (in order):
#'
#' 1. **Verify integrity** by comparing the NA mask of `original` to the
#'    SHA-256 fingerprint stored on the recipe (controlled by
#'    `check_integrity`).
#' 2. **Drop** columns that `mask()` dropped (in `collaborate` mode this is
#'    every `ignore` column; in `local` mode no columns are dropped).
#' 3. **Subset and reorder** to the columns the recipe knows about.
#' 4. **Re-label factors / characters** for any column with a level map
#'    held by the recipe (i.e., treatment and categorical covariates in
#'    `collaborate` mode; or treatment in `local` mode with opt-in
#'    permutation). Unknown non-NA values fail closed.
#' 5. **Rename columns** per `recipe@column_name_map` (currently `NULL`;
#'    reserved for a future opt-in column-aliasing flag — see
#'    `vignette("roadmap")`).
#'
#' Numeric columns are passed through unchanged: the synthetic-namespace
#' for numeric columns is the same as the original. NA cells in the input
#' remain NA in the output (no synthesis is performed here).
#'
#' @param original A data frame in the original namespace.
#' @param rec A `masque_recipe` object (e.g. from `recipe(m)`).
#' @param check_integrity Logical. When `TRUE` (default), verifies that
#'   the NA mask of `original` matches the recipe's recorded
#'   `integrity_fp`. Mismatches error with guidance. Pass `FALSE` to
#'   bypass when the missingness has legitimately changed since the
#'   recipe was built.
#'
#' @return A tibble in the synthetic namespace, ready for the pipeline.
#'
#' @examples
#' r <- propose_roles(iris)
#' r$role[r$col == "Sepal.Length"] <- "outcome"
#' r$role[r$col == "Species"] <- "covariate"
#' m <- mask(iris, r, mode = "collaborate", seed = 1)
#' rec <- recipe(m)
#' iris_in_synth_space <- apply_recipe(iris, rec)
#' head(iris_in_synth_space)
#'
#' @seealso [unmask()], [mask()].
#' @export
apply_recipe <- function(original, rec, check_integrity = TRUE) {
  if (!is.data.frame(original)) {
    cli::cli_abort(
      "`original` must be a data frame; got {.cls {class(original)[1]}}."
    )
  }
  if (!S7::S7_inherits(rec, masque_recipe)) {
    cli::cli_abort(
      "`rec` must be a {.cls masque_recipe} object; got {.cls {class(rec)[1]}}."
    )
  }
  if (!is.logical(check_integrity) || length(check_integrity) != 1L) {
    cli::cli_abort("`check_integrity` must be a single logical.")
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
      paste0(
        "`original` is missing column(s) required by the recipe: ",
        "{.field {missing_in_orig}}."
      ),
      i = "Was the recipe built from a different schema?"
    ))
  }

  if (isTRUE(check_integrity)) {
    .check_recipe_integrity(original, rec)
  }

  out <- original[, retained, drop = FALSE]

  for (col in names(rec@level_maps)) {
    if (!(col %in% names(out))) next
    out[[col]] <- .apply_level_map_forward(
      out[[col]], rec@level_maps[[col]],
      col = col
    )
  }

  if (!is.null(rec@column_name_map)) {
    cmap <- rec@column_name_map
    nm <- names(out)
    hits <- nm %in% names(cmap)
    nm[hits] <- unname(unlist(cmap[nm[hits]]))
    names(out) <- nm
  }

  tibble::as_tibble(out)
}

#' Translate data from the synthetic namespace back to the original
#'
#' Inverse of [apply_recipe()]. Accepts a data frame or an atomic vector.
#' For an atomic factor / character vector with a recipe that holds
#' multiple level maps, `column` must name which map to invert. Atomic
#' numeric, integer, logical, and `Date` / `POSIXct` vectors are
#' returned unchanged (no inverse map applies — these are pass-through
#' under [apply_recipe()] too).
#'
#' The most common pattern is round-tripping pipeline predictions:
#'
#' \preformatted{
#' fit                 <- my_model(synthetic(m))            # train on synthetic
#' orig_in_synth_space <- apply_recipe(original, recipe(m)) # forward
#' preds_synth         <- predict(fit, orig_in_synth_space)
#' preds_orig          <- unmask(preds_synth, recipe(m))    # inverse
#' }
#'
#' Unknown levels (synthetic aliases not in the recipe's map) fail
#' closed with an informative error rather than silently coercing to
#' `NA`.
#'
#' @param x A data frame or an atomic vector to translate from
#'   synthetic-namespace to original-namespace.
#' @param rec A `masque_recipe` object.
#' @param column Optional column name. Only consulted for atomic
#'   factor / character `x` when the recipe holds more than one level
#'   map. Ignored for atomic numeric / logical / Date-like input
#'   (pass-through), but if supplied is validated against the recipe's
#'   known columns.
#'
#' @return An object of the same type as `x`, in the original namespace.
#'
#' @seealso [apply_recipe()], [mask()].
#' @export
unmask <- function(x, rec, column = NULL) {
  if (!S7::S7_inherits(rec, masque_recipe)) {
    cli::cli_abort(
      "`rec` must be a {.cls masque_recipe} object; got {.cls {class(rec)[1]}}."
    )
  }

  if (is.data.frame(x)) {
    out <- x
    if (!is.null(rec@column_name_map)) {
      cmap_inv <- stats::setNames(
        names(rec@column_name_map),
        unlist(unname(rec@column_name_map))
      )
      nm <- names(out)
      hits <- nm %in% names(cmap_inv)
      nm[hits] <- unname(cmap_inv[nm[hits]])
      names(out) <- nm
    }
    for (col in names(rec@level_maps)) {
      if (!(col %in% names(out))) next
      out[[col]] <- .apply_level_map_inverse(
        out[[col]], rec@level_maps[[col]],
        col = col,
        target_class = rec@storage_classes[[col]]
      )
    }
    return(tibble::as_tibble(out))
  }

  if (is.atomic(x) && is.null(dim(x))) {
    # Pass-through for non-categorical atomic input (numeric, integer,
    # logical, Date, POSIXct, ...); these are unchanged by apply_recipe()
    # so they cannot need an inverse map.
    if (!is.character(x) && !is.factor(x)) {
      if (!is.null(column) && length(rec@roles$col) > 0L &&
        !(column %in% rec@roles$col)) {
        cli::cli_abort(c(
          "Column {.field {column}} is not known to the recipe.",
          i = "Available columns: {.val {rec@roles$col}}."
        ))
      }
      return(x)
    }

    # Categorical atomic: need a level map.
    if (length(rec@level_maps) == 0L) {
      cli::cli_abort(c(
        paste0(
          "Recipe holds no level maps; cannot unmask a categorical ",
          "atomic vector."
        ),
        i = paste0(
          "Numeric / logical / Date-like vectors are passed through ",
          "unchanged."
        )
      ))
    }
    if (is.null(column)) {
      if (length(rec@level_maps) == 1L) {
        column <- names(rec@level_maps)[1L]
      } else {
        cli::cli_abort(c(
          paste0(
            "Atomic `x` with multiple level maps in the recipe; ",
            "please supply {.arg column}."
          ),
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
    return(.apply_level_map_inverse(
      x, rec@level_maps[[column]],
      col = column,
      target_class = rec@storage_classes[[column]]
    ))
  }

  cli::cli_abort(
    "`x` must be a data frame or atomic vector; got {.cls {class(x)[1]}}."
  )
}

# Internal: maps an original-label to its synthetic-label.
# Fail-closed: unmapped non-NA values raise an error rather than coerce to NA.
.apply_level_map_forward <- function(val, map, col = NULL) {
  if (is.factor(val) || is.character(val) || is.logical(val)) {
    val_chr <- as.character(val)
    not_na <- !is.na(val_chr)
    unmapped <- not_na & !(val_chr %in% names(map))
    if (any(unmapped)) {
      .fail_unmapped(
        unique(val_chr[unmapped]),
        col = col, direction = "forward"
      )
    }
    new_chr <- ifelse(is.na(val_chr), NA_character_, unname(map[val_chr]))
    if (is.factor(val)) {
      factor(new_chr, levels = unname(map))
    } else {
      new_chr
    }
  } else {
    val
  }
}

# Internal: synthetic-label -> original-label. Fail-closed (see forward).
.apply_level_map_inverse <- function(val, map, col = NULL, target_class = NULL) {
  inv <- stats::setNames(names(map), unname(map))
  if (is.factor(val) || is.character(val) || is.logical(val)) {
    val_chr <- as.character(val)
    not_na <- !is.na(val_chr)
    unmapped <- not_na & !(val_chr %in% names(inv))
    if (any(unmapped)) {
      .fail_unmapped(
        unique(val_chr[unmapped]),
        col = col, direction = "inverse"
      )
    }
    new_chr <- ifelse(is.na(val_chr), NA_character_, unname(inv[val_chr]))
    if (is_logical_class(target_class)) {
      return(as_logical_labels(new_chr))
    }
    if (is.factor(val)) {
      factor(new_chr, levels = unname(inv))
    } else {
      new_chr
    }
  } else {
    val
  }
}

is_logical_class <- function(x) {
  is.character(x) && "logical" %in% x
}

as_logical_labels <- function(x) {
  out <- rep(NA, length(x))
  known <- !is.na(x)
  out[known & x == "TRUE"] <- TRUE
  out[known & x == "FALSE"] <- FALSE
  out
}

.fail_unmapped <- function(bad, col, direction) {
  hint <- if (direction == "forward") {
    "Schema drift or new original-namespace level(s)."
  } else {
    "Schema drift or new synthetic-namespace alias(es)."
  }
  bad_preview <- utils::head(bad, 5L)
  if (is.null(col)) {
    cli::cli_abort(c(
      "Value(s) not in the recipe's level map: {.val {bad_preview}}.",
      i = paste(hint, "Unknown values are not coerced to NA (fail-closed)."),
      "*" = paste0(
        "Rebuild the recipe from a dataset that contains these values, ",
        "or strip them before retargeting."
      )
    ))
  } else {
    cli::cli_abort(c(
      paste0(
        "Value(s) not in the recipe's level map in column ",
        "{.field {col}}: {.val {bad_preview}}."
      ),
      i = paste(hint, "Unknown values are not coerced to NA (fail-closed)."),
      "*" = paste0(
        "Rebuild the recipe from a dataset that contains these values, ",
        "or strip them before retargeting."
      )
    ))
  }
}
