# controls.R -- controls() and control_table(): null, negative and positive
# control datasets derived from a table by restricted permutation and planted
# effects. Nothing is re-simulated.

#' Internal: the masque_controls S7 class
#'
#' The resolved declaration plus everything needed to regenerate a control
#' table: the owned table, the validated roles, the seeds, the analysed
#' columns, the event pairs, the per-row stratum and unit ids, the unit ids
#' of grained columns, the manifest, the truth table and the notes.
#'
#' @keywords internal
#' @noRd
masque_controls <- S7::new_class(
  "masque_controls",
  properties = list(
    table = S7::class_data.frame,
    roles = S7::class_data.frame,
    spec = masque_control_spec,
    seeds = S7::class_integer,
    analysed = S7::class_character,
    events = S7::class_list,
    strata_id = S7::class_integer,
    unit_id = S7::class_integer,
    grain_units = S7::class_list,
    manifest = S7::class_data.frame,
    truth = S7::class_data.frame,
    notes = S7::class_character
  )
)

# Offset that roots the planted-effect draw away from the permutation stream.
.CONTROL_SALT <- 7919L

#' Derive null, negative and positive controls from a table
#'
#' Builds the control datasets a [control_spec()] declares, from any table
#' with a role table: a synthetic clone, a comparator's clone, or, on the
#' owner's side, the original. Nothing is re-simulated. Three kinds of
#' control exist, each with a known truth:
#'
#' * `null`: every analysed column (outcome, covariate and date columns
#'   with action `scramble` or `alias`) is permuted independently over its
#'   non-missing rows; a column declared unit-grained is permuted across its
#'   units and stays constant within each. Design, treatment and kept
#'   columns, the NA mask and every column's multiset of values are kept.
#'   No association among analysed columns, or with the treatment, remains.
#'   Use it as a smoke test and to expose leakage through analysed columns.
#' * `negative`: the declared column `on` alone is permuted within the
#'   declared design strata, at its unit, while the design structure and all
#'   other associations are kept. Choose strata that every level of `on` can
#'   reach. Complete replicates qualify. Within incomplete blocks each block
#'   keeps its set of levels, so part of the real effect of `on` survives.
#'   With `n` replicates it gives a permutation null for a whole pipeline: a
#'   false-positive rate, a permutation p-value.
#' * `positive`: the same permutation as the negative replicate, plus the
#'   declared shift per level of `on` on each target, in units of the
#'   target's standard deviation in the table at hand. Positive minus
#'   negative is the planted truth, exactly.
#'
#' @section Declaration before data:
#' The spec is resolved against the table here: `on` defaults to the single
#' treatment column; strata and unit are checked for nesting; an `effect`
#' given as `list(sd = )` is drawn under the spec's seed, once, so the same
#' spec plants the same vector on every table it meets. The resolved spec
#' and the truth table are on the returned object and in its print.
#'
#' @section Two sides, two seeds:
#' An analyst who holds only the clone runs this on the clone. The owner
#' runs it on the original, offline, with a private `seed` that overrides
#' the spec's seed for the permutations (the planted vector still comes
#' from the spec's seed). A public seed would let anyone who knows the
#' design, which the clone shares, rebuild every permutation and read the
#' original outcome out of per-replicate statistics. Control tables built
#' from an original never leave the owner; what leaves is an aggregate
#' verdict about the pipeline, through the owner's usual output checking.
#'
#' @section Limits:
#' A kept column is structure and is never permuted, so leakage through
#' kept columns, ids or row order passes the null. A planted effect is
#' clean: uniform within a level, with no confounding and no interaction.
#' Nothing is clipped, so a shift can take a non-negative outcome below
#' zero; [control_table()] warns when it does. The null collapses the
#' design means of row-grained outcomes, so false-positive calibration
#' comes from the negative control, not the null.
#'
#' @param df The table to derive controls from: a data frame or data.table.
#' @param roles Its role table, as returned by [roles()] for a clone or by
#'   [propose_roles()] and [set_role()] for any table. Or a plan: the analyst
#'   passes [clone_plan()] with the clone, the owner passes the plan and the
#'   `recipe` with the real table.
#' @param spec A [control_spec()]. With a plan in `roles`, the name of one of
#'   its specs, or `NULL` when it holds exactly one.
#' @param events Linked time/status pairs among the outcome columns, in the
#'   form [mask()] takes. The null permutes each pair as one block. `NULL`
#'   when there are none.
#' @param seed A private seed for the permutations that overrides the
#'   spec's seed, for the owner's side; `NULL` uses the spec's seed, or with a
#'   `recipe` a private seed derived from the recipe's. A value equal to the
#'   spec's seed is refused there.
#' @param recipe With a plan in `roles`, the recipe of the clone. `df` is then
#'   the real table: its cleaning and conformance are replayed as in
#'   [apply_recipe()], a table with a different schema or NA mask is refused,
#'   and a spec that differs from the one fixed at [mask()] is refused.
#'
#' @returns A `masque_controls` object: the resolved spec (`@spec`), the
#'   manifest (`@manifest`, one row per dataset), the truth table
#'   (`@truth`, one row per target and level of `on`) and the notes
#'   (`@notes`). Datasets are produced by [control_table()].
#'
#' @examples
#' trial <- read.csv(system.file("extdata", "john_alpha.csv", package = "masque"))
#' r <- propose_roles(trial, detect = FALSE)
#' r <- set_role(r, c("rep", "block"), role = "design", action = "keep")
#' r <- set_role(r, "gen", role = "treatment", action = "keep")
#' r <- set_role(r, "yield", role = "outcome", action = "scramble")
#' r <- set_role(r, c("plot", "row", "col"), role = "id", action = "keep")
#' spec <- control_spec(
#'   on = "gen", target = "yield", effect = list(sd = 0.5),
#'   strata = "rep", n = 5L, seed = 2026L
#' )
#' ctl <- controls(trial, r, spec)
#' ctl
#' head(control_table(ctl, "positive", 1L))
#'
#' @seealso [control_spec()], [control_table()], [mask()], [roles()].
#'
#' @export
controls <- function(df, roles, spec = NULL, events = NULL, seed = NULL,
                     recipe = NULL) {
  withr::local_preserve_seed()
  plan_notes <- character()
  if (S7::S7_inherits(roles, .plan_class)) {
    from_plan <- .controls_from_plan(df, roles, spec, events, seed, recipe)
    df <- from_plan$df
    roles <- from_plan$roles
    spec <- from_plan$spec
    events <- from_plan$events
    seed <- from_plan$seed
    plan_notes <- from_plan$notes
  } else if (!is.null(recipe)) {
    .control_refuse("`recipe` goes with a plan in `roles`: {.code controls(real, plan, recipe = rec)}.", "recipe")
  }
  .check_control_table(df)
  .check_control_spec_class(spec)
  if (!is.null(seed)) {
    .check_seed(seed)
  }
  df <- .as_owned_dt(df)
  roles <- roles_validate(roles, df = df)

  # Resolve the declaration against the table ------------------------------
  res <- .resolve_control_spec(spec, df, roles)
  events <- .normalise_events(events, df, roles)
  .check_control_target_events(res$spec, events)

  # Seeds: one for the null, one per replicate -----------------------------
  run_seed <- if (is.null(seed)) spec@seed else as.integer(seed)
  seeds <- as.integer(.sub_seeds(run_seed, res$spec@n + 1L))

  manifest <- .control_manifest(res, seeds)
  masque_controls(
    table = df,
    roles = .as_owned_dt(roles),
    spec = res$spec,
    seeds = seeds,
    analysed = res$analysed,
    events = events,
    strata_id = res$strata_id,
    unit_id = res$unit_id,
    grain_units = res$grain_units,
    manifest = manifest,
    truth = res$truth,
    notes = c(res$notes, plan_notes)
  )
}

