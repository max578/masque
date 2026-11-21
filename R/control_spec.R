# control_spec.R -- control_spec(): the declaration behind controls().

#' Internal: the masque_control_spec S7 class
#'
#' A container for one validated declaration; constructed by
#' [control_spec()] only.
#'
#' @keywords internal
#' @noRd
masque_control_spec <- S7::new_class(
  "masque_control_spec",
  properties = list(
    on = S7::new_property(
      class = S7::new_union(S7::class_character, NULL), default = NULL
    ),
    target = S7::new_property(
      class = S7::new_union(S7::class_character, NULL), default = NULL
    ),
    # A named numeric vector of level shifts in outcome-SD units, or
    # `list(sd = )` until the spec meets a table and the vector is drawn.
    effect = S7::new_property(
      class = S7::new_union(S7::class_list, S7::class_numeric, NULL),
      default = NULL
    ),
    strata = S7::new_property(
      class = S7::class_character, default = character()
    ),
    unit = S7::new_property(class = S7::class_character, default = character()),
    grain = S7::new_property(class = S7::class_list, default = list()),
    n = S7::new_property(class = S7::class_integer, default = 1L),
    seed = S7::class_integer
  )
)

#' Declare the controls to derive from a table
#'
#' A control spec says what [controls()] permutes and plants: the column
#' the negative control reassigns (`on`), the outcome the
#' positive control plants an effect on (`target`), the planted effect per
#' level of `on` in outcome-SD units (`effect`), the design strata within
#' which `on` is permuted and the unit it is permuted at, the other
#' unit-grained columns, the number of replicates and the seed. The spec is
#' declared once, before any control table exists, and is the record of
#' what was planted; print it to read the declaration.
#'
#' The null control needs nothing beyond the seed. The negative control
#' needs `on`, which defaults to the single treatment column of the table.
#' The positive control needs `target` and `effect` together.
#'
#' @param on The name of the column the negative control reassigns, by
#'   permuting it within `strata` at its `unit`. The outcome is not changed,
#'   so any real effect of `on` stays in it as unexplained variation. Must be
#'   a treatment or covariate column, categorical or
#'   whole-valued. `NULL` (the default) means the single treatment column of
#'   the table; a table with several or no treatment columns needs `on`
#'   named.
#' @param target The name of one or more numeric outcome columns the
#'   positive control plants the effect on, or `NULL` for no positive
#'   control. A logical, factor, date, event or two-valued column is
#'   refused when the spec meets the table.
#' @param effect The planted effect per level of `on`, in units of the
#'   target's standard deviation in the table at hand. That standard deviation
#'   includes the design variance and any real effect of `on`, so the size is
#'   not a multiple of an analysis's residual. Give it as a named numeric
#'   vector (`c(G01 = 0.5, G02 = -0.5)`; a level not named shifts by zero),
#'   or `list(sd = s)` to draw one shift per level from a normal
#'   distribution with standard deviation `s`, under the spec's seed, when
#'   the spec first meets a table. Required with `target`. On a whole-valued
#'   target the shift is rounded, which can change the ratios between levels;
#'   `shift_realised` in `@truth` holds the effect that is in the table, and a
#'   warning (class `masque_control_shape_rounded`) marks a changed shape.
#' @param strata Design columns within which `on` is permuted, or `NULL`
#'   for no stratification. Every unit of `on` must lie within one stratum.
#'   Prefer complete replicates to incomplete blocks; see [controls()].
#' @param unit Design columns within which `on` is constant. `on` is then
#'   permuted across those units, so name the unit `on` was assigned at.
#'   `NULL` (the default) permutes rows, and in a plan picks the coarsest design
#'   column on which `on` is constant and which has enough units for a 5 percent
#'   level, with a warning (class `masque_control_unit_ambiguous`) when several
#'   qualify.
#' @param grain A named list giving, for other analysed columns constant
#'   within a design unit, the unit columns: `list(rain = "trial")`. Such a
#'   column is permuted across its units in the null control, so it stays
#'   constant within each unit.
#' @param n The number of negative (and positive) replicates.
#' @param seed The seed of the control draws. Required.
#'
#' @returns A `masque_control_spec` object, with a print method.
#'
#' @examples
#' spec <- control_spec(
#'   on = "gen", target = "yield", effect = c(G01 = 0.5, G02 = -0.5),
#'   strata = "rep", n = 19L, seed = 2026L
#' )
#' spec
#'
#' @seealso [controls()], [control_table()].
#'
#' @export
control_spec <- function(
  on = NULL,
  target = NULL,
  effect = NULL,
  strata = NULL,
  unit = NULL,
  grain = NULL,
  n = 1L,
  seed = NULL
) {
  .check_control_seed(seed)
  on <- .check_control_names(on, "on", single = TRUE)
  target <- .check_control_names(target, "target", single = FALSE)
  effect <- .check_control_effect(effect, target)
  strata <- .check_control_cols(strata, "strata")
  unit <- .check_control_cols(unit, "unit")
  grain <- .check_control_grain(grain)
  n <- .check_control_n(n)
  masque_control_spec(
    on = on,
    target = target,
    effect = effect,
    strata = strata,
    unit = unit,
    grain = grain,
    n = n,
    seed = as.integer(seed)
  )
}

# Refusal helper -------------------------------------------------------------

# A classed refusal: `masque_control_<what>_refusal` under the shared marker.
# The message is interpolated in the caller's frame, where its values live.
.control_refuse <- function(msg, what, .envir = parent.frame()) {
  cli::cli_abort(
    msg,
    class = c(paste0("masque_control_", what, "_refusal"), "orchestra_refusal"),
    .envir = .envir
  )
}

