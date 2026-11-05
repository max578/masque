# plan.R -- masque_plan(): the roles table and every named spec in one object.

.plan_class <- S7::new_class(
  "masque_plan",
  properties = list(
    roles = S7::class_data.frame,
    coords = S7::class_list,
    events = S7::class_list,
    conditional = S7::new_union(S7::class_logical, S7::class_character),
    ladder = S7::class_character,
    grain = S7::class_logical,
    alias_names = S7::new_union(S7::class_logical, S7::class_character),
    controls = S7::class_list,
    vocabulary = S7::class_character,
    mode = S7::new_union(S7::class_character, NULL)
  )
)

#' A masking plan: roles and named specs in one object
#'
#' Holds what a [mask()] call needs apart from the table: the roles, the
#' coordinate and event declarations, the conditioning choice and any named
#' [control_spec()]s. `mask(df, plan)` reads them from the plan; an argument
#' passed to [mask()] as well overrides the plan's value for that call.
#'
#' At `mask()` each control spec is resolved on the source table and written
#' back: its unit, its strata, the grain of its columns and its effect vector.
#' The clone does not depend on the specs. The resolved plan is on the recipe,
#' and [clone_plan()] gives the same plan in clone vocabulary for the analyst.
#'
#' A spec's `unit`, where not declared, resolves to the coarsest design
#' partition within which `on` is constant, or to the row. Its `strata`, where
#' not declared, resolve to the finest design partition above the unit in which
#' every stratum holds every level of `on`, or to none. A stratum that misses
#' levels of `on` would keep part of the real effect in a negative control, so
#' incomplete blocks are not chosen by default.
#'
#' @param roles A roles table from [propose_roles()].
#' @param coords,events,conditional,ladder,grain,alias_names As in [mask()].
#' @param controls `NULL`, one [control_spec()], or a named list of them. A
#'   single spec is named `default`.
#'
#' @returns A `masque_plan` object.
#'
#' @examples
#' trial <- read.csv(system.file("extdata", "john_alpha.csv", package = "masque"))
#' r <- propose_roles(trial, detect = FALSE)
#' r <- set_role(r, c("rep", "block"), role = "design", action = "keep")
#' r <- set_role(r, "gen", role = "treatment", action = "alias")
#' r <- set_role(r, "yield", role = "outcome", action = "scramble")
#' r <- set_role(r, c("plot", "row", "col"), role = "id", action = "keep")
#' p <- masque_plan(
#'   r,
#'   conditional = "design",
#'   controls = control_spec(
#'     on = "gen", target = "yield", effect = list(sd = 0.5), n = 5L, seed = 7L
#'   )
#' )
#' p
#' m <- mask(trial, p, mode = "local", seed = 1L)
#' clone_plan(m)
#'
#' @seealso [mask()], [clone_plan()], [save_plan()], [controls()], [handover()].
#'
#' @export
masque_plan <- function(
  roles,
  coords = NULL,
  events = NULL,
  conditional = FALSE,
  ladder = c("hierarchy", "levels"),
  grain = TRUE,
  alias_names = FALSE,
  controls = NULL
) {
  if (!is.data.frame(roles)) {
    .plan_refuse("`roles` must be a data frame; got {.cls {class(roles)[1]}}.", "roles")
  }
  need <- setdiff(c("col", "role", "action", "kind"), names(roles))
  if (length(need)) {
    .plan_refuse("`roles` lacks column{?s} {.field {need}}.", "roles")
  }
  .check_conditional_arg(conditional)
  ladder <- match.arg(ladder)
  if (!is.logical(grain) || length(grain) != 1L || is.na(grain)) {
    .plan_refuse("`grain` must be a single `TRUE` or `FALSE`.", "grain")
  }
  .plan_class(
    roles = roles,
    coords = .plan_wrap(coords, c("lat", "lon")),
    events = .plan_wrap(events, c("time", "status")),
    conditional = conditional,
    ladder = ladder,
    grain = grain,
    alias_names = alias_names,
    controls = .plan_controls(controls),
    vocabulary = "source",
    mode = attr(roles, "mode")
  )
}

