#' Mask a multi-table set with cross-table-consistent aliasing
#'
#' The set-level counterpart to [mask()]. Takes a folder of tabular
#' files, an Excel workbook, or a named list of data frames and produces
#' one synthetic table per input table plus a single private recipe
#' bundle. Columns that are shared across tables - a site code, a
#' genotype name, a plot id appearing in several tables - are aliased
#' *identically everywhere they occur*, so a join written against the
#' synthetic set still resolves on the masked data.
#'
#' @section Links:
#'
#' A *link* is a column name that appears in two or more tables with a
#' compatible kind and overlapping values - the join keys of the set.
#' `mask_set()` proposes links automatically and prints them; pass
#' `links` to override. Linked columns are aliased in place with a shared
#' map (built over the union of values across all tables), so identical
#' original values map to identical aliases in every table. Set a linked
#' column's action to `keep` in its roles table to pass it through
#' unmasked instead.
#'
#' @param input A folder path, an `.xlsx` / `.xls` path, or a named list
#'   of data frames - anything [read_set()] accepts.
#' @param roles Optional named list of roles tables, one per input table
#'   (names must match). When `NULL` (default), [propose_roles()] runs on
#'   each table for the chosen `mode`. Supply edited tables for full
#'   control.
#' @param links Optional override for link detection: a character vector
#'   of column names to treat as cross-table links, or `FALSE` to disable
#'   linking entirely (each table masked independently). When `NULL`
#'   (default), links are detected automatically.
#' @param mode Either `"local"` or `"collaborate"`. When omitted and `roles`
#'   are supplied, inherit their common mode. Tables prepared for different
#'   modes must be reconciled explicitly. Otherwise default to `"local"`.
#' @param seed Optional integer for reproducibility.
#' @param clean Hygiene mode passed to [clean_table()] for every table
#'   (`"auto"`, `"report"`, or `"off"`).
#' @param alias_names Hide column names. `FALSE` (default) keeps them;
#'   `TRUE` aliases every non-link column (linked join keys keep their
#'   names so the synthetic set stays joinable).
#' @param conditional Logical scalar (default `FALSE`). Passed through to
#'   each per-table [mask()] call: when `TRUE`, every table's numeric
#'   block is re-simulated within its own treatment-by-design strata so
#'   the treatment-to-outcome relationship survives the clone. See
#'   [mask()] for the full account.
#' @param quiet Logical; suppress the link / hygiene report.
#'
#' @return A `masque_set` S7 object. Use [synthetic()] for the named list
#'   of synthetic tables and [recipe()] for the private recipe bundle.
#'
#' @examples
#' tables <- list(
#'   plots = data.frame(
#'     site = c("A", "A", "B", "B"),
#'     gen = c("x", "y", "x", "y"),
#'     yield = c(3.1, 2.9, 4.0, 3.7)
#'   ),
#'   sites = data.frame(
#'     site = c("A", "B"),
#'     rainfall = c(420, 560)
#'   )
#' )
#' m <- mask_set(tables, mode = "collaborate", seed = 1, quiet = TRUE)
#' synthetic(m)$plots$site
#' synthetic(m)$sites$site # same aliases -> the join still works
#'
#' @seealso [mask()], [read_set()], [write_set()].
#' @export
mask_set <- function(input,
                     roles = NULL,
                     links = NULL,
                     mode = c("local", "collaborate"),
                     seed = NULL,
                     clean = c("auto", "report", "off"),
                     alias_names = FALSE,
                     conditional = FALSE,
                     quiet = FALSE) {
  withr::local_preserve_seed()
  if (missing(mode)) {
    mode <- "local"
    if (!is.null(roles) && is.list(roles)) {
      role_modes <- unique(vapply(roles, function(role_table) {
        attr(role_table, "mode") %||% NA_character_
      }, character(1L)))
      role_modes <- stats::na.omit(role_modes)
      if (length(role_modes) > 1L) {
        cli::cli_abort(c(
          "Supplied `roles` were prepared for multiple modes.",
          "i" = "Set `mode` explicitly after reconciling the role tables."
        ))
      }
      if (length(role_modes) == 1L) {
        mode <- role_modes[[1L]]
      } else {
        cli::cli_warn(c(
          "No {.arg mode} was supplied and no supplied {.arg roles} table carries mode provenance.",
          "i" = paste0(
            "Defaulting to {.val local}. Pass {.code mode =} explicitly, or keep ",
            "the tibbles from {.fn propose_roles} (a {.fn data.table} or ",
            "{.fn saveRDS} round-trip strips the mode attribute)."
          )
        ), class = "masque_mode_unset")
      }
    }
  }
  mode <- match.arg(mode, c("local", "collaborate"))
  clean <- match.arg(clean)

  tables <- read_set(input)
  table_names <- names(tables)

  # Hygiene per table (names legalised, whitespace trimmed) up front, so
  # link detection and roles see the cleaned schema.
  cleaned <- lapply(tables, function(tab) clean_table(tab, clean, quiet = TRUE))
  tables <- lapply(cleaned, `[[`, "data")

  # Roles: proposed per table unless supplied.
  if (is.null(roles)) {
    roles <- lapply(tables, function(tab) {
      propose_roles(tab, mode = mode)
    })
    names(roles) <- table_names
  } else {
    .check_roles_list(roles, tables)
  }

  # Link detection -> shared alias maps. `.build_shared_maps()` fills each
  # group's `$map` and indexes the maps by table for the mask() calls.
  link_groups <- .resolve_links(tables, roles, links, mode)
  built <- .build_shared_maps(tables, roles, link_groups, mode)
  link_groups <- built$groups
  shared_by_table <- built$shared_by_table

  if (!quiet) .report_links(link_groups)

  # Column-name aliasing target per table: when alias_names = TRUE, alias
  # every column except the linked join keys (which must keep stable
  # names so the synthetic set stays joinable).
  linked_cols <- unique(unlist(lapply(link_groups, `[[`, "name")))

  recipes <- vector("list", length(tables))
  synth_tables <- vector("list", length(tables))
  audits <- vector("list", length(tables))
  names(recipes) <- names(synth_tables) <- names(audits) <- table_names

  for (nm in table_names) {
    aln <- .table_alias_names(alias_names, names(tables[[nm]]), linked_cols)
    m <- mask(
      tables[[nm]],
      roles = roles[[nm]],
      mode = mode,
      seed = seed,
      clean = "off", # already cleaned at set level
      alias_names = aln,
      conditional = conditional,
      .shared_maps = shared_by_table[[nm]]
    )
    synth_tables[[nm]] <- synthetic(m)
    recipes[[nm]] <- recipe(m)
    audits[[nm]] <- m@audit
  }

  link_record <- lapply(link_groups, function(g) {
    list(name = g$name, tables = g$tables, map = g$map)
  })

  rec_set <- masque_recipe_set(
    masque_version = as.character(utils::packageVersion("masque")),
    created_at     = Sys.time(),
    mode           = mode,
    recipes        = recipes,
    links          = link_record
  )

  masque_set(
    synthetic = synth_tables,
    recipe    = rec_set,
    mode      = mode,
    audit     = if (identical(mode, "collaborate")) audits else NULL
  )
}

