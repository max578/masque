# data_card.R -- data_card(): a C8 v0.1 data card computed from a clone.

#' Write a data card for a masked clone
#'
#' Describes a clone in a data card (card version 0.1): its size, its
#' design columns and, for each column, a role, a kind and counts. An
#' analysis planner can read the card in place of the data. No value of
#' any column is written: a factor's levels are counted, never listed.
#'
#' The card is computed from the clone alone: [synthetic()], the role table
#' from [roles()], the mode, the package version and the column names of any
#' `events` spec given to [mask()]. No other part of the private recipe is
#' read, so the card can travel with the clone. On a clone whose column
#' names were aliased, the card uses the aliases throughout.
#'
#' @section Design block:
#' The design block is copied from the role table, never re-detected. The
#' treatment columns are those with the role `treatment`, and the block
#' columns those with the role `design`, less any named in `env`,
#' `spatial` or `unit`. Environment, spatial and unit columns are named by
#' the caller, since the role table does not tell them apart from blocks.
#' No design class is written. For a linked-event spec, the event pair
#' chosen by `primary_event` gives the event time and status columns, the
#' other status columns of that spec are listed as competing, and the card
#' records the number of rows with the primary status equal to 1 and the
#' share of rows with neither the primary nor a competing event (censored).
#'
#' @section Provenance:
#' Every statistic carries a provenance class.
#' * `structure`: exact in the clone, so equal to the same statistic on the
#'   original table. Row and column counts, missing counts and shares, the
#'   level counts and zero shares of kept and aliased columns and of event
#'   status columns, the treatment, block and event columns, the
#'   environment count and the event count.
#' * `clone_estimate`: re-simulated, so approximate. The level counts and
#'   zero shares of scrambled columns, including event times, and the
#'   censored share.
#' * `analyst`: named in this call: the environment, spatial and unit
#'   columns.
#'
#' @section The YAML file:
#' The card is written by a small deterministic writer: keys in the order of
#' the contract, every string double-quoted and escaped, counts as integers,
#' shares with six decimals, UTF-8 with `\n` line ends. The same clone gives
#' the same bytes.
#'
#' @param m A `masque` object from [mask()], or a `masque_set` from
#'   [mask_set()].
#' @param file Where to write the card in YAML, or `NULL` (the default) to
#'   write nothing. For a set, a directory, which receives one file per
#'   table named `<table>.data_card.yaml`.
#' @param name The table name on the card. Defaults to `"clone"` for a
#'   single table, and to the table names for a set (where `name` may give
#'   one name per table, in order). A name must start with a letter and
#'   hold only letters, digits, `_` and `.`. Any other name is refused with
#'   `masque_bad_card_name_refusal`, never cleaned.
#' @param env,spatial,unit Optional names of clone columns: the environment
#'   columns (trials, sites, years), the columns giving a spatial or temporal
#'   position, and the one column identifying the unit of repeated
#'   measurement. Environment columns must have the role `design`. For a
#'   set, a named list giving the columns per table. A name that is not a
#'   column of the clone is refused with `masque_bad_card_column_refusal`.
#' @param primary_event Which event pair of the first `events` spec is the
#'   card's event time and status, counted in the order the events occur.
#'   Ignored when the clone has no `events` spec.
#'
#' @returns The card as a list, invisibly when `file` is given. For a set, a
#'   named list of cards, one per table.
#'
#' @examples
#' r <- propose_roles(iris)
#' r <- set_role(r, "Species", role = "treatment", action = "alias")
#' r <- set_role(r, "Sepal.Length", role = "outcome")
#' m <- mask(iris, r, seed = 1)
#' card <- data_card(m)
#' card$table
#' card$design
#'
#' path <- tempfile(fileext = ".yaml")
#' data_card(m, file = path)
#' head(readLines(path), 12)
#'
#' @seealso [roles()], [synthetic()], [mask()], [mask_set()].
#'
#' @export
data_card <- function(
  m,
  file = NULL,
  name = NULL,
  env = NULL,
  spatial = NULL,
  unit = NULL,
  primary_event = 1L
) {
  if (S7::S7_inherits(m, masque_set)) {
    return(.data_card_set(m, file, name, env, spatial, unit, primary_event))
  }
  r <- roles(m)
  card <- .card_build(
    m@synthetic,
    r,
    mode = m@mode,
    events = .card_event_specs(m@recipe),
    name = if (is.null(name)) "clone" else name,
    env = env,
    spatial = spatial,
    unit = unit,
    primary_event = primary_event
  )
  if (is.null(file)) {
    return(card)
  }
  .card_write(card, file)
  invisible(card)
}