.plan_refuse <- function(msg, what, .envir = parent.frame()) {
  cli::cli_abort(
    msg,
    class = c(paste0("masque_plan_", what, "_refusal"), "orchestra_refusal"),
    .envir = .envir
  )
}

# One spec, or a list of them, as a list of specs.
.plan_wrap <- function(x, keys) {
  if (is.null(x)) {
    return(list())
  }
  if (is.character(x) && length(names(x))) {
    x <- as.list(x)
  }
  if (is.list(x) && any(keys %in% names(x))) {
    x <- list(x)
  }
  x
}

.plan_controls <- function(controls) {
  if (is.null(controls)) {
    return(list())
  }
  if (S7::S7_inherits(controls, masque_control_spec)) {
    return(list(default = controls))
  }
  nms <- names(controls)
  ok <- is.list(controls) && length(controls) >= 1L && !is.null(nms) &&
    all(nzchar(nms)) && !anyDuplicated(nms) &&
    all(vapply(controls, S7::S7_inherits, logical(1L), masque_control_spec))
  if (!ok) {
    .plan_refuse(
      "`controls` must be one {.fn control_spec} or a named list of them.",
      "controls"
    )
  }
  controls
}

# Print ----------------------------------------------------------------------

# local(): see the plot method in detect_plot.R.
local(S7::method(print, .plan_class) <- function(x, ...) {
  cli::cli_h1("masque_plan ({x@vocabulary} vocabulary)")
  tally <- table(factor(
    x@roles$role,
    levels = c("design", "treatment", "outcome", "covariate", "date", "id", "ignore")
  ))
  tally <- tally[tally > 0L]
  cli::cli_bullets(c(
    "*" = sprintf(
      "Roles: %s",
      paste(sprintf("%d %s", tally, names(tally)), collapse = ", ")
    ),
    "*" = sprintf("Conditional: %s", paste(x@conditional, collapse = ", ")),
    "*" = sprintf("Ladder: %s; grain: %s", x@ladder, x@grain),
    "*" = sprintf("Column names aliased: %s", paste(x@alias_names, collapse = ", ")),
    "*" = sprintf("Coordinate pairs: %d", length(x@coords)),
    "*" = sprintf("Linked-event specs: %d", length(x@events)),
    "*" = sprintf("Control specs: %d", length(x@controls))
  ))
  for (nm in names(x@controls)) {
    s <- x@controls[[nm]]
    cli::cli_text("{.strong {nm}}")
    cli::cli_bullets(c(
      " " = sprintf("on %s, unit %s", .spec_on_line(s), .spec_cols_line(s@unit, "row")),
      " " = sprintf("strata %s", .spec_cols_line(s@strata, "none")),
      " " = sprintf("target %s; %s replicate(s)", .spec_target_line(s), s@n)
    ))
  }
  invisible(x)
})

# Resolution on the source, at mask() ----------------------------------------

# The plan as it ran, with every spec resolved on the source table.
.plan_resolve <- function(plan, df, roles, rec, args) {
  specs <- lapply(plan@controls, .plan_resolve_spec, df = df, roles = roles, rec = rec)
  resolved_roles <- as.data.frame(rec@roles)
  attr(resolved_roles, "mode") <- rec@mode
  .plan_class(
    roles = resolved_roles,
    coords = .plan_wrap(args$coords, c("lat", "lon")),
    events = .plan_wrap(args$events, c("time", "status")),
    conditional = args$conditional,
    ladder = args$ladder,
    grain = args$grain,
    alias_names = args$alias_names,
    controls = specs,
    vocabulary = "source",
    mode = rec@mode
  )
}