.check_roles_list <- function(roles, tables) {
  if (!is.list(roles) || is.null(names(roles))) {
    cli::cli_abort("`roles` must be a named list of roles tables.")
  }
  missing <- setdiff(names(tables), names(roles))
  if (length(missing)) {
    cli::cli_abort("`roles` is missing table(s): {.val {missing}}.")
  }
}

# Decide which columns are cross-table links. A candidate is a column
# name present in >= 2 tables with a compatible kind and at least one
# shared value. The user can force a set via `links` or disable with
# FALSE.
.resolve_links <- function(tables, roles, links, mode) {
  if (isFALSE(links)) {
    return(list())
  }

  name_tables <- list()
  for (nm in names(tables)) {
    for (col in names(tables[[nm]])) {
      name_tables[[col]] <- c(name_tables[[col]], nm)
    }
  }
  multi <- names(name_tables)[vapply(name_tables, length, integer(1L)) >= 2L]

  if (is.character(links)) {
    unknown <- setdiff(links, multi)
    if (length(unknown)) {
      cli::cli_abort(c(
        "`links` names column(s) not shared across tables: {.val {unknown}}.",
        i = "Columns appearing in >= 2 tables: {.val {multi}}."
      ))
    }
    multi <- links
  }

  groups <- list()
  for (col in multi) {
    tabs <- name_tables[[col]]
    # Compatible kind across tables and at least one shared value.
    kinds <- vapply(tabs, function(nm) col_kind(tables[[nm]][[col]]),
      character(1L)
    )
    if (!.kinds_compatible(kinds)) next
    vals <- lapply(tabs, function(nm) {
      unique(stats::na.omit(as.character(tables[[nm]][[col]])))
    })
    shared_vals <- Reduce(intersect, vals)
    if (!length(shared_vals)) next
    groups[[col]] <- list(name = col, tables = tabs)
  }
  groups
}