#' @noRd
.data_card_set <- function(m, file, name, env, spatial, unit, primary_event) {
  tables <- names(m@synthetic)
  if (is.null(name)) {
    name <- tables
  } else if (!is.character(name) || length(name) != length(tables)) {
    .card_refuse(
      "masque_bad_card_name_refusal",
      "For a set, {.arg name} must give one name per table ({length(tables)})."
    )
  }
  for (arg in c("env", "spatial", "unit")) {
    val <- get(arg)
    if (!is.null(val) && (!is.list(val) || !all(names(val) %in% tables))) {
      .card_refuse(
        "masque_bad_card_column_refusal",
        "For a set, {.arg {arg}} must be a list named by table."
      )
    }
  }
  all_roles <- roles(m)
  cards <- lapply(seq_along(tables), function(i) {
    nm <- tables[i]
    .card_build(
      m@synthetic[[nm]],
      all_roles[[nm]],
      mode = m@mode,
      events = .card_event_specs(m@recipe@recipes[[nm]]),
      name = name[i],
      env = env[[nm]],
      spatial = spatial[[nm]],
      unit = unit[[nm]],
      primary_event = primary_event
    )
  })
  names(cards) <- tables
  if (is.null(file)) {
    return(cards)
  }
  dir.create(file, recursive = TRUE, showWarnings = FALSE)
  for (i in seq_along(cards)) {
    .card_write(
      cards[[i]],
      file.path(file, paste0(cards[[i]]$table$name, ".data_card.yaml"))
    )
  }
  invisible(cards)
}

# Building the card ------------------------------------------------------------

# The card from a clone and its public role table. `events` is a list of
# `list(time =, status =)` in the clone's column names.
#' @noRd
.card_build <- function(
  clone,
  roles,
  mode,
  events = list(),
  name = "clone",
  env = NULL,
  spatial = NULL,
  unit = NULL,
  primary_event = 1L
) {
  .check_card_name(name)
  cols <- names(clone)
  role_of <- stats::setNames(roles$role[match(cols, roles$col)], cols)
  action_of <- stats::setNames(roles$action[match(cols, roles$col)], cols)
  if (anyNA(role_of)) {
    .card_refuse(
      "masque_bad_card_roles_refusal",
      "The role table has no row for {.field {cols[is.na(role_of)]}}."
    )
  }
  .check_card_cols(env, cols, "env", role_of, need_design = TRUE)
  .check_card_cols(spatial, cols, "spatial", role_of)
  .check_card_cols(unit, cols, "unit", role_of, single = TRUE)
  ev <- .card_events(clone, events, primary_event)
  exact <- action_of %in% c("keep", "alias")
  names(exact) <- cols
  exact[ev$status_cols] <- TRUE

  # Design ---------------------------------------------------------------------
  design <- list()
  prov <- list()
  treatment <- cols[role_of == "treatment"]
  blocks <- setdiff(cols[role_of == "design"], c(env, spatial, unit))
  if (length(treatment)) {
    design$treatment_cols <- treatment
    prov$treatment_cols <- "structure"
  }
  if (length(blocks)) {
    design$block_cols <- blocks
    prov$block_cols <- "structure"
  }
  if (length(env)) {
    design$env_cols <- env
    prov$env_cols <- "analyst"
  }
  if (length(spatial)) {
    design$spatial_cols <- spatial
    prov$spatial_cols <- "analyst"
  }
  if (length(unit)) {
    design$unit_col <- unit
    prov$unit_col <- "analyst"
  }
  if (length(env)) {
    env_dt <- stats::na.omit(data.table::as.data.table(clone), cols = env)
    design$n_env <- data.table::uniqueN(env_dt, by = env)
    prov$n_env <- if (all(exact[env])) "structure" else "clone_estimate"
  }
  if (!is.null(ev$design)) {
    design <- c(design, ev$design)
    prov <- c(prov, ev$provenance)
  }
  if (length(design)) {
    design$provenance <- prov
  }

  # Columns --------------------------------------------------------------------
  n <- nrow(clone)
  columns <- lapply(cols, function(nm) {
    x <- clone[[nm]]
    kind <- .card_kind(x)
    entry <- list(name = nm, role = role_of[[nm]], kind = kind)
    p <- list(kind = if (sub("ordered", "factor", kind) == roles$kind[
      match(nm, roles$col)
    ]) "structure" else "clone_estimate")
    est <- if (exact[[nm]]) "structure" else "clone_estimate"
    miss <- is.na(x)
    if (kind != "other") {
      entry$n_levels <- data.table::uniqueN(x[!miss])
      p$n_levels <- est
    }
    entry$n_missing <- sum(miss)
    p$n_missing <- "structure"
    entry$na_share <- if (n) round(mean(miss), 6L) else 0
    p$na_share <- "structure"
    if (kind %in% c("numeric", "integer") && any(!miss)) {
      entry$zero_share <- round(mean(x[!miss] == 0), 6L)
      p$zero_share <- est
    }
    entry$provenance <- p
    entry
  })

  card <- list(
    card_version = "0.1",
    produced_by = list(
      package = "masque",
      version = as.character(utils::packageVersion("masque")),
      mode = mode
    ),
    table = list(
      name = name,
      source = "clone",
      n_rows = n,
      n_cols = length(cols),
      provenance = list(n_rows = "structure", n_cols = "structure")
    )
  )
  if (length(design)) {
    card$design <- design
  }
  card$columns <- columns
  card
}