.plan_resolve_spec <- function(spec, df, roles, rec) {
  design <- intersect(
    names(df), roles$col[roles$role == "design" & roles$action != "drop"]
  )
  on <- .resolve_control_on(spec@on, df, roles, spec@target)
  unit <- if (length(spec@unit)) spec@unit else .default_control_unit(df, on, design)
  strata <- if (length(spec@strata)) {
    spec@strata
  } else {
    .default_control_strata(df, on, design, unit)
  }
  grain <- spec@grain
  analysed <- roles$col[
    roles$role %in% c("outcome", "covariate", "date") &
      roles$action %in% c("scramble", "alias")
  ]
  for (g in .prop_or(rec, "grain", list())) {
    if (all(g$unit %in% design)) {
      for (cl in setdiff(intersect(g$cols, analysed), c(names(grain), spec@target))) {
        grain[[cl]] <- g$unit
      }
    }
  }
  draft <- masque_control_spec(
    on = on, target = spec@target, effect = spec@effect, strata = strata,
    unit = unit, grain = grain, n = spec@n, seed = spec@seed
  )
  .resolve_control_spec(draft, df, roles)$spec
}

# Coarsest design column, then pair of columns, within which `on` is constant.
# A partition of mostly single rows says nothing: `on` is constant there by
# construction, so it must average two rows a unit.
.default_control_unit <- function(df, on, design) {
  n <- nrow(df)
  sets <- c(as.list(design), if (length(design) >= 2L) {
    utils::combn(design, 2L, simplify = FALSE)
  })
  for (size in 1:2) {
    pick <- Filter(function(s) length(s) == size, sets)
    n_units <- vapply(pick, function(s) {
      id <- as.integer(.unit_id(df, s))
      if (.constant_within(id, df[[on]])) max(id) else NA_integer_
    }, integer(1L))
    n_units[n_units > n / 2] <- NA_integer_
    if (any(!is.na(n_units))) {
      return(pick[[which.min(n_units)]])
    }
  }
  character()
}

# Finest design partition above the unit whose every stratum holds every level.
.default_control_strata <- function(df, on, design, unit) {
  unit_id <- if (length(unit)) as.integer(.unit_id(df, unit)) else seq_len(nrow(df))
  all_levels <- length(unique(df[[on]][!is.na(df[[on]])]))
  usable <- function(cols) {
    id <- as.integer(.unit_id(df, cols))
    if (max(id) < 2L || !.constant_within(unit_id, id)) {
      return(FALSE)
    }
    held <- tapply(df[[on]], id, function(v) length(unique(v[!is.na(v)])))
    all(held == all_levels)
  }
  passing <- Filter(usable, setdiff(design, c(unit, on)))
  if (!length(passing)) {
    return(character())
  }
  if (usable(passing)) {
    return(passing)
  }
  sizes <- vapply(passing, function(cl) max(as.integer(.unit_id(df, cl))), integer(1L))
  passing[which.max(sizes)]
}

# Translation between source and clone vocabulary ----------------------------

.plan_col_translator <- function(rec, to) {
  map <- rec@column_name_map
  from_to <- if (length(map)) {
    if (identical(to, "clone")) {
      unlist(map)
    } else {
      stats::setNames(names(map), unlist(map))
    }
  } else {
    character()
  }
  function(x) {
    if (!length(x)) {
      return(x)
    }
    hits <- x %in% names(from_to)
    x[hits] <- unname(from_to[x[hits]])
    x
  }
}

.plan_spec_translate <- function(spec, rec, to) {
  rename <- .plan_col_translator(rec, to)
  on_source <- if (identical(to, "clone")) spec@on else .plan_col_translator(rec, "source")(spec@on)
  effect <- spec@effect
  map <- rec@level_maps[[on_source]]
  if (is.numeric(effect) && length(map)) {
    relabel <- if (identical(to, "clone")) {
      .apply_level_map_forward
    } else {
      .apply_level_map_inverse
    }
    names(effect) <- as.character(relabel(names(effect), map, col = on_source))
  }
  grain <- lapply(spec@grain, rename)
  names(grain) <- rename(names(grain))
  masque_control_spec(
    on = rename(spec@on),
    target = if (is.null(spec@target)) NULL else rename(spec@target),
    effect = effect,
    strata = rename(spec@strata),
    unit = rename(spec@unit),
    grain = grain,
    n = spec@n,
    seed = spec@seed
  )
}

