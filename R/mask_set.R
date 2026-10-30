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
#'   of data frames - anything [read_set()] accepts. A list element may also
#'   be a [conform_table()] result: its cleaning record and conform
#'   decisions are used for that table and recorded on its recipe.
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
#' @param ladder Drop order of the conditioning ladder, `"hierarchy"` (default)
#'   or `"levels"`; passed through to each [mask()] call.
#' @param grain Single logical (default `TRUE`); passed through to each
#'   [mask()] call, which synthesises a unit-constant column once per unit.
#' @param allow_kept_outcome Single logical, passed to each [mask()] call:
#'   `TRUE` allows a kept outcome in a collaborate clone and records it.
#' @param quiet Logical; suppress the link / hygiene report, including the
#'   hint that a table looks like documentation.
#' @param sheets For an Excel workbook, the sheets to read (default: all);
#'   passed to [read_set()].
#' @param info Optional character vector of table names (sheet names, or
#'   file names without extension) to set aside as documentation, for
#'   example a data dictionary. They are set aside before masking: not
#'   masked, not in the synthetic set, not written by [write_set()], and
#'   their content is not kept. Their names are
#'   recorded on the recipe bundle. A table that looks like documentation
#'   and is not named here raises a hint (a message of class
#'   `masque_info_hint`); the hint decides nothing.
#' @param ... Must be empty: any argument here is refused with
#'   `masque_unused_arg_refusal`.
#'
#' @return A `masque_set` S7 object. Use [synthetic()] for the named list
#'   of synthetic tables and [recipe()] for the private recipe bundle.
#'
#' @examples
#' tables <- list(
#'   plots = data.frame(
#'     site = rep(c("A", "B", "C", "D", "E"), each = 2),
#'     gen = rep(c("x", "y"), 5),
#'     yield = c(3.1, 2.9, 4.0, 3.7, 3.3, 3.5, 2.8, 3.0, 3.9, 3.6)
#'   ),
#'   sites = data.frame(
#'     site = c("A", "B", "C", "D", "E"),
#'     rainfall = c(420, 560, 390, 610, 480)
#'   )
#' )
#' roles <- lapply(tables, propose_roles, mode = "collaborate")
#' roles <- lapply(roles, set_role, "site", action = "alias")
#' m <- mask_set(tables, roles = roles, seed = 1, quiet = TRUE)
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
                     ladder = c("hierarchy", "levels"),
                     grain = TRUE,
                     allow_kept_outcome = FALSE,
                     quiet = FALSE,
                     sheets = NULL,
                     info = NULL,
                     ...) {
  .refuse_unused_dots("mask_set", ...)
  withr::local_preserve_seed()
  ladder <- match.arg(ladder)
  # Check the shape of `roles` before reading its mode, so a wrong argument
  # is reported as such.
  if (!is.null(roles)) .check_roles_shape(roles)
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
        ), class = c("masque_mode_conflict_refusal", "orchestra_refusal"))
      }
      if (length(role_modes) == 1L) {
        mode <- role_modes[[1L]]
      } else {
        cli::cli_warn(c(
          paste0(
            "No {.arg mode} was supplied and no supplied {.arg roles} table ",
            "carries mode provenance."
          ),
          "i" = paste0(
            "Defaulting to {.val local}. Pass {.code mode =} explicitly, ",
            "or keep the tables from {.fn propose_roles} (a ",
            "{.fn data.table} copy or a CSV round-trip strips the mode ",
            "attribute)."
          )
        ), class = "masque_mode_unset")
      }
    }
  }
  mode <- match.arg(mode, c("local", "collaborate"))
  clean <- match.arg(clean)

  # A table given as a conform_table() result was cleaned and conformed
  # already; its own record is used and its decisions go on its recipe.
  split <- .split_conformance(input)
  tables <- read_set(split$input, sheets = sheets)

  # Documentation tables are set aside before anything reads their content;
  # only their names are kept.
  info <- .check_info(info, names(tables))
  tables <- tables[setdiff(names(tables), info)]
  conformed <- split$conformed[setdiff(names(split$conformed), info)]
  table_names <- names(tables)
  if (!quiet) {
    if (length(info)) {
      cli::cli_alert_info("Set aside, not masked: {.val {info}}.")
    }
    .hint_info(tables)
  }

  # Hygiene per table (names legalised, whitespace trimmed) up front, so
  # link detection and roles see the cleaned schema. Each table's record goes
  # to its recipe so the set round-trips like a single table.
  cleaning <- stats::setNames(vector("list", length(tables)), table_names)
  for (nm in table_names) {
    if (nm %in% names(conformed)) {
      cleaning[[nm]] <- .cleaning_record(conformed[[nm]]$cleaning)
    } else {
      cl <- clean_table(tables[[nm]], clean = clean, quiet = TRUE)
      tables[[nm]] <- cl$data
      cleaning[[nm]] <- .cleaning_record(cl)
    }
  }

  # Roles: proposed per table unless supplied. Supplied roles may name the
  # original headers or the cleaned ones.
  if (is.null(roles)) {
    roles <- lapply(tables, function(tab) {
      propose_roles(tab, mode = mode)
    })
    names(roles) <- table_names
  } else {
    .check_roles_list(roles, tables)
    for (nm in table_names) {
      roles[[nm]] <- .align_roles_cols(
        roles[[nm]], cleaning[[nm]]$name_map, names(tables[[nm]])
      )
    }
  }

  # Link detection -> shared alias maps. `.build_shared_maps()` fills each
  # group's `$map` and indexes the maps by table for the mask() calls.
  link_groups <- .resolve_links(tables, roles, links, mode)
  built <- if (is.null(seed)) {
    .build_shared_maps(tables, roles, link_groups, mode)
  } else {
    with_rng_state(seed, .build_shared_maps(tables, roles, link_groups, mode))
  }
  link_groups <- built$groups
  shared_by_table <- built$shared_by_table

  if (!quiet) .report_links(link_groups)

  # With alias_names = TRUE every column is aliased except the linked join
  # keys, which keep their names so the set stays joinable.
  linked_cols <- unique(unlist(lapply(link_groups, `[[`, "name")))

  recipes <- vector("list", length(tables))
  synth_tables <- vector("list", length(tables))
  audits <- vector("list", length(tables))
  names(recipes) <- names(synth_tables) <- names(audits) <- table_names

  for (nm in table_names) {
    aln <- .table_alias_names(alias_names, names(tables[[nm]]), linked_cols)
    m <- mask(
      conformed[[nm]] %||% tables[[nm]],
      roles = roles[[nm]],
      mode = mode,
      seed = seed,
      alias_names = aln,
      conditional = conditional,
      ladder = ladder,
      grain = grain,
      allow_kept_outcome = allow_kept_outcome,
      .shared_maps = shared_by_table[[nm]],
      .cleaning = cleaning[[nm]]
    )
    synth_tables[[nm]] <- synthetic(m)
    recipes[[nm]] <- .record_links_retained(
      recipe(m), names(shared_by_table[[nm]])
    )
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
    links          = link_record,
    info           = info
  )

  masque_set(
    synthetic = synth_tables,
    recipe    = rec_set,
    mode      = mode,
    audit     = if (identical(mode, "collaborate")) audits else NULL
  )
}