# The event fields of the design block, from the first spec.
#' @noRd
.card_events <- function(clone, events, primary_event) {
  if (!length(events)) {
    return(list(status_cols = character()))
  }
  spec <- events[[1L]]
  k <- length(spec$time)
  if (!is.numeric(primary_event) || length(primary_event) != 1L ||
        is.na(primary_event) || primary_event != round(primary_event) ||
        primary_event < 1 || primary_event > k) {
    .card_refuse(
      "masque_bad_card_event_refusal",
      "{.arg primary_event} must be a whole number from 1 to {k}."
    )
  }
  i <- as.integer(primary_event)
  competing <- spec$status[-i]
  status <- clone[[spec$status[i]]]
  other <- if (length(competing)) {
    Reduce(`|`, lapply(competing, function(s) clone[[s]] == 1))
  } else {
    rep(FALSE, nrow(clone))
  }
  design <- list(
    event_time_col = spec$time[i],
    event_status_col = spec$status[i]
  )
  prov <- list(event_time_col = "structure", event_status_col = "structure")
  if (length(competing)) {
    design$competing_status_cols <- competing
    prov$competing_status_cols <- "structure"
  }
  design$n_events <- sum(status == 1)
  prov$n_events <- "structure"
  design$censored_share <- if (nrow(clone)) {
    round(mean(status == 0 & !other), 6L)
  } else {
    0
  }
  prov$censored_share <- "clone_estimate"
  list(
    design = design,
    provenance = prov,
    status_cols = unlist(lapply(events, `[[`, "status"))
  )
}

# The `events` specs recorded at mask() time, under the clone's names.
#' @noRd
.card_event_specs <- function(rec) {
  map <- rec@column_name_map
  rename <- function(x) {
    hits <- x %in% names(map)
    x[hits] <- unname(unlist(map[x[hits]]))
    x
  }
  lapply(rec@events, function(e) {
    list(time = rename(e$time), status = rename(e$status))
  })
}

#' @noRd
.card_kind <- function(x) {
  if (inherits(x, c("POSIXct", "POSIXlt", "difftime"))) {
    return("datetime")
  }
  if (inherits(x, "Date")) {
    return("date")
  }
  if (is.ordered(x)) {
    return("ordered")
  }
  if (is.factor(x)) {
    return("factor")
  }
  if (is.logical(x)) {
    return("logical")
  }
  if (is.integer(x)) {
    return("integer")
  }
  if (is.numeric(x)) {
    return("numeric")
  }
  if (is.character(x)) {
    return("character")
  }
  "other"
}

# Checks ---------------------------------------------------------------------

