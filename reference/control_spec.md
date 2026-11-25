# Declare the controls to derive from a table

A control spec says what
[`controls()`](https://max578.github.io/masque/reference/controls.md)
permutes and plants: the column the negative control reassigns (`on`),
the outcome the positive control plants an effect on (`target`), the
planted effect per level of `on` in outcome-SD units (`effect`), the
design strata within which `on` is permuted and the unit it is permuted
at, the other unit-grained columns, the number of replicates and the
seed. The spec is declared once, before any control table exists, and is
the record of what was planted; print it to read the declaration.

## Usage

``` r
control_spec(
  on = NULL,
  target = NULL,
  effect = NULL,
  strata = NULL,
  unit = NULL,
  grain = NULL,
  n = 1L,
  seed = NULL
)
```

## Arguments

- on:

  The name of the column the negative control reassigns, by permuting it
  within `strata` at its `unit`. The outcome is not changed, so any real
  effect of `on` stays in it as unexplained variation. Must be a
  treatment or covariate column, categorical or whole-valued. `NULL`
  (the default) means the single treatment column of the table; a table
  with several or no treatment columns needs `on` named.

- target:

  The name of one or more numeric outcome columns the positive control
  plants the effect on, or `NULL` for no positive control. A logical,
  factor, date, event or two-valued column is refused when the spec
  meets the table.

- effect:

  The planted effect per level of `on`, in units of the target's
  standard deviation in the table at hand. That standard deviation
  includes the design variance and any real effect of `on`, so the size
  is not a multiple of an analysis's residual. Give it as a named
  numeric vector (`c(G01 = 0.5, G02 = -0.5)`; a level not named shifts
  by zero), or `list(sd = s)` to draw one shift per level from a normal
  distribution with standard deviation `s`, under the spec's seed, when
  the spec first meets a table. Required with `target`. On a
  whole-valued target the shift is rounded, which can change the ratios
  between levels; `shift_realised` in `@truth` holds the effect that is
  in the table, and a warning (class `masque_control_shape_rounded`)
  marks a changed shape.

- strata:

  Design columns within which `on` is permuted, or `NULL` for no
  stratification. Every unit of `on` must lie within one stratum. Prefer
  complete replicates to incomplete blocks; see
  [`controls()`](https://max578.github.io/masque/reference/controls.md).

- unit:

  Design columns within which `on` is constant. `on` is then permuted
  across those units, so name the unit `on` was assigned at. `NULL` (the
  default) permutes rows, and in a plan picks the coarsest design column
  on which `on` is constant and which has enough units for a 5 percent
  level, with a warning (class `masque_control_unit_ambiguous`) when
  several qualify.

- grain:

  A named list giving, for other analysed columns constant within a
  design unit, the unit columns: `list(rain = "trial")`. Such a column
  is permuted across its units in the null control, so it stays constant
  within each unit.

- n:

  The number of negative (and positive) replicates.

- seed:

  The seed of the control draws. Required.

## Value

A `masque_control_spec` object, with a print method.

## Details

The null control needs nothing beyond the seed. The negative control
needs `on`, which defaults to the single treatment column of the table.
The positive control needs `target` and `effect` together.

## See also

[`controls()`](https://max578.github.io/masque/reference/controls.md),
[`control_table()`](https://max578.github.io/masque/reference/control_table.md).

## Examples

``` r
spec <- control_spec(
  on = "gen", target = "yield", effect = c(G01 = 0.5, G02 = -0.5),
  strata = "rep", n = 19L, seed = 2026L
)
spec
#> 
#> ── masque_control_spec ─────────────────────────────────────────────────────────
#> • Permuted column (on): gen
#> • Planted-effect target: yield
#> • Effect (target-SD units): G01 +0.5, G02 -0.5
#> • Strata: rep
#> • Unit of on: row
#> • Unit-grained columns: none declared
#> • Replicates: 19
#> • Seed: present
```
