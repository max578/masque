#' Redacted print method for masque_recipe
#'
#' Prints a tabular summary of roles and a per-column marker indicating
#' whether a level map is held for that column (`*` = mapped, `=` = no
#' map). **Original level labels are never printed by this method.** Use
#' [reveal_maps()] for an explicit, audited reveal.
#'
#' Registered as both an S7 method (for S7 dispatch) and an S3 method
#' on the masque_recipe class (for legacy S3 generics).
#'
#' @keywords internal
#' @noRd
NULL

S7::method(print, masque_recipe) <- function(x, ...) {
  cli::cli_h1("masque_recipe")
  cli::cli_bullets(c(
    "*" = sprintf("Created: %s", format(x@created_at, "%Y-%m-%d %H:%M:%S %Z")),
    "*" = sprintf("Mode: %s", x@mode),
    "*" = sprintf(
      "Seed: %s",
      if (length(x@seed) == 0L) "NULL" else "present (redacted)"
    ),
    "*" = sprintf("masque version: %s", x@masque_version),
    "*" = sprintf(
      "Integrity fingerprint: %s...",
      substr(x@integrity_fp, 1L, 12L)
    )
  ))

  n_lvl_maps <- length(x@level_maps)
  n_col_map <- if (is.null(x@column_name_map)) 0L else length(x@column_name_map)
  cli::cli_h2(sprintf(
    "Columns (%d total; %d level-map(s); %d column-name map(s))",
    nrow(x@roles), n_lvl_maps, n_col_map
  ))

  marker <- ifelse(x@roles$col %in% names(x@level_maps), "*", "=")
  action <- if ("action" %in% names(x@roles)) {
    x@roles$action
  } else {
    rep("", nrow(x@roles))
  }
  # When column names are aliased, show the opaque alias (the real name
  # stays redacted, like the level maps).
  shown_col <- x@roles$col
  if (!is.null(x@column_name_map)) {
    hits <- shown_col %in% names(x@column_name_map)
    shown_col[hits] <- paste0(
      unname(unlist(x@column_name_map[shown_col[hits]])), " (aliased)"
    )
  }
  body <- sprintf(
    "  %s %-9s %-8s  %-28s  (%s)",
    marker, x@roles$role, action, shown_col, x@roles$kind
  )
  cat(body, sep = "\n")

  if (length(x@warnings)) {
    cli::cli_h2("Warnings")
    for (w in x@warnings) cli::cli_alert_warning(w)
  }

  cli::cli_text("")
  cli::cli_alert_danger(
    "PRIVATE - never share this recipe alongside the synthetic."
  )
  cli::cli_text(
    "Use {.code reveal_maps(rec)} to inspect level maps explicitly."
  )

  invisible(x)
}

S7::method(format, masque_recipe) <- function(x, ...) {
  sprintf(
    "<masque_recipe: mode=%s, cols=%d, level-maps=%d>",
    x@mode, nrow(x@roles), length(x@level_maps)
  )
}

S7::method(print, masque_obj) <- function(x, ...) {
  cli::cli_h1("masque")
  cli::cli_bullets(c(
    "*" = sprintf("Mode: %s", x@mode),
    "*" = sprintf(
      "Synthetic: %d row(s) x %d column(s)",
      nrow(x@synthetic), ncol(x@synthetic)
    ),
    "*" = sprintf(
      "Audit: %s",
      if (is.null(x@audit)) {
        "not run (use audit_mask())"
      } else {
        sprintf("%d row(s)", nrow(x@audit))
      }
    )
  ))

  if (identical(x@mode, "local")) {
    cli::cli_alert_warning(
      paste0(
        "local mode: synthetic data is for owner development only, ",
        "not external sharing."
      )
    )
  }

  cli::cli_text(
    paste0(
      "Use {.code synthetic(m)} to extract data; ",
      "{.code recipe(m)} for the recipe."
    )
  )
  cli::cli_text("")
  print(x@recipe)

  invisible(x)
}

#' Reveal the level maps held inside a recipe
#'
#' Explicit, audited reveal: prints each `original -> synthetic` level map
#' held by the recipe. **Use sparingly.** Recipe maps are at least as
#' sensitive as the original data; printing them defeats the redaction
#' built into [print()] and [summary()].
#'
#' @param rec A `masque_recipe` object (e.g., from `recipe(m)`).
#' @return `rec`, invisibly.
#' @examples
#' r <- propose_roles(iris)
#' r$role[r$col == "Sepal.Length"] <- "outcome"
#' r$role[r$col == "Species"] <- "covariate"
#' m <- suppressWarnings(mask(iris, r, mode = "collaborate", seed = 1))
#' rec <- recipe(m)
#' reveal_maps(rec)
#' @export
reveal_maps <- function(rec) {
  if (!S7::S7_inherits(rec, masque_recipe)) {
    cli::cli_abort(
      "`rec` must be a {.cls masque_recipe} object; got {.cls {class(rec)[1]}}."
    )
  }

  cli::cli_alert_warning(
    "Revealing sensitive level maps. Proceed at your discretion."
  )
  cli::cli_text("")

  if (!is.null(rec@column_name_map) && length(rec@column_name_map)) {
    cli::cli_h3("column names (original -> alias)")
    cmap <- rec@column_name_map
    lines <- sprintf(
      "  %s  ->  %s", names(cmap), unname(unlist(cmap))
    )
    cat(lines, sep = "\n")
  }

  if (length(rec@level_maps) == 0L) {
    if (is.null(rec@column_name_map) || !length(rec@column_name_map)) {
      cli::cli_alert_info("No level maps held in this recipe.")
    }
    return(invisible(rec))
  }

  for (col in names(rec@level_maps)) {
    cli::cli_h3(col)
    map <- rec@level_maps[[col]]
    lines <- sprintf("  %s  ->  %s", names(map), unname(map))
    cat(lines, sep = "\n")
  }

  if (length(rec@seed)) {
    cli::cli_h3("seed")
    cat(sprintf("  %d\n", rec@seed))
  }

  invisible(rec)
}