#' @noRd
.check_card_name <- function(name) {
  ok <- is.character(name) && length(name) == 1L && !is.na(name) &&
    grepl("^[A-Za-z][A-Za-z0-9_.]*$", name)
  if (!ok) {
    .card_refuse(
      "masque_bad_card_name_refusal",
      c(
        paste0(
          "The card's table name must start with a letter and hold only ",
          "letters, digits, {.val _} and {.val .}."
        ),
        i = "Pass a name that does: {.arg name} is never cleaned."
      )
    )
  }
  invisible(name)
}

#' @noRd
.check_card_cols <- function(
  x,
  cols,
  arg,
  role_of,
  need_design = FALSE,
  single = FALSE
) {
  if (is.null(x)) {
    return(invisible(x))
  }
  if (!is.character(x) || !length(x) || anyNA(x) ||
        (single && length(x) != 1L)) {
    .card_refuse(
      "masque_bad_card_column_refusal",
      paste0(
        "{.arg {arg}} must name ",
        if (single) "one column" else "columns",
        " of the clone."
      )
    )
  }
  absent <- setdiff(x, cols)
  if (length(absent)) {
    .card_refuse(
      "masque_bad_card_column_refusal",
      c(
        "{.arg {arg}} names {length(absent)} column{?s} not in the clone.",
        i = "Use the clone's own column names, as {.fn roles} lists them."
      )
    )
  }
  if (need_design && !all(role_of[x] == "design")) {
    .card_refuse(
      "masque_bad_card_column_refusal",
      "{.arg {arg}} must name columns with the role {.val design}."
    )
  }
  invisible(x)
}

#' @noRd
.card_refuse <- function(class, message) {
  cli::cli_abort(
    message,
    class = c(class, "orchestra_refusal"),
    .envir = parent.frame()
  )
}

# The YAML writer ------------------------------------------------------------

.card_seq_keys <- c(
  "treatment_cols", "block_cols", "env_cols", "spatial_cols",
  "competing_status_cols"
)

#' @noRd
.card_write <- function(card, path) {
  writeBin(charToRaw(enc2utf8(.card_yaml(card))), path)
  invisible(path)
}

#' @noRd
.card_yaml <- function(x) {
  paste0(paste(.yaml_mapping(x, 0L, character()), collapse = "\n"), "\n")
}

#' @noRd
# `seq_keys` are the keys whose character value is a sequence even when it
# holds one name; they apply in the design block only.
.yaml_mapping <- function(x, indent, seq_keys) {
  pad <- strrep(" ", indent)
  out <- character()
  for (k in names(x)) {
    v <- x[[k]]
    key <- paste0(pad, k, ":")
    if (is.list(v) && !is.null(names(v))) {
      inner <- if (k == "design") .card_seq_keys else character()
      out <- c(out, key, .yaml_mapping(v, indent + 2L, inner))
    } else if (is.list(v) || k %in% seq_keys) {
      if (!length(v)) {
        out <- c(out, paste0(key, " []"))
      } else {
        items <- lapply(v, .yaml_item, indent = indent + 2L)
        out <- c(out, key, unlist(items))
      }
    } else {
      out <- c(out, paste(key, .yaml_scalar(v)))
    }
  }
  out
}

#' @noRd
.yaml_item <- function(item, indent) {
  pad <- strrep(" ", indent)
  if (is.list(item)) {
    lines <- .yaml_mapping(item, indent + 2L, character())
    lines[1L] <- paste0(pad, "- ", substring(lines[1L], indent + 3L))
    return(lines)
  }
  paste0(pad, "- ", .yaml_scalar(item))
}

#' @noRd
.yaml_scalar <- function(v) {
  if (is.character(v)) {
    return(.yaml_quote(v))
  }
  if (is.integer(v)) {
    return(as.character(v))
  }
  sprintf("%.6f", v)
}

#' @noRd
.yaml_quote <- function(s) {
  s <- enc2utf8(s)
  s <- gsub("\\", "\\\\", s, fixed = TRUE)
  s <- gsub("\"", "\\\"", s, fixed = TRUE)
  cp <- utf8ToInt(s)
  ctl <- cp < 32L | cp == 127L
  if (any(ctl)) {
    chars <- vapply(cp, intToUtf8, character(1L))
    chars[ctl] <- sprintf("\\u%04X", cp[ctl])
    s <- paste(chars, collapse = "")
  }
  paste0("\"", s, "\"")
}