#' Produce one control dataset
#'
#' Regenerates a control dataset of a [controls()] object from its seed: the
#' null, or negative or positive replicate `i`. Positive replicate `i` is
#' negative replicate `i` plus the planted shift. The result carries a
#' `masque_control` attribute naming its kind and replicate; its values
#' alone do not tell it from the table it came from, so keep the manifest
#' with it.
#'
#' @param ctl A `masque_controls` object from [controls()].
#' @param kind One of `"null"`, `"negative"`, `"positive"`.
#' @param i The replicate, from 1 to `n` of the spec; ignored for the null.
#'
#' @returns A data.table with the columns, classes, NA mask and row order of
#'   the input table.
#'
#' @examples
#' trial <- read.csv(system.file("extdata", "john_alpha.csv", package = "masque"))
#' r <- propose_roles(trial, detect = FALSE)
#' r <- set_role(r, c("rep", "block"), role = "design", action = "keep")
#' r <- set_role(r, "gen", role = "treatment", action = "keep")
#' r <- set_role(r, "yield", role = "outcome", action = "scramble")
#' r <- set_role(r, c("plot", "row", "col"), role = "id", action = "keep")
#' spec <- control_spec(on = "gen", strata = "rep", n = 3L, seed = 1L)
#' ctl <- controls(trial, r, spec)
#' neg <- control_table(ctl, "negative", 2L)
#' table(neg$block, neg$gen)[1:2, 1:6]
#'
#' @seealso [controls()], [control_spec()].
#'
#' @export
control_table <- function(ctl, kind = c("null", "negative", "positive"), i = 1L) {
  withr::local_preserve_seed()
  .check_controls_class(ctl)
  kind <- match.arg(kind)
  i <- .check_control_index(i, ctl@spec@n)
  if (identical(kind, "positive") && is.null(ctl@spec@target)) {
    .control_refuse(
      "The spec declares no `target`, so there is no positive control.",
      "kind"
    )
  }

  out <- data.table::copy(ctl@table)
  if (identical(kind, "null")) {
    with_rng_state(ctl@seeds[1L], .permute_analysed(out, ctl))
  } else {
    with_rng_state(ctl@seeds[1L + i], .permute_on(out, ctl))
    if (identical(kind, "positive")) {
      .plant_effect(out, ctl)
    }
  }
  data.table::setattr(out, "masque_control", list(
    kind = kind,
    replicate = if (identical(kind, "null")) NA_integer_ else i
  ))
  out[]
}