#' The plan in clone vocabulary, for the analyst
#'
#' The plan of a [mask()] result, in the names and labels of the clone. It
#' carries the roles as [roles()] gives them, the linked events and each control
#' spec as resolved on the source. It holds no coordinate declaration, and
#' nothing else from the recipe. With [controls()] it gives the analyst the
#' pre-declared controls on the clone.
#'
#' @param m A `masque` object from [mask()]. A clone masked without a plan gives
#'   a plan with no control specs.
#'
#' @returns A `masque_plan` in clone vocabulary.
#'
#' @examples
#' r <- propose_roles(iris, detect = FALSE)
#' clone_plan(mask(iris, r, mode = "local", seed = 1L))
#'
#' @seealso [masque_plan()], [controls()], [handover()].
#'
#' @export
clone_plan <- function(m) {
  if (!S7::S7_inherits(m, masque_obj)) {
    cli::cli_abort(
      "`m` must be a {.cls masque} object; got {.cls {class(m)[1]}}.",
      class = c("masque_bad_masque_obj_refusal", "orchestra_refusal")
    )
  }
  rec <- m@recipe
  source_plan <- .prop_or(rec, "plan", NULL)
  public <- as.data.frame(.public_roles(rec, m@synthetic))
  attr(public, "mode") <- rec@mode
  rename <- .plan_col_translator(rec, "clone")
  conditional <- rec@conditional
  grain <- TRUE
  specs <- list()
  if (!is.null(source_plan)) {
    conditional <- source_plan@conditional
    if (is.character(conditional) && !identical(conditional, "design")) {
      conditional <- rename(conditional)
    }
    grain <- source_plan@grain
    specs <- lapply(source_plan@controls, .plan_spec_translate, rec = rec, to = "clone")
  }
  .plan_class(
    roles = public,
    coords = list(),
    events = .card_event_specs(rec),
    conditional = conditional,
    ladder = rec@ladder,
    grain = grain,
    alias_names = FALSE,
    controls = specs,
    vocabulary = "clone",
    mode = rec@mode
  )
}

# controls() from a plan ------------------------------------------------------

# Offset that roots the owner's permutations away from the spec's seed.
.CONTROL_SALT <- 15485863L

# Arguments of controls() from a plan, on either side of the boundary.
.controls_from_plan <- function(df, plan, spec, events, seed, recipe) {
  picked <- .plan_pick_spec(plan, spec)
  if (is.null(recipe)) {
    if (!identical(plan@vocabulary, "clone")) {
      .control_refuse(
        c(
          "This plan is in source vocabulary, and no `recipe` was given.",
          i = "The analyst uses {.fn clone_plan}; the owner passes `recipe =`, which draws from a private seed."
        ),
        "source_plan"
      )
    }
    return(list(
      df = df,
      roles = plan@roles,
      spec = picked$spec,
      events = if (is.null(events) && length(plan@events)) plan@events else events,
      seed = seed,
      notes = character()
    ))
  }
  if (!S7::S7_inherits(recipe, masque_recipe)) {
    .control_refuse("`recipe` must be a {.cls masque_recipe}; got {.cls {class(recipe)[1]}}.", "recipe")
  }
  source_spec <- if (identical(plan@vocabulary, "clone")) {
    .plan_spec_translate(picked$spec, recipe, "source")
  } else {
    picked$spec
  }
  .check_spec_as_declared(source_spec, picked$name, recipe)
  list(
    df = .controls_replay_source(df, recipe),
    roles = as.data.frame(recipe@roles),
    spec = source_spec,
    events = if (is.null(events) && length(recipe@events)) {
      lapply(recipe@events, function(e) list(time = e$time, status = e$status))
    } else {
      events
    },
    seed = .control_source_seed(recipe@seed, source_spec@seed, seed),
    notes = "Source side: the seed is private. Release aggregates only."
  )
}

.plan_pick_spec <- function(plan, spec) {
  specs <- plan@controls
  if (!length(specs)) {
    .control_refuse("This plan holds no control spec.", "spec")
  }
  if (is.null(spec)) {
    if (length(specs) != 1L) {
      nms <- names(specs)
      .control_refuse(
        "This plan holds {length(specs)} control specs; name one in `spec`: {.val {nms}}.",
        "spec"
      )
    }
    return(list(name = names(specs), spec = specs[[1L]]))
  }
  if (!is.character(spec) || length(spec) != 1L || !spec %in% names(specs)) {
    nms <- names(specs)
    .control_refuse("With a plan, `spec` names one of its specs: {.val {nms}}.", "spec")
  }
  list(name = spec, spec = specs[[spec]])
}