# The same refusal mask() gives: a misspelled argument must not vanish.
.refuse_unused_dots <- function(fn, ...) {
  if (!...length()) {
    return(invisible())
  }
  dot_names <- names(list(...))
  dot_names <- dot_names[nzchar(dot_names)]
  unused <- if (length(dot_names)) {
    paste0(" ", paste0("`", dot_names, "`", collapse = ", "))
  } else {
    ""
  }
  label <- if (...length() == 1L) "argument" else "arguments"
  cli::cli_abort(c(
    paste0("Unused ", label, unused, " passed to `", fn, "()`."),
    i = "Check for misspelled argument names."
  ), class = c("masque_unused_arg_refusal", "orchestra_refusal"))
}

# `info` names tables to set aside: each must be in the set, and at least one
# table must remain to mask.
.check_info <- function(info, table_names) {
  if (is.null(info)) {
    return(character())
  }
  if (!is.character(info) || anyNA(info)) {
    cli::cli_abort(
      "{.arg info} must be a character vector of table names.",
      class = c("masque_bad_info_refusal", "orchestra_refusal")
    )
  }
  unknown <- setdiff(info, table_names)
  if (length(unknown)) {
    cli::cli_abort(c(
      paste0(
        "{.arg info} names {cli::qty(length(unknown))}table{?s} not in ",
        "the set: {.val {unknown}}."
      ),
      i = "Tables: {.val {table_names}}."
    ), class = c("masque_bad_info_refusal", "orchestra_refusal"))
  }
  if (!length(setdiff(table_names, info))) {
    cli::cli_abort(
      "{.arg info} sets aside every table; nothing is left to mask.",
      class = c("masque_bad_info_refusal", "orchestra_refusal")
    )
  }
  unique(info)
}