# Resolution ----------------------------------------------------------------

# Resolve a spec against a table and its roles.
.resolve_control_spec <- function(spec, df, roles) {
  n <- nrow(df)
  notes <- character()
  design <- intersect(
    names(df), roles$col[roles$role == "design" & roles$action != "drop"]
  )
  analysed <- intersect(names(df), roles$col[
    roles$role %in% c("outcome", "covariate", "date") &
      roles$action %in% c("scramble", "alias")
  ])
  if (!length(analysed)) {
    .control_refuse(
      "The table has no analysed column: an outcome, covariate or date column with action `scramble` or `alias`.",
      "analysed"
    )
  }
  kept_outcome <- roles$col[roles$role == "outcome" & roles$action == "keep"]
  if (length(kept_outcome)) {
    warning(warningCondition(
      sprintf(
        "Kept outcome column%s %s %s structure and %s not permuted by any control.",
        if (length(kept_outcome) > 1L) "s" else "",
        paste(kept_outcome, collapse = ", "),
        if (length(kept_outcome) > 1L) "are" else "is",
        if (length(kept_outcome) > 1L) "are" else "is"
      ),
      class = "masque_control_kept_outcome"
    ))
  }

  # The permuted column and its unit ------------------------------------
  on <- .resolve_control_on(spec@on, df, roles, spec@target)
  unit <- .check_design_cols(spec@unit, "unit", design)
  unit_id <- if (length(unit)) {
    as.integer(.unit_id(df, unit))
  } else {
    seq_len(n)
  }
  if (length(unit) && !.constant_within(unit_id, df[[on]])) {
    .control_refuse(
      "`on` ({.field {on}}) varies within its declared unit ({.field {unit}}); a unit must hold one value of `on`.",
      "unit"
    )
  }

  # Strata: nested above the unit, and `on` must vary somewhere ------------
  strata <- .check_design_cols(spec@strata, "strata", design)
  strata_id <- if (length(strata)) {
    as.integer(.unit_id(df, strata))
  } else {
    rep(1L, n)
  }
  if (length(strata) && !.constant_within(unit_id, strata_id)) {
    .control_refuse(
      "A unit of `on` ({.field {unit}}) spans more than one stratum ({.field {strata}}); strata must be nested above the unit.",
      "strata"
    )
  }
  constant_share <- .strata_constant_share(df[[on]], strata_id)
  if (constant_share >= 1) {
    .control_refuse(
      c(
        "`on` ({.field {on}}) is constant within every stratum ({.field {strata}}), so a restricted permutation changes nothing.",
        i = "Coarsen the strata or drop them."
      ),
      "degenerate"
    )
  }
  if (constant_share > 0.5) {
    warning(warningCondition(
      sprintf(
        "`on` (%s) is constant within %.0f%% of the strata; the negative control permutes little.",
        on, 100 * constant_share
      ),
      class = "masque_control_strata_weak"
    ))
  }

  # Grain of other analysed columns ----------------------------------------
  grain_units <- list()
  for (cl in names(spec@grain)) {
    if (!cl %in% analysed) {
      .control_refuse(
        "`grain` names {.field {cl}}, which is not an analysed column of the table.",
        "grain"
      )
    }
    u <- .check_design_cols(spec@grain[[cl]], "grain", design)
    gid <- as.integer(.unit_id(df, u))
    if (.constant_within(gid, df[[cl]])) {
      grain_units[[cl]] <- gid
    } else {
      notes <- c(notes, sprintf(
        "%s is not constant within %s in this table; permuted at the row.",
        cl, paste(u, collapse = " + ")
      ))
    }
  }

  # Targets and the planted truth -----------------------------------------
  target <- .check_control_targets(spec@target, df, roles, on, spec@grain)
  levels <- .control_levels(df[[on]])
  effect <- .resolve_control_effect(spec@effect, levels, spec@seed)
  truth <- .control_truth(df, target, effect, strata_id)

  spec_out <- masque_control_spec(
    on = on,
    target = target,
    effect = effect,
    strata = strata,
    unit = unit,
    grain = spec@grain,
    n = spec@n,
    seed = spec@seed
  )
  list(
    spec = spec_out,
    analysed = analysed,
    strata_id = strata_id,
    unit_id = unit_id,
    n_strata = max(strata_id),
    constant_share = constant_share,
    grain_units = grain_units,
    truth = truth,
    notes = notes
  )
}

