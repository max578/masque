#' Internal: the masque_recipe_set S7 class
#'
#' The recipe bundle for a multi-table set. Holds one `masque_recipe`
#' per table plus the cross-table link maps that keep shared key / level
#' vocabularies aliased identically across tables. Like a single recipe,
#' it is private and at least as sensitive as the original data.
#'
#' @keywords internal
#' @noRd
masque_recipe_set <- S7::new_class(
  "masque_recipe_set",
  properties = list(
    masque_version = S7::class_character,
    created_at = S7::class_POSIXct,
    mode = S7::class_character,
    recipes = S7::new_property(class = S7::class_list, default = list()),
    links = S7::new_property(class = S7::class_list, default = list()),
    info = S7::new_property(class = S7::class_character, default = character())
  )
)

#' Internal: the masque_set S7 class
#'
#' Container returned by [mask_set()]. Holds the named list of synthetic
#' tables, the (private) recipe bundle, the resolved mode, and the
#' per-table audit data.tables (collaborate mode). Users interact via
#' [synthetic()] and [recipe()], which dispatch on it.
#'
#' @keywords internal
#' @noRd
masque_set <- S7::new_class(
  "masque_set",
  properties = list(
    synthetic = S7::new_property(class = S7::class_list, default = list()),
    recipe = masque_recipe_set,
    mode = S7::class_character,
    audit = S7::new_property(
      class   = S7::new_union(S7::class_list, NULL),
      default = NULL
    )
  )
)

# local(): see the plot method in detect_plot.R.
local(S7::method(print, masque_set) <- function(x, ...) {
  cli::cli_h1("masque_set")
  cli::cli_bullets(c(
    "*" = sprintf("Mode: %s", x@mode),
    "*" = sprintf("Tables: %d", length(x@synthetic))
  ))
  for (nm in names(x@synthetic)) {
    tab <- x@synthetic[[nm]]
    cli::cli_li(
      "{.field {nm}}: {nrow(tab)} row{?s} x {ncol(tab)} column{?s}"
    )
  }
  n_links <- length(x@recipe@links)
  if (n_links) {
    cli::cli_h2(sprintf("Cross-table links (%d)", n_links))
    for (lk in x@recipe@links) {
      cli::cli_li(sprintf(
        "{.val %s} shared across {.val %s}",
        lk$name, paste(lk$tables, collapse = ", ")
      ))
    }
  }
  if (identical(x@mode, "local")) {
    cli::cli_alert_warning(
      "local mode: these surrogates are for owner development only."
    )
  }
  cli::cli_text(
    "Use {.code synthetic(m)} for the tables; {.code recipe(m)} for the bundle."
  )
  cli::cli_text("")
  cli::cli_alert_danger(
    "The recipe bundle is PRIVATE - never share it with the synthetic set."
  )
  invisible(x)})


# local(): see the plot method in detect_plot.R.
local(S7::method(print, masque_recipe_set) <- function(x, ...) {
  cli::cli_h1("masque_recipe_set")
  cli::cli_bullets(c(
    "*" = sprintf("Created: %s", format(x@created_at, "%Y-%m-%d %H:%M:%S %Z")),
    "*" = sprintf("Mode: %s", x@mode),
    "*" = sprintf("Tables: %d", length(x@recipes)),
    "*" = sprintf("masque version: %s", x@masque_version)
  ))

  # Link names and tables only; the shared maps stay redacted.
  if (length(x@links)) {
    cli::cli_h2(sprintf("Cross-table links (%d)", length(x@links)))
    for (lk in x@links) {
      cli::cli_li(sprintf(
        "{.val %s} shared across {.val %s}",
        lk$name, paste(lk$tables, collapse = ", ")
      ))
    }
  }

  for (nm in names(x@recipes)) {
    cli::cli_text("")
    cli::cli_rule(left = "table: {nm}")
    print(x@recipes[[nm]])
  }

  cli::cli_text("")
  cli::cli_alert_danger(
    "The recipe bundle is PRIVATE - never share it with the synthetic set."
  )
  cli::cli_text(
    "Use {.code reveal_maps(rec, table = )} to inspect level maps explicitly."
  )
  invisible(x)})


# local(): see the plot method in detect_plot.R.
local(S7::method(format, masque_recipe_set) <- function(x, ...) {
  sprintf(
    "<masque_recipe_set: mode=%s, tables=%d, links=%d>",
    x@mode, length(x@recipes), length(x@links)
  )})


# local(): see the plot method in detect_plot.R.
local(S7::method(format, masque_set) <- function(x, ...) {
  sprintf(
    "<masque_set: mode=%s, tables=%d, links=%d>",
    x@mode, length(x@synthetic), length(x@recipe@links)
  )})


# Redacted str() and knit_print(): see recipe_print.R.
local({
  str <- utils::str
  S7::method(str, masque_recipe_set) <- .str_redacted
  S7::method(str, masque_set) <- .str_redacted
})

local({
  S7::method(knit_print, masque_recipe_set) <- .knit_print_redacted
  S7::method(knit_print, masque_set) <- .knit_print_redacted
})