# A spec fixed in the plan before any real result exists stays fixed.
.check_spec_as_declared <- function(spec, name, recipe) {
  declared <- .prop_or(recipe, "plan", NULL)
  if (is.null(declared)) {
    return(invisible(TRUE))
  }
  on_file <- declared@controls[[name]]
  same <- !is.null(on_file) && all(vapply(
    c("on", "target", "effect", "strata", "unit", "grain", "n", "seed"),
    function(p) isTRUE(all.equal(S7::prop(spec, p), S7::prop(on_file, p))),
    logical(1L)
  ))
  if (!same) {
    .control_refuse(
      c(
        "Control spec {.val {name}} differs from the one fixed at {.fn mask}.",
        i = "A control is declared before any real result exists, so the owner runs the spec on the recipe."
      ),
      "spec_changed"
    )
  }
  invisible(TRUE)
}

# The table the clone was built on: cleaning and conformance replayed, the
# schema and NA mask checked.
.controls_replay_source <- function(df, recipe) {
  .check_control_table(df)
  df <- .apply_cleaning_forward(df, recipe@cleaning)
  df <- .apply_conform_forward(df, .prop_or(recipe, "conform", NULL))
  retained <- setdiff(recipe@roles$col, .recipe_dropped_cols(recipe))
  gone <- setdiff(retained, names(df))
  if (length(gone)) {
    .control_refuse(
      "The table lacks column{?s} the recipe was built on: {.field {gone}}.",
      "mismatch"
    )
  }
  .check_recipe_integrity(df, recipe)
  df
}

.control_source_seed <- function(recipe_seed, spec_seed, seed) {
  if (!is.null(seed)) {
    .check_seed(seed)
    if (as.integer(seed) == spec_seed) {
      .control_refuse(
        "`seed` equals the spec's seed, which the analyst holds. The source side needs a private seed.",
        "seed"
      )
    }
    return(as.integer(seed))
  }
  if (is.null(recipe_seed)) {
    .control_refuse(
      "The recipe holds no seed to derive a private one from. Pass a private `seed`.",
      "seed"
    )
  }
  root <- (as.numeric(recipe_seed) + as.numeric(spec_seed) + .CONTROL_SALT) %%
    .Machine$integer.max
  .sub_seeds(root, 1L)
}

# YAML ------------------------------------------------------------------------

#' Save and read a masking plan as YAML
#'
#' A plan on disk is plain, reviewable and diffable. `save_plan()` needs the
#' `yaml` package. A custom `on_land` function cannot be written, and is refused.
#' A source-vocabulary plan names real columns and labels, so it stays with the
#' owner. The analyst's file comes from [clone_plan()] or [handover()].
#'
#' @param plan A [masque_plan()].
#' @param path Path of a `.yaml` or `.yml` file.
#'
#' @returns `save_plan()` returns `path` invisibly; `read_plan()` a `masque_plan`.
#'
#' @examples
#' if (requireNamespace("yaml", quietly = TRUE)) {
#'   r <- propose_roles(iris, detect = FALSE)
#'   f <- tempfile(fileext = ".yaml")
#'   save_plan(masque_plan(r), f)
#'   read_plan(f)
#' }
#'
#' @export
save_plan <- function(plan, path) {
  if (!S7::S7_inherits(plan, .plan_class)) {
    .plan_refuse("`plan` must be a {.cls masque_plan}; got {.cls {class(plan)[1]}}.", "class")
  }
  .check_plan_path(path)
  .check_yaml_available()
  yaml::write_yaml(.plan_to_list(plan), path, precision = 17L)
  invisible(path)
}