# `on`: the single treatment column when NULL; present, a treatment or
# covariate, categorical or whole-valued, and not a target.
.resolve_control_on <- function(on, df, roles, target) {
  if (is.null(on)) {
    trt <- intersect(
      names(df),
      roles$col[roles$role == "treatment" & roles$action != "drop"]
    )
    if (length(trt) != 1L) {
      .control_refuse(
        c(
          "`on` is `NULL` and the table has {length(trt)} treatment column{?s}; name `on`.",
          i = "A negative control needs exactly one column to permute."
        ),
        "on"
      )
    }
    on <- trt
  }
  if (!on %in% names(df)) {
    .control_refuse("`on` ({.field {on}}) is not a column of the table.", "on")
  }
  role <- roles$role[match(on, roles$col)]
  kind <- roles$kind[match(on, roles$col)]
  if (!role %in% c("treatment", "covariate")) {
    .control_refuse(
      "`on` ({.field {on}}) has role {.val {role}}; it must be a treatment or covariate column.",
      "on"
    )
  }
  categorical <- kind %in% .categorical_kinds()
  whole <- kind %in% .numeric_kinds() && .is_whole_valued(df[[on]])
  if (!categorical && !whole) {
    .control_refuse(
      "`on` ({.field {on}}) must be categorical or whole-valued; a continuous column has no levels to shift.",
      "on"
    )
  }
  if (on %in% target) {
    .control_refuse("`on` ({.field {on}}) cannot also be a `target`.", "on")
  }
  on
}

# Columns named for strata, unit or grain must be retained design columns.
.check_design_cols <- function(cols, arg, design) {
  if (!length(cols)) {
    return(character())
  }
  bad <- setdiff(cols, design)
  if (length(bad)) {
    .control_refuse(
      "`{arg}` names {.field {bad}}, which {?is/are} not {?a/} retained design column{?s} of the table.",
      arg
    )
  }
  cols
}