# Hygiene hint, never a decision: a table named like documentation, or of at
# most three columns with one of long free text, is offered to `info =`.
.INFO_NAME_PATTERN <- paste0(
  "dictionar|read[ ._-]?me|notes|info|meta[ ._-]?data|code[ ._-]?book"
)

.hint_info <- function(tables) {
  looks <- vapply(names(tables), function(nm) {
    .looks_like_info(nm, tables[[nm]])
  }, logical(1L))
  hits <- names(tables)[looks]
  if (!length(hits)) {
    return(invisible())
  }
  cli::cli_inform(c(
    i = paste0(
      "{cli::qty(length(hits))}Table{?s} {.val {hits}} look{?s/} like ",
      "documentation."
    ),
    " " = paste0(
      "Name {cli::qty(length(hits))}{?it/them} in {.arg info} to set ",
      "{?it/them} aside: not masked and not written."
    )
  ), class = "masque_info_hint")
}

.looks_like_info <- function(nm, tab) {
  if (grepl(.INFO_NAME_PATTERN, nm, ignore.case = TRUE)) {
    return(TRUE)
  }
  if (ncol(tab) > 3L) {
    return(FALSE)
  }
  long_text <- vapply(tab, function(x) {
    if (!(is.character(x) || is.factor(x))) {
      return(FALSE)
    }
    x <- as.character(x[!is.na(x)])
    length(x) > 0L && stats::median(nchar(x)) >= 25
  }, logical(1L))
  any(long_text)
}

# Pull conform_table() results out of a list input: `input` with each one
# replaced by its data, and the conformance objects by table name.
.split_conformance <- function(input) {
  if (!is.list(input) || is.data.frame(input) ||
    inherits(input, "masque_conformance")) {
    return(list(input = input, conformed = list()))
  }
  is_cf <- vapply(input, inherits, logical(1L), what = "masque_conformance")
  conformed <- input[is_cf]
  input[is_cf] <- lapply(conformed, `[[`, "data")
  list(input = input, conformed = conformed)
}

# The shape half of the roles check, split out so it can run before the
# mode is inferred from the roles tables' provenance attribute.
.check_roles_shape <- function(roles) {
  if (!is.list(roles) || is.null(names(roles))) {
    cli::cli_abort(
      "`roles` must be a named list of roles tables.",
      class = c("masque_bad_roles_refusal", "orchestra_refusal")
    )
  }
  invisible(roles)
}

.check_roles_list <- function(roles, tables) {
  .check_roles_shape(roles)
  missing <- setdiff(names(tables), names(roles))
  if (length(missing)) {
    cli::cli_abort(
      "`roles` is missing table{?s}: {.val {missing}}.",
      class = c("masque_roles_missing_table_refusal", "orchestra_refusal")
    )
  }
}

# Cross-table links: a column name in two or more tables with a compatible
# kind and a shared value. `links` forces a set; FALSE turns links off.
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
        "`links` names column{?s} not shared across tables: {.val {unknown}}.",
        i = "Columns appearing in >= 2 tables: {.val {multi}}."
      ), class = c("masque_bad_links_refusal", "orchestra_refusal"))
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

# Shared alias map per link group, over the union of its values. A link kept
# unmasked in every table gets no map.
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
    # Random assignment, as in alias_levels(): a sorted map could be inverted
    # from a public vocabulary.
    map <- stats::setNames(
      aliases[.alias_order(length(union_vals))], union_vals
    )

    g$map <- map
    kept_groups[[col]] <- g
    for (nm in g$tables) {
      shared_by_table[[nm]][[col]] <- map
    }
  }

  list(groups = kept_groups, shared_by_table = shared_by_table)
}

# A linked key is aliased by the shared map whatever its own action, so the
# recipe records it as aliased.
.record_links_retained <- function(rec, shared_cols) {
  if (!length(shared_cols)) {
    return(rec)
  }
  roles <- rec@roles
  roles$action[roles$col %in% shared_cols] <- "alias"
  rec@roles <- roles
  rec
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