#' @rdname save_plan
#' @export
read_plan <- function(path) {
  .check_plan_path(path)
  .check_yaml_available()
  if (!file.exists(path)) {
    .plan_refuse("File not found: {.file {path}}.", "file")
  }
  x <- tryCatch(
    yaml::read_yaml(path),
    error = function(e) {
      .plan_refuse("{.file {path}} is not valid YAML: {conditionMessage(e)}", "file")
    }
  )
  if (!is.list(x) || !identical(as.integer(x$masque_plan), 1L)) {
    .plan_refuse("{.file {path}} is not a saved masque plan.", "file")
  }
  .plan_from_list(x)
}

.check_plan_path <- function(path) {
  ok <- is.character(path) && length(path) == 1L && !is.na(path) &&
    grepl("\\.ya?ml$", path, ignore.case = TRUE)
  if (!ok) {
    .plan_refuse("`path` must be a single path ending in {.file .yaml} or {.file .yml}.", "file")
  }
}

.check_yaml_available <- function() {
  if (!requireNamespace("yaml", quietly = TRUE)) {
    .plan_refuse("Writing and reading a plan needs the {.pkg yaml} package.", "yaml")
  }
}

.plan_to_list <- function(plan) {
  r <- plan@roles
  coords <- lapply(plan@coords, function(s) {
    s <- as.list(s)
    if (any(vapply(s, is.function, logical(1L)))) {
      .plan_refuse("A coordinate spec with an `on_land` function cannot be written to a file.", "file")
    }
    s
  })
  list(
    masque_plan = 1L,
    vocabulary = plan@vocabulary,
    mode = plan@mode,
    conditional = as.list(plan@conditional),
    ladder = plan@ladder,
    grain = plan@grain,
    alias_names = as.list(plan@alias_names),
    roles = lapply(seq_len(nrow(r)), function(i) {
      list(col = r$col[i], role = r$role[i], action = r$action[i], kind = r$kind[i])
    }),
    coords = coords,
    events = lapply(plan@events, function(e) {
      list(time = as.list(e$time), status = as.list(e$status))
    }),
    controls = lapply(plan@controls, .spec_to_list)
  )
}

.spec_to_list <- function(s) {
  effect <- s@effect
  list(
    on = s@on,
    target = as.list(s@target),
    effect_sd = if (is.list(effect)) effect$sd,
    effect = if (is.numeric(effect)) {
      lapply(seq_along(effect), function(i) {
        list(level = names(effect)[i], shift = effect[[i]])
      })
    },
    strata = as.list(s@strata),
    unit = as.list(s@unit),
    grain = lapply(seq_along(s@grain), function(i) {
      list(col = names(s@grain)[i], unit = as.list(s@grain[[i]]))
    }),
    n = s@n,
    seed = s@seed
  )
}

.chr <- function(x) as.character(unlist(x))

.plan_from_list <- function(x) {
  roles <- data.frame(
    col = vapply(x$roles, function(r) as.character(r$col), character(1L)),
    role = vapply(x$roles, function(r) as.character(r$role), character(1L)),
    action = vapply(x$roles, function(r) as.character(r$action), character(1L)),
    kind = vapply(x$roles, function(r) as.character(r$kind), character(1L)),
    stringsAsFactors = FALSE
  )
  attr(roles, "mode") <- x$mode
  .plan_class(
    roles = roles,
    coords = lapply(x$coords, as.list),
    events = lapply(x$events, function(e) {
      list(time = .chr(e$time), status = .chr(e$status))
    }),
    conditional = unlist(x$conditional),
    ladder = as.character(x$ladder),
    grain = isTRUE(x$grain),
    alias_names = unlist(x$alias_names),
    controls = lapply(x$controls, .spec_from_list),
    vocabulary = as.character(x$vocabulary),
    mode = x$mode
  )
}

.spec_from_list <- function(s) {
  effect <- if (!is.null(s$effect_sd)) {
    list(sd = as.double(s$effect_sd))
  } else if (length(s$effect)) {
    stats::setNames(
      vapply(s$effect, function(e) as.double(e$shift), numeric(1L)),
      vapply(s$effect, function(e) as.character(e$level), character(1L))
    )
  }
  grain <- lapply(s$grain, function(g) .chr(g$unit))
  names(grain) <- vapply(s$grain, function(g) as.character(g$col), character(1L))
  masque_control_spec(
    on = if (is.null(s$on)) NULL else as.character(s$on),
    target = if (length(s$target)) .chr(s$target),
    effect = effect,
    strata = .chr(s$strata),
    unit = .chr(s$unit),
    grain = if (length(grain)) grain else list(),
    n = as.integer(s$n),
    seed = as.integer(s$seed)
  )
}