# Targets: present, outcome or covariate, numeric with more than two values,
# not `on`, and not declared unit-grained.
.check_control_targets <- function(target, df, roles, on, grain) {
  if (is.null(target)) {
    return(NULL)
  }
  missing <- setdiff(target, names(df))
  if (length(missing)) {
    .control_refuse(
      "`target` names {.field {missing}}, not {?a/} column{?s} of the table.",
      "target"
    )
  }
  for (tg in target) {
    role <- roles$role[match(tg, roles$col)]
    kind <- roles$kind[match(tg, roles$col)]
    y <- df[[tg]]
    ok <- role %in% c("outcome", "covariate") && kind %in% .numeric_kinds() &&
      data.table::uniqueN(y, na.rm = TRUE) > 2L
    if (!ok) {
      .control_refuse(
        "`target` {.field {tg}} must be a numeric outcome or covariate with more than two distinct values.",
        "target_kind"
      )
    }
    if (tg %in% names(grain)) {
      .control_refuse(
        "`target` {.field {tg}} is declared unit-grained; a shift by level of `on` would break its constancy within the unit.",
        "target_grain"
      )
    }
  }
  if (on %in% target) {
    .control_refuse("`on` ({.field {on}}) cannot also be a `target`.", "target")
  }
  target
}

# A target cannot be a declared event column.
.check_control_target_events <- function(spec, events) {
  if (is.null(spec@target) || !length(events)) {
    return(invisible(NULL))
  }
  ev <- unlist(lapply(events, function(e) c(e$time, e$status)))
  bad <- intersect(spec@target, ev)
  if (length(bad)) {
    .control_refuse(
      "`target` {.field {bad}} is a linked-event column; events take no planted shift.",
      "target_kind"
    )
  }
  invisible(NULL)
}

# The levels of `on` as character, in sorted order.
.control_levels <- function(x) {
  as.character(sort(unique(x[!is.na(x)])))
}

# Share of strata in which `on` holds at most one distinct value.
.strata_constant_share <- function(x, strata_id) {
  g <- V1 <- NULL
  obs <- !is.na(x)
  pairs <- data.table::data.table(g = strata_id, x = x)
  per <- pairs[obs, data.table::uniqueN(x), by = g]
  n_strata <- data.table::uniqueN(strata_id)
  constant <- n_strata - nrow(per) + sum(per$V1 <= 1L)
  constant / n_strata
}

# The effect vector over the levels: drawn from `list(sd = )` under the
# spec's seed, or a named vector completed with zeros.
.resolve_control_effect <- function(effect, levels, seed) {
  if (is.null(effect)) {
    return(NULL)
  }
  if (is.list(effect)) {
    root <- (as.numeric(seed) + .CONTROL_SALT) %% .Machine$integer.max
    draw <- with_rng_state(root, stats::rnorm(length(levels), 0, effect$sd))
    return(stats::setNames(draw, levels))
  }
  unknown <- setdiff(names(effect), levels)
  if (length(unknown)) {
    .control_refuse(
      "`effect` names {.val {unknown}}, not {?a/} level{?s} of `on`.",
      "effect"
    )
  }
  out <- stats::setNames(rep(0, length(levels)), levels)
  out[names(effect)] <- effect
  out
}