# Argument checks ------------------------------------------------------------

# The seed is required: a control without a seed cannot be declared.
.check_control_seed <- function(seed) {
  if (is.null(seed)) {
    .control_refuse(
      c(
        "`seed` is required for a control spec.",
        i = "A control is reproducible from its declaration, so the seed is part of it."
      ),
      "seed"
    )
  }
  .check_seed(seed)
}

# `NULL`, or a character vector of column names, single when `single`.
.check_control_names <- function(x, arg, single) {
  if (is.null(x)) {
    return(NULL)
  }
  ok <- is.character(x) && length(x) >= 1L && !anyNA(x) && all(nzchar(x)) &&
    !anyDuplicated(x) && (!single || length(x) == 1L)
  if (!ok) {
    what <- if (single) "a single column name" else "one or more column names"
    .control_refuse("`{arg}` must be {what}, or `NULL`.", arg)
  }
  x
}

# `NULL` or a character vector of design column names.
.check_control_cols <- function(x, arg) {
  if (!length(x)) {
    return(character())
  }
  .check_control_names(x, arg, single = FALSE)
}

# `effect` and `target` come together: a named numeric vector of finite
# level shifts, or `list(sd = s)` with a single positive `s`.
.check_control_effect <- function(effect, target) {
  if (is.null(effect) && is.null(target)) {
    return(NULL)
  }
  if (is.null(effect) || is.null(target)) {
    .control_refuse(
      "`target` and `effect` are declared together: a positive control needs both.",
      "effect"
    )
  }
  if (is.numeric(effect)) {
    nms <- names(effect)
    ok <- length(effect) >= 1L && !is.null(nms) && all(nzchar(nms)) &&
      !anyDuplicated(nms) && all(is.finite(effect))
    if (!ok) {
      .control_refuse(
        "A numeric `effect` must be a named vector of finite level shifts, one name per level of `on`.",
        "effect"
      )
    }
    return(stats::setNames(as.double(effect), nms))
  }
  if (is.list(effect)) {
    ok <- identical(names(effect), "sd") && is.numeric(effect$sd) &&
      length(effect$sd) == 1L && is.finite(effect$sd) && effect$sd > 0
    if (ok) {
      return(list(sd = as.double(effect$sd)))
    }
  }
  .control_refuse(
    "`effect` must be a named numeric vector of level shifts or `list(sd = s)` with a single positive `s`.",
    "effect"
  )
}

# `NULL` or a named list of character vectors: column -> its unit columns.
.check_control_grain <- function(grain) {
  if (is.null(grain)) {
    return(list())
  }
  nms <- names(grain)
  ok <- is.list(grain) && length(grain) >= 1L && !is.null(nms) &&
    all(nzchar(nms)) && !anyDuplicated(nms) &&
    all(vapply(grain, function(u) {
      is.character(u) && length(u) >= 1L && !anyNA(u) && all(nzchar(u))
    }, logical(1L)))
  if (!ok) {
    .control_refuse(
      "`grain` must be a named list of unit column names, as in `list(rain = \"trial\")`.",
      "grain"
    )
  }
  grain
}

# A single whole number of replicates, at least one.
.check_control_n <- function(n) {
  ok <- is.numeric(n) && length(n) == 1L && !is.na(n) && is.finite(n) &&
    n == round(n) && n >= 1L
  if (!ok) {
    .control_refuse("`n` must be a single whole number of replicates, at least 1.", "n")
  }
  as.integer(n)
}

# Print ----------------------------------------------------------------------

# local(): see the plot method in detect_plot.R.
local(S7::method(print, masque_control_spec) <- function(x, ...) {
  cli::cli_h1("masque_control_spec")
  cli::cli_bullets(c(
    "*" = sprintf("Permuted column (on): %s", .spec_on_line(x)),
    "*" = sprintf("Planted-effect target: %s", .spec_target_line(x)),
    "*" = sprintf("Effect (target-SD units): %s", .spec_effect_line(x)),
    "*" = sprintf("Strata: %s", .spec_cols_line(x@strata, "none")),
    "*" = sprintf("Unit of on: %s", .spec_cols_line(x@unit, "row")),
    "*" = sprintf("Unit-grained columns: %s", .spec_grain_line(x)),
    "*" = sprintf("Replicates: %d", x@n),
    "*" = "Seed: present"
  ))
  invisible(x)
})

.spec_on_line <- function(x) {
  if (is.null(x@on)) "the treatment column of the table" else x@on
}

.spec_target_line <- function(x) {
  if (is.null(x@target)) "none" else paste(x@target, collapse = ", ")
}

.spec_effect_line <- function(x) {
  if (is.null(x@effect)) {
    return("none (no positive control)")
  }
  if (is.list(x@effect)) {
    return(sprintf(
      "one shift per level drawn from N(0, %s^2) when the spec meets a table",
      format(x@effect$sd)
    ))
  }
  paste(sprintf("%s %+.3g", names(x@effect), x@effect), collapse = ", ")
}

.spec_cols_line <- function(cols, empty) {
  if (length(cols)) paste(cols, collapse = " + ") else empty
}

.spec_grain_line <- function(x) {
  if (!length(x@grain)) {
    return("none declared")
  }
  units <- vapply(x@grain, paste, character(1L), collapse = " + ")
  paste(sprintf("%s within %s", names(x@grain), units), collapse = "; ")
}
