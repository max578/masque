# A masking plan: roles and named specs in one object

Holds what a
[`mask()`](https://max578.github.io/masque/reference/mask.md) call needs
apart from the table: the roles, the coordinate and event declarations,
the conditioning choice and any named
[`control_spec()`](https://max578.github.io/masque/reference/control_spec.md)s.
`mask(df, plan)` reads them from the plan; an argument passed to
[`mask()`](https://max578.github.io/masque/reference/mask.md) as well
overrides the plan's value for that call.

## Usage

``` r
masque_plan(
  roles,
  coords = NULL,
  events = NULL,
  conditional = FALSE,
  ladder = c("hierarchy", "levels"),
  grain = TRUE,
  alias_names = FALSE,
  controls = NULL
)
```

## Arguments

- roles:

  A roles table from
  [`propose_roles()`](https://max578.github.io/masque/reference/propose_roles.md).

- coords, events, conditional, ladder, grain, alias_names:

  As in [`mask()`](https://max578.github.io/masque/reference/mask.md).

- controls:

  `NULL`, one
  [`control_spec()`](https://max578.github.io/masque/reference/control_spec.md),
  or a named list of them. A single spec is named `default`.

## Value

A `masque_plan` object.

## Details

At [`mask()`](https://max578.github.io/masque/reference/mask.md) each
control spec is resolved on the source table and written back: its unit,
its strata, the grain of its columns and its effect vector. The clone
does not depend on the specs. The resolved plan is on the recipe, and
[`clone_plan()`](https://max578.github.io/masque/reference/clone_plan.md)
gives the same plan in clone vocabulary for the analyst.

A spec's `unit`, where not declared, resolves to the coarsest design
partition within which `on` is constant, or to the row. Its `strata`,
where not declared, resolve to the finest design partition above the
unit in which every stratum holds every level of `on`, or to none. A
stratum that misses levels of `on` would keep part of the real effect in
a negative control, so incomplete blocks are not chosen by default.
Declare a whole-plot unit where few plots hold more than one row: it is
taken only when a quarter of the rows share a unit.

A drawn effect, `list(sd = )`, is drawn over the clone's labels and
shows nothing of the source. A declared effect is written to the clone
plan as given, so values that rise with a level reveal that level's
rank.

## See also

[`mask()`](https://max578.github.io/masque/reference/mask.md),
[`clone_plan()`](https://max578.github.io/masque/reference/clone_plan.md),
[`save_plan()`](https://max578.github.io/masque/reference/save_plan.md),
[`controls()`](https://max578.github.io/masque/reference/controls.md),
[`handover()`](https://max578.github.io/masque/reference/handover.md).

## Examples

``` r
trial <- read.csv(system.file("extdata", "john_alpha.csv", package = "masque"))
r <- propose_roles(trial, mode = "local", detect = FALSE)
r <- set_role(r, c("rep", "block"), role = "design", action = "keep")
r <- set_role(r, "gen", role = "treatment", action = "alias")
r <- set_role(r, "yield", role = "outcome", action = "scramble")
r <- set_role(r, c("plot", "row", "col"), role = "id", action = "keep")
p <- masque_plan(
  r,
  conditional = "design",
  controls = control_spec(
    on = "gen", target = "yield", effect = list(sd = 0.5), n = 5L, seed = 7L
  )
)
p
#> 
#> ── masque_plan (source vocabulary) ─────────────────────────────────────────────
#> • Roles: 2 design, 1 treatment, 1 outcome, 3 id
#> • Conditional: design
#> • Ladder: hierarchy; grain: TRUE
#> • Column names aliased: FALSE
#> • Coordinate pairs: 0
#> • Linked-event specs: 0
#> • Control specs: 1
#> default
#>   on gen, unit row
#>   strata none
#>   target yield; replicates: 5
m <- mask(trial, p, mode = "local", seed = 1L)
#> Warning: Conditional clone: cells of the finest conditioning stratum held fewer than 5 rows, so the ladder coarsened it by dropping block. Conditioning on: rep. The main effect of block is carried into the clone as an additive shift; its interaction with a kept treatment is not.
clone_plan(m)
#> 
#> ── masque_plan (clone vocabulary) ──────────────────────────────────────────────
#> • Roles: 2 design, 1 treatment, 1 outcome, 3 id
#> • Conditional: design
#> • Ladder: hierarchy; grain: TRUE
#> • Column names aliased: FALSE
#> • Coordinate pairs: 0
#> • Linked-event specs: 0
#> • Control specs: 1
#> default
#>   on gen, unit row
#>   strata rep
#>   target yield; replicates: 5
```