# One row per target and level; a whole-valued target takes a whole shift.
.control_truth <- function(df, target, effect, strata_id) {
  empty <- data.table::data.table(
    target = character(), level = character(), effect_sd = double(),
    sd_y = double(), sd_within_strata = double(), shift_raw = double(),
    shift_realised = double(), whole_valued = logical()
  )
  if (is.null(target)) {
    return(empty)
  }
  rows <- lapply(target, function(tg) {
    y <- df[[tg]]
    sd_y <- stats::sd(y, na.rm = TRUE)
    resid <- y - stats::ave(y, strata_id, FUN = function(v) mean(v, na.rm = TRUE))
    whole <- .is_whole_valued(y)
    shift_raw <- unname(effect) * sd_y
    shift_realised <- if (whole) round(shift_raw) else shift_raw
    vanished <- whole & effect != 0 & shift_realised == 0
    if (any(vanished)) {
      .control_refuse(
        c(
          "On the whole-valued target {.field {tg}}, the shift for level{?s} {.val {names(effect)[vanished]}} rounds to zero.",
          i = "Declare a larger effect, or a target with a finer resolution."
        ),
        "shift_vanishes"
      )
    }
    data.table::data.table(
      target = tg,
      level = names(effect),
      effect_sd = unname(effect),
      sd_y = sd_y,
      sd_within_strata = stats::sd(resid, na.rm = TRUE),
      shift_raw = shift_raw,
      shift_realised = shift_realised,
      whole_valued = whole
    )
  })
  data.table::rbindlist(rows)
}

# One manifest row per dataset: what was permuted, where, under which seed.
.control_manifest <- function(res, seeds) {
  spec <- res$spec
  n <- spec@n
  kinds <- c("null", rep("negative", n), if (!is.null(spec@target)) rep("positive", n))
  reps <- c(NA_integer_, seq_len(n), if (!is.null(spec@target)) seq_len(n))
  dataset <- ifelse(is.na(reps), kinds, paste0(kinds, "_", reps))
  seed_of <- ifelse(is.na(reps), seeds[1L], seeds[1L + ifelse(is.na(reps), 0L, reps)])
  permuted <- ifelse(
    kinds == "null", paste(res$analysed, collapse = ", "), spec@on
  )
  data.table::data.table(
    dataset = dataset,
    kind = kinds,
    replicate = reps,
    seed = as.integer(seed_of),
    permuted = permuted,
    strata = if (length(spec@strata)) paste(spec@strata, collapse = " + ") else "none",
    unit = if (length(spec@unit)) paste(spec@unit, collapse = " + ") else "row",
    n_strata = as.integer(res$n_strata),
    strata_constant_share = res$constant_share,
    target = if (is.null(spec@target)) NA_character_ else paste(spec@target, collapse = ", ")
  )
}

# Permutation ---------------------------------------------------------------

# Permute the non-missing values of `x` across units within strata; an
# all-missing unit stays missing. With `unit_id = seq_along(x)` it is a row
# permutation.
.permute_within <- function(x, unit_id, strata_id) {
  obs <- which(!is.na(x))
  if (length(obs) < 2L) {
    return(x)
  }
  u_obs <- unique(unit_id[obs])
  first <- obs[match(u_obs, unit_id[obs])]
  u_val <- x[first]
  groups <- split(seq_along(u_obs), strata_id[first])
  perm <- integer(length(u_obs))
  for (g in groups) {
    perm[g] <- g[sample.int(length(g))]
  }
  new_val <- u_val[perm]
  out <- x
  out[obs] <- new_val[match(unit_id[obs], u_obs)]
  out
}

# The null: every analysed column on its own draw, at its grain, no strata;
# a linked-event pair moves as one row block.
.permute_analysed <- function(out, ctl) {
  n <- nrow(out)
  rows <- seq_len(n)
  none <- rep(1L, n)
  pair_cols <- unlist(lapply(ctl@events, function(e) c(e$time, e$status)))
  for (cl in setdiff(ctl@analysed, pair_cols)) {
    uid <- ctl@grain_units[[cl]]
    if (is.null(uid)) {
      uid <- rows
    }
    data.table::set(out, j = cl, value = .permute_within(out[[cl]], uid, none))
  }
  for (e in ctl@events) {
    perm <- .permute_within(rows, rows, none)
    for (cl in c(e$time, e$status)) {
      data.table::set(out, j = cl, value = out[[cl]][perm])
    }
  }
  invisible(out)
}

# The negative: `on` alone, within strata, at its unit.
.permute_on <- function(out, ctl) {
  on <- ctl@spec@on
  data.table::set(
    out,
    j = on,
    value = .permute_within(out[[on]], ctl@unit_id, ctl@strata_id)
  )
  invisible(out)
}