# Handover --------------------------------------------------------------------

#' Hand a clone to an analyst
#'
#' Writes what the analyst works from into one folder: the clone (`clone.csv`),
#' the plan in clone vocabulary (`plan.yaml`), the data card (`card.yaml`) and a
#' plain note (`README.txt`). The recipe is never written. The release gate runs
#' first, as for [write_set()]: an unresolved HIGH finding blocks the write
#' unless `allow_high = TRUE`.
#'
#' @param m A `masque` object from [mask()].
#' @param dir The folder to write. An existing folder that holds files is
#'   refused unless `overwrite = TRUE`.
#' @param name Dataset name for the data card; `NULL` uses `"clone"`.
#' @param overwrite Replace the four files if they exist.
#' @param allow_high Write despite HIGH findings, with a warning.
#'
#' @returns The paths written, invisibly.
#'
#' @examples
#' if (requireNamespace("yaml", quietly = TRUE)) {
#'   r <- propose_roles(iris, detect = FALSE)
#'   m <- mask(iris, r, mode = "local", seed = 1L)
#'   d <- tempfile()
#'   handover(m, d)
#'   list.files(d)
#' }
#'
#' @seealso [clone_plan()], [data_card()], [controls()].
#'
#' @export
handover <- function(m, dir, name = NULL, overwrite = FALSE, allow_high = FALSE) {
  if (!S7::S7_inherits(m, masque_obj)) {
    cli::cli_abort(
      "`m` must be a {.cls masque} object; got {.cls {class(m)[1]}}.",
      class = c("masque_bad_masque_obj_refusal", "orchestra_refusal")
    )
  }
  if (!is.character(dir) || length(dir) != 1L || is.na(dir) || !nzchar(dir)) {
    cli::cli_abort(
      "`dir` must be a single non-empty string.",
      class = c("masque_bad_handover_dir_refusal", "orchestra_refusal")
    )
  }
  .check_yaml_available()
  high <- .gate_release(m, allow_high)
  if (dir.exists(dir) && length(list.files(dir, all.files = TRUE, no.. = TRUE)) &&
    !isTRUE(overwrite)) {
    cli::cli_abort(
      c(
        "{.file {dir}} already holds files.",
        i = "Choose an empty folder, or pass `overwrite = TRUE`."
      ),
      class = c("masque_handover_exists_refusal", "orchestra_refusal")
    )
  }
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)

  paths <- file.path(dir, c("clone.csv", "plan.yaml", "card.yaml", "README.txt"))
  data.table::fwrite(m@synthetic, paths[1L])
  save_plan(clone_plan(m), paths[2L])
  data_card(m, file = paths[3L], name = name)
  writeLines(.handover_note(m, length(high)), paths[4L])
  invisible(paths)
}

.handover_note <- function(m, n_high) {
  plan <- clone_plan(m)
  c(
    "Masked clone for pipeline development",
    "",
    sprintf(
      "clone.csv holds %d rows and %d columns. An empty cell is a missing value.",
      nrow(m@synthetic), ncol(m@synthetic)
    ),
    "plan.yaml holds the column roles and any declared controls, in the clone's names.",
    "card.yaml describes the table for downstream tools.",
    "",
    "The values are re-simulated. Do not read an effect or an estimate from this table.",
    "Write and test your code here. The data owner runs the finished code on the real table.",
    if (length(plan@controls)) {
      paste0(
        "In R, read_plan(\"plan.yaml\") and controls(clone, plan) rebuild the declared ",
        "known-truth controls."
      )
    },
    if (n_high > 0L) {
      sprintf(
        "The owner released this clone despite %d HIGH leakage finding(s), after review.",
        n_high
      )
    }
  )
}