# All categorical, or all numeric/integer: linkable. Mixed kinds are not.
.kinds_compatible <- function(kinds) {
  u <- unique(kinds)
  all(u %in% .categorical_kinds()) ||
    all(u %in% .numeric_kinds())
}

# Build the shared alias map for each link group (over the union of
# values across its tables). Returns the link groups with their `$map`
# filled, plus the maps indexed by table -> col -> map for the mask()
# calls. A link whose column the user kept unmasked in every table is
# dropped (no shared map needed).
.build_shared_maps <- function(tables, roles, link_groups, mode) {
  shared_by_table <- stats::setNames(
    rep(list(list()), length(tables)), names(tables)
  )
  kept_groups <- list()

  for (g in link_groups) {
    col <- g$name
    actions <- vapply(g$tables, function(nm) {
      r <- roles[[nm]]
      a <- r$action[r$col == col]
      if (length(a)) a else NA_character_
    }, character(1L))
    if (all(!is.na(actions) & actions == "keep")) next

    union_vals <- sort(unique(unlist(lapply(g$tables, function(nm) {
      as.character(stats::na.omit(tables[[nm]][[col]]))
    }))))
    if (!length(union_vals)) next

    width <- max(3L, nchar(as.character(length(union_vals))))
    aliases <- sprintf(
      paste0("%s_K%0", width, "d"), col, seq_along(union_vals)
    )
    # Which level receives which alias is a draw from the seeded stream, as
    # in alias_levels(): a lexicographic map is invertible from a public
    # vocabulary alone (M-01, 2026-08-25 audit).
    map <- stats::setNames(aliases[.alias_order(length(union_vals))], union_vals)

    g$map <- map
    kept_groups[[col]] <- g
    for (nm in g$tables) {
      shared_by_table[[nm]][[col]] <- map
    }
  }

  list(groups = kept_groups, shared_by_table = shared_by_table)
}

.table_alias_names <- function(alias_names, cols, linked_cols) {
  if (isFALSE(alias_names)) {
    return(FALSE)
  }
  targets <- if (isTRUE(alias_names)) cols else alias_names
  # Never alias the names of linked join keys - they must stay findable.
  setdiff(intersect(targets, cols), linked_cols)
}

.report_links <- function(link_groups) {
  if (!length(link_groups)) {
    cli::cli_alert_info("No cross-table links detected.")
    return(invisible())
  }
  cli::cli_h2(sprintf("Cross-table links (%d)", length(link_groups)))
  for (g in link_groups) {
    cli::cli_li(sprintf(
      "{.val %s} shared across {.val %s} - aliased consistently",
      g$name, paste(g$tables, collapse = ", ")
    ))
  }
}