# The positive: each target's realised shift on the rows of each level of
# the permuted `on`; nothing is clipped.
.plant_effect <- function(out, ctl) {
  on_val <- as.character(out[[ctl@spec@on]])
  crossed <- character()
  for (tg in unique(ctl@truth$target)) {
    tr <- ctl@truth[ctl@truth$target == tg, ]
    shift <- tr$shift_realised[match(on_val, tr$level)]
    shift[is.na(shift)] <- 0
    y <- out[[tg]]
    obs <- !is.na(y)
    y_new <- y
    y_new[obs] <- y[obs] + shift[obs]
    if (is.integer(y)) {
      y_new <- as.integer(round(y_new))
    }
    if (all(y[obs] >= 0) && any(y_new[obs] < 0)) {
      crossed <- c(crossed, tg)
    }
    data.table::set(out, j = tg, value = y_new)
  }
  if (length(crossed)) {
    warning(warningCondition(
      sprintf(
        "The planted shift took %s below zero on a target with no negative values; nothing is clipped.",
        paste(crossed, collapse = ", ")
      ),
      class = "masque_control_sign_crossed"
    ))
  }
  invisible(out)
}

# Argument checks -----------------------------------------------------------

.check_control_table <- function(df) {
  if (!is.data.frame(df)) {
    .control_refuse(
      "`df` must be a data frame; got {.cls {class(df)[1]}}.", "table"
    )
  }
  if (nrow(df) < 2L) {
    .control_refuse("`df` needs at least two rows to permute.", "table")
  }
  if (anyDuplicated(names(df))) {
    .control_refuse("`df` has duplicated column names.", "table")
  }
  invisible(df)
}

.check_control_spec_class <- function(spec) {
  if (!S7::S7_inherits(spec, masque_control_spec)) {
    .control_refuse(
      "`spec` must be a {.cls masque_control_spec} from {.fn control_spec}; got {.cls {class(spec)[1]}}.",
      "spec"
    )
  }
  invisible(spec)
}

.check_controls_class <- function(ctl) {
  if (!S7::S7_inherits(ctl, masque_controls)) {
    .control_refuse(
      "`ctl` must be a {.cls masque_controls} from {.fn controls}; got {.cls {class(ctl)[1]}}.",
      "kind"
    )
  }
  invisible(ctl)
}

.check_control_index <- function(i, n) {
  ok <- is.numeric(i) && length(i) == 1L && !is.na(i) && i == round(i) &&
    i >= 1L && i <= n
  if (!ok) {
    .control_refuse(
      "`i` must be a single replicate number from 1 to {n}.", "kind"
    )
  }
  as.integer(i)
}

# Print ---------------------------------------------------------------------

# local(): see the plot method in detect_plot.R.
local(S7::method(print, masque_controls) <- function(x, ...) {
  spec <- x@spec
  cli::cli_h1("masque_controls")
  cli::cli_bullets(c(
    "*" = sprintf(
      "Table: %d rows, %d columns; %d analysed column%s",
      nrow(x@table), ncol(x@table), length(x@analysed),
      if (length(x@analysed) == 1L) "" else "s"
    ),
    "*" = sprintf("Permuted column (on): %s", spec@on),
    "*" = sprintf(
      "Strata: %s (%d strata; on constant in %.0f%% of them)",
      .spec_cols_line(spec@strata, "none"), max(x@strata_id),
      100 * x@manifest$strata_constant_share[1L]
    ),
    "*" = sprintf("Unit of on: %s", .spec_cols_line(spec@unit, "row")),
    "*" = sprintf(
      "Datasets: 1 null, %d negative, %d positive",
      spec@n, if (is.null(spec@target)) 0L else spec@n
    ),
    "*" = "Seeds: present"
  ))
  if (nrow(x@truth)) {
    cli::cli_h2("Planted truth (positive minus negative, per level of on)")
    print(x@truth[, c(
      "target", "level", "effect_sd", "sd_y", "sd_within_strata",
      "shift_realised"
    )])
  }
  if (length(x@notes)) {
    cli::cli_h2("Notes")
    cli::cli_bullets(stats::setNames(x@notes, rep("!", length(x@notes))))
  }
  invisible(x)
})
