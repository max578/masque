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

# local(): see the plot method in detect_plot.R.
local(S7::method(print, masque_recipe) <- function(x, ...) {
  cli::cli_h1("masque_recipe")
  fidelity <- .recipe_fidelity_line(x)
  cli::cli_bullets(c(
    "*" = sprintf("Created: %s", format(x@created_at, "%Y-%m-%d %H:%M:%S %Z")),
    "*" = sprintf("Mode: %s", x@mode),
    "*" = sprintf("Clone fidelity: %s", fidelity),
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

  if (length(x@coords)) {
    cli::cli_h2("Coordinates ({length(x@coords)} pair{?s}, coarsened)")
    for (cr in x@coords) {
      line <- .coord_print_line(cr)
      cli::cli_bullets(c("*" = "{line}"))
    }
  }

  conform <- .prop_or(x, "conform", NULL)
  if (!is.null(conform)) {
    line <- .conform_print_line(conform)
    cli::cli_bullets(c("*" = "{line}"))
  }

  grain <- .prop_or(x, "grain", list())
  if (length(grain)) {
    cli::cli_h2("Grain ({length(grain)} unit{?s})")
    for (g in grain) {
      line <- .grain_print_line(g, x@column_name_map)
      cli::cli_bullets(c("*" = "{line}"))
    }
  }

  events <- .prop_or(x, "events", list())
  if (length(events)) {
    cli::cli_h2("Linked events ({length(events)} group{?s})")
    for (er in events) {
      line <- .event_report_line(er)
      cli::cli_bullets(c("*" = "{line}"))
    }
  }

  n_lvl_maps <- length(x@level_maps)
  n_col_map <- if (is.null(x@column_name_map)) 0L else length(x@column_name_map)
  cli::cli_h2(paste0(
    "Columns ({nrow(x@roles)} total; {n_lvl_maps} level map{?s}; ",
    "{n_col_map} column-name map{?s})"
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

  invisible(x)})


# A property of a recipe written by an older masque may be absent.
.prop_or <- function(x, name, default) {
  if (S7::prop_exists(x, name)) S7::prop(x, name) else default
}

# Counts only: merge sources and targets are original labels.
.conform_print_line <- function(conform) {
  n_merge <- NROW(conform$merges)
  n_type <- NROW(conform$types)
  sprintf(
    "Conformance: %d label merge%s, %d type change%s",
    n_merge, if (n_merge == 1L) "" else "s",
    n_type, if (n_type == 1L) "" else "s"
  )
}


# local(): see the plot method in detect_plot.R.
local(S7::method(format, masque_recipe) <- function(x, ...) {
  sprintf(
    "<masque_recipe: mode=%s, cols=%d, level-maps=%d>",
    x@mode, nrow(x@roles), length(x@level_maps)
  )})


# local(): see the plot method in detect_plot.R.
local(S7::method(print, masque_obj) <- function(x, ...) {
  cli::cli_h1("masque")
  cli::cli_bullets(c(
    "*" = sprintf("Mode: %s", x@mode),
    "*" = cli::pluralize(
      "Synthetic: {nrow(x@synthetic)} row{?s} x {ncol(x@synthetic)} column{?s}"
    ),
    "*" = sprintf(
      "Audit: %s",
      if (is.null(x@audit)) {
        "not run (use audit_mask())"
      } else {
        tally <- .audit_tally(x)
        paste0(
          sprintf(
            "%d HIGH, %d medium, %d low",
            tally[["high"]], tally[["medium"]], tally[["low"]]
          ),
          if (tally[["high"]] > 0L) " - package-managed writing blocked" else ""
        )
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

  invisible(x)})


# local(): see the plot method in detect_plot.R.
local(S7::method(format, masque_obj) <- function(x, ...) {
  sprintf(
    "<masque: mode=%s, synthetic=%d x %d, audit=%s>",
    x@mode, nrow(x@synthetic), ncol(x@synthetic),
    if (is.null(x@audit)) "not run" else "stored"
  )})


# str() shows format() only: any property, present or future, may hold labels.
.str_redacted <- function(object, ...) {
  nest_lev <- list(...)$nest.lev %||% 0L
  cat(" ", format(object), "\n", sep = "")
  if (nest_lev == 0L) {
    cat(
      " Private: properties are not listed. Use print() for the redacted",
      " summary and reveal_maps() for the level maps.\n",
      sep = ""
    )
  }
  invisible(NULL)
}

# The set classes register theirs in recipe_set.R, which collates later.
local({
  str <- utils::str
  S7::method(str, masque_recipe) <- .str_redacted
  S7::method(str, masque_obj) <- .str_redacted
})


# The redacted print as plain text lines, in the order they print.
.redacted_lines <- function(x) {
  lines <- utils::capture.output(
    withCallingHandlers(
      print(x),
      message = function(m) {
        cat(conditionMessage(m))
        invokeRestart("muffleMessage")
      }
    )
  )
  cli::ansi_strip(lines)
}

# knitr is suggested only: the method is registered when knitr loads.
.knit_print_redacted <- function(x, ...) {
  knitr::asis_output(paste0(
    "\n```\n", paste(.redacted_lines(x), collapse = "\n"), "\n```\n"
  ))
}

# S7 finds an external generic by its name in the namespace, so it is bound
# here; S7 registers the methods when knitr loads.
knit_print <- S7::new_external_generic("knitr", "knit_print", "x")

local({
  S7::method(knit_print, masque_recipe) <- .knit_print_redacted
  S7::method(knit_print, masque_obj) <- .knit_print_redacted
})


#' Reveal the level maps held inside a recipe
#'
#' Explicit, audited reveal: prints each `original -> synthetic` level map
#' held by the recipe. **Use sparingly.** Recipe maps are at least as
#' sensitive as the original data; printing them defeats the redaction
#' built into the `print()`, `format()`, `str()` and `knitr::knit_print()`
#' methods of recipes, recipe bundles, `masque` and `masque_set` objects.
#' `saveRDS()` and `dput()` write the maps by design.
#'
#' For each recipe it prints the column-name map (when names were
#' aliased), every level map as `original -> alias`, and the seed. The
#' alias labels follow the scheme described under `alias` in [mask()]:
#' `trt_NNN` or `<col>_trt_NNN` for treatments, `<col>_LNNN`, `<col>_DNNN`,
#' `<col>_INNN` and `<col>_TNNN` for covariates, design columns, ids and
#' text, and `<col>_KNNN` for a key shared across the tables of a set.
#'
#' @param rec A `masque_recipe` object (e.g., from `recipe(m)`), or the
#'   `masque_recipe_set` bundle of a [mask_set()] result.
#' @param table For a bundle, the names of the tables whose maps to reveal.
#'   `NULL` (default) reveals every table. Must be `NULL` for a single
#'   recipe.
#' @return `rec`, invisibly.
#' @examples
#' r <- propose_roles(iris)
#' r$role[r$col == "Sepal.Length"] <- "outcome"
#' r$role[r$col == "Species"] <- "covariate"
#' m <- mask(iris, r, mode = "collaborate", seed = 1)
#' rec <- recipe(m)
#' reveal_maps(rec)
#' @export
reveal_maps <- function(rec, table = NULL) {
  is_set <- S7::S7_inherits(rec, masque_recipe_set)
  if (!is_set && !S7::S7_inherits(rec, masque_recipe)) {
    cli::cli_abort(
      paste0(
        "`rec` must be a {.cls masque_recipe} or {.cls masque_recipe_set} ",
        "object; got {.cls {class(rec)[1]}}."
      ),
      class = c("masque_bad_recipe_refusal", "orchestra_refusal")
    )
  }
  tables <- if (is_set) names(rec@recipes) else character()
  if (!is.null(table)) {
    if (!is_set) {
      cli::cli_abort(
        "`table` applies to a recipe bundle; `rec` is a single recipe.",
        class = c("masque_bad_table_refusal", "orchestra_refusal")
      )
    }
    if (!is.character(table) || !length(table) || anyNA(table) ||
      !all(table %in% tables)) {
      cli::cli_abort(
        c(
          "`table` must name tables in the bundle.",
          i = "Bundle tables: {.val {tables}}."
        ),
        class = c("masque_bad_table_refusal", "orchestra_refusal")
      )
    }
    tables <- table
  }

  cli::cli_alert_warning(
    "Revealing sensitive level maps. Proceed at your discretion."
  )
  cli::cli_text("")

  if (!is_set) {
    .reveal_one(rec)
    return(invisible(rec))
  }
  for (nm in tables) {
    cli::cli_rule(left = "table: {nm}")
    .reveal_one(rec@recipes[[nm]])
    cli::cli_text("")
  }
  invisible(rec)
}

# Internal: print one recipe's column-name map, level maps and seed.
.reveal_one <- function(rec) {
  if (!is.null(rec@column_name_map) && length(rec@column_name_map)) {
    cli::cli_h3("column names (original -> alias)")
    cmap <- rec@column_name_map
    lines <- sprintf(
      "  %s  ->  %s", names(cmap), unname(unlist(cmap))
    )
    cli::cli_verbatim(lines)
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
    cli::cli_verbatim(lines)
  }

  if (length(rec@seed)) {
    cli::cli_h3("seed")
    cli::cli_verbatim(sprintf("  %d", rec@seed))
  }
  invisible(rec)
}

# Internal: one-line clone-fidelity summary. Reports the rung the ladder
# reached, and the pooled fraction when it differs from the one requested.
.recipe_fidelity_line <- function(x) {
  if (!isTRUE(x@conditional)) {
    return("marginal / structural (global copula)")
  }
  requested <- x@conditioning_cols
  used <- tryCatch(x@conditioning_used, error = function(e) requested)
  if (is.null(used)) {
    used <- requested
  }
  frac <- tryCatch(x@fallback_frac, error = function(e) NA_real_)
  if (is.null(frac) || !length(frac)) {
    frac <- NA_real_
  }
  if (!length(used)) {
    return("conditional requested (no conditioning column; pooled fallback)")
  }
  line <- sprintf(
    "conditional (treatment -> outcome preserved; strata: %s)",
    paste(used, collapse = ", ")
  )
  dropped <- setdiff(requested, used)
  if (length(dropped)) {
    line <- sprintf(
      "%s [ladder coarsened; dropped: %s]",
      line, paste(dropped, collapse = ", ")
    )
  }
  shifted <- tryCatch(x@conditioning_shifted, error = function(e) character())
  if (length(shifted)) {
    line <- sprintf(
      "%s [main effects carried as shifts: %s]",
      line, paste(shifted, collapse = ", ")
    )
  }
  if (isTRUE(is.finite(frac)) && frac > 0) {
    line <- sprintf("%s [%.1f%% of rows pooled]", line, 100 * frac)
  }
  line
}
