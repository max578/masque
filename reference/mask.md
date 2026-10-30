# Mask a tabular dataset into a structurally faithful development surrogate

Takes one data frame and a user-edited `roles` table (from
[`propose_roles()`](https://max578.github.io/masque/reference/propose_roles.md),
possibly adjusted with
[`set_role()`](https://max578.github.io/masque/reference/set_role.md))
and produces a synthetic clone according to each column's `action`.
Returns a `masque` S7 object holding the synthetic data and a private
`masque_recipe`.

## Usage

``` r
mask(
  df,
  roles,
  mode = c("local", "collaborate"),
  seed = NULL,
  clean = c("auto", "report", "off"),
  alias_names = FALSE,
  conditional = FALSE,
  ladder = c("hierarchy", "levels"),
  coords = NULL,
  events = NULL,
  grain = TRUE,
  allow_unmasked_coords = FALSE,
  allow_kept_outcome = FALSE,
  quiet = FALSE,
  .shared_maps = list(),
  .cleaning = NULL,
  ...
)
```

## Arguments

- df:

  A data frame, or the `masque_conformance` object returned by
  [`conform_table()`](https://max578.github.io/masque/reference/conform_table.md),
  whose `data` element is then masked. Its cleaning record and its
  merges and type changes go on the recipe, so
  [`apply_recipe()`](https://max578.github.io/masque/reference/apply_recipe.md)
  replays them; `clean` is not applied a second time.

- roles:

  A roles table from
  [`propose_roles()`](https://max578.github.io/masque/reference/propose_roles.md)
  (possibly edited). Tables from masque \<= 0.5.0 are upgraded with a
  deprecation warning; see
  [`roles_validate()`](https://max578.github.io/masque/reference/roles_validate.md).

- mode:

  Either `"local"` or `"collaborate"`. When omitted, inherit
  `attr(roles, "mode")`, falling back to `"local"` for a roles table
  with no mode provenance. An explicit collaborate-to-local downgrade
  raises a classed `masque_mode_downgrade` warning. A table of fewer
  than five rows in which any column would be re-simulated (a scrambled
  covariate, outcome, date or text column, or an `events` spec) is
  refused in collaborate mode with `masque_too_few_rows_refusal`,
  because such a clone is the original values resampled; local mode
  warns with `masque_too_few_rows`. Kept, aliased and dropped columns
  are not re-simulated, so a short lookup table of those masks in either
  mode.

- seed:

  Optional integer for reproducibility.

- clean:

  Label and column-name hygiene before masking, passed to
  [`clean_table()`](https://max578.github.io/masque/reference/clean_table.md):
  one of `"auto"` (default - trim whitespace and report near-duplicate
  labels), `"report"` (report only), or `"off"` (skip). Invalid column
  names are legalised in **every** mode – an invalid name silently
  rewritten during synthesis corrupts the clone – and the repair is
  raised as a `masque_name_repaired` warning. The `roles` table's column
  references are remapped to the legalised names, the fixes are recorded
  in the recipe, and
  [`apply_recipe()`](https://max578.github.io/masque/reference/apply_recipe.md)
  / [`unmask()`](https://max578.github.io/masque/reference/unmask.md)
  reverse them on the round-trip.

- alias_names:

  Hide the column names themselves. `FALSE` (the default) keeps them.
  `TRUE` replaces every retained column name with an opaque alias
  (`col_001`, `col_002`, ... in column order). A character vector names
  just the columns to alias. The original-to-alias map is stored in the
  recipe and inverted by
  [`apply_recipe()`](https://max578.github.io/masque/reference/apply_recipe.md)
  / [`unmask()`](https://max578.github.io/masque/reference/unmask.md),
  so a pipeline written against the aliased synthetic round-trips. Alias
  the names when the schema itself is sensitive.

- conditional:

  Logical scalar (default `FALSE`). The *collaborate-grade conditional
  clone*. When `FALSE`, scrambled numeric columns are re-simulated from
  one global Gaussian copula - marginals and global covariance survive,
  but the treatment-to-outcome relationship does not, so a causal model
  fitted on the clone recovers a null effect. When `TRUE`, the numeric
  block is re-simulated *within each treatment-by-design stratum*, so a
  row's synthetic outcome inherits the location of the treatment that
  row carries. A causal model fitted on the conditional clone recovers
  the real treatment effect within sampling tolerance. The conditioning
  columns (treatment plus retained design) are recorded on the recipe.

  The stratum is chosen by a **coarsening ladder**. Treatment crossed
  with every retained design column is the finest rung, but on a
  replicated factorial that rung holds one row per cell, which is too
  thin to synthesise. The ladder then drops design columns, in the order
  set by `ladder`, until the cells hold at least five rows; treatment
  columns are never dropped. Whatever remains below that floor is pooled
  into a global fallback. The rung reached is recorded on the recipe as
  `conditioning_used`, the columns given up as `conditioning_dropped`,
  the pooled share as `fallback_frac`, and any coarsening or residual
  pooling raises a classed `masque_conditional_degraded` warning –
  including the case where no treatment or design column survives at
  all, in which case the clone is the pooled copula.

- ladder:

  How the coarsening ladder orders the design columns it may drop, and
  what it keeps of a dropped one. `"hierarchy"` (the default) drops plot
  coordinates (`row`, `col`, `range`, `plot`) first, then blocking
  columns, then environment columns (`site`, `year`, `county`, `trial`,
  ...), so an environment is never dropped before the replicates inside
  it; within the last two tiers the column explaining the least variance
  in the numeric block (adjusted for its number of levels) goes first.
  The main effect of every dropped column, and of each pair of dropped
  blocking or environment columns (the replicate inside a county is a
  different block from the same label in the next county), is estimated
  by least squares beside the stratum that was kept, removed before the
  within-stratum copula and added back after it. A clone that conditions
  on genotype alone therefore still has the original's environment,
  replicate and block means. Rows pooled into the fallback stratum keep
  the stratum columns' main effects the same way, which is how a
  three-replicate variety trial keeps its genotype means. A level with a
  single row is pooled with the other singletons before the fit, so no
  row's own outcome is carried. The terms carried are recorded on the
  recipe as `conditioning_shifted`. `"levels"` is the ladder of masque
  0.11.1 to 0.12.0: columns are dropped in decreasing order of distinct
  values and a dropped column leaves no trace in the clone.

- coords:

  Optional geographic-coordinate declaration. Supply one or more
  latitude/longitude pairs and each is coarsened in place by an on-land
  jitter (see
  [`jitter_coordinates()`](https://max578.github.io/masque/reference/jitter_coordinates.md))
  instead of being copula-scrambled into implausible locations. A pair
  is a named vector `c(lat = "lat_col", lon = "lon_col")` or a named
  list that also carries jitter parameters (`by`, `method`, `min_km`,
  `max_km`, `sd_km`, `on_land`); a single pair may be passed bare, and
  several pairs as a list of pairs. Defaults to a donut of 5-20 km on
  land. A declared column must have the action `keep` in `roles`; any
  other action, including the `drop` that
  [`propose_roles()`](https://max578.github.io/masque/reference/propose_roles.md)
  proposes for a coordinate-named column, is refused with a
  `masque_coords_action_refusal` error. One displacement is drawn per
  **site** and broadcast to that site's rows: `by` names the columns of
  `df` that identify a site, and is omitted when rows sharing an
  identical input coordinate already identify one. A declared pair
  always survives masking, coarsened; the recipe records the parameters
  and the site grouping it was coarsened under, and
  [`apply_recipe()`](https://max578.github.io/masque/reference/apply_recipe.md)
  retargets to the real coordinates. Several published jitters of the
  same point average toward it: keep the seed, which the recipe records,
  and do not publish more than one jittered release of the same sites.

- events:

  Optional linked time-to-event outcomes. One spec per group of linked
  events, `list(time = c(...), status = c(...))`, with the time and
  status columns listed in the order the events occur; pass several
  specs as a list. Every column must have role `outcome` and action
  `scramble`, times must be numeric and in order in `df`, status columns
  must hold whole-numbered codes, and none may be missing. The times are
  turned into gaps between successive events, the rows' status patterns
  are permuted (within treatment when `conditional = TRUE`), and the
  gaps are re-simulated within each status pattern by the empirical
  copula, then summed back into times. Times therefore stay ordered, a
  gap that every row of a pattern holds at zero stays zero, and the
  count of each status pattern is exact. A summed final time is capped
  at the longest final time observed in the rows its gaps were drawn
  from (the pattern, within treatment when conditional), so no clone row
  runs past the observed follow-up. Only the final time and the times
  tied to it move; a row whose earlier time already passes the cap is
  scaled down as a whole, which keeps its order and its zero gaps. The
  recipe records how many rows were capped. A pattern with fewer than
  five rows draws each of its free gaps from every pattern in which that
  gap is free, with a `masque_events_pooled` warning; when no other
  pattern has the gap free, `mask()` stops. No hazard model is fitted
  and no covariate-to-event relation is kept.

- grain:

  Single logical (default `TRUE`). Synthesise each column at its
  **grain**: a scrambled covariate, outcome or date column, or an
  aliased categorical covariate, that holds at most one distinct
  non-missing value within every unit of a retained design column, or of
  a pair of them (`site:year`), is re-simulated once per unit and each
  unit's new value is written to that unit's rows. The grain is the
  coarsest such unit with at least two units and at least two rows per
  unit on average; a unit with no value stays missing. Numeric columns
  of one grain are drawn jointly through the copula on the unit-level
  table (with collaborate-mode jitter against the unit-level values),
  and categorical and date columns are permuted across units, then
  aliased where their action is `alias`. The clone therefore keeps one
  value per unit, the frequencies of a categorical across units, and the
  correlation among columns of the same grain. It does **not** keep the
  correlation between a grained column and row-level columns, and
  grained columns are not conditioned on treatment when
  `conditional = TRUE`. In local mode the unit values are drawn from the
  original unit values. In collaborate mode a grain with fewer than five
  units is synthesised row by row instead, with a
  `masque_grain_small_units` warning, because resampling that few real
  values would disclose them. Each grain is recorded on the recipe
  (`grain`) with a line in its warnings. `FALSE` synthesises every
  column row by row, as masque 0.15 did; detected grains are still
  recorded. Coordinates declared to `coords`, `events` columns and
  linked columns are never grained.

- allow_unmasked_coords:

  Single logical. A masked table must not carry a real coordinate, so by
  default `mask()` **stops** when a column whose name says coordinate
  (`gps`, `lat`, `lon`, `easting`, ...) would be written through
  unmasked, and warns when a column detected only by the shape of its
  values would be. State otherwise by declaring the pair to `coords`
  (coarsened), giving the column a masking action (`drop` or
  `scramble`), or – having decided the coordinate is not sensitive –
  setting this to `TRUE`, which is recorded on the recipe.

- allow_kept_outcome:

  Single logical. In collaborate mode an outcome with the action `keep`
  carries its real values beside the re-simulated columns, so
  [`audit_mask()`](https://max578.github.io/masque/reference/audit_mask.md)
  grades it HIGH and the collaborate write gate stops it. Having decided
  the real outcome may be shared, set this to `TRUE`: the column is then
  graded medium and the choice is recorded on the recipe. Local mode is
  unaffected.

- quiet:

  Single logical. `TRUE` silences the `masque_mode_downgrade` warning
  raised when a roles table prepared for `"collaborate"` is used in
  `"local"` mode, for a plan that is deliberately shared across both
  modes. No other warning is affected; a HIGH-leakage finding is always
  raised.

- .shared_maps:

  Internal. A named list of pre-computed `original -> alias` level maps
  for cross-table linked columns, set by
  [`mask_set()`](https://max578.github.io/masque/reference/mask_set.md).
  Not for direct use.

- .cleaning:

  Internal. The cleaning record of a table
  [`mask_set()`](https://max578.github.io/masque/reference/mask_set.md)
  has already cleaned; `mask()` then skips its own cleaning and stores
  this record on the recipe. Not for direct use.

- ...:

  Must be empty. An unused argument, for example a misspelled name, is
  an error.

## Value

A `masque` S7 object. Use
[`synthetic()`](https://max578.github.io/masque/reference/synthetic.md)
and [`recipe()`](https://max578.github.io/masque/reference/recipe.md) to
extract the components.

## Details

`mode = "local"` marks the synthetic for owner development only; the
reminder is recorded on the recipe and shown when the object prints.
`mode = "collaborate"` additionally jitters re-simulated numerics within
their measurement resolution (stochastically rounding integers) and runs
[`audit_mask()`](https://max578.github.io/masque/reference/audit_mask.md)
automatically; a HIGH finding is raised as a classed warning
(`masque_high_leakage`) and blocks the package-managed writers
([`masque()`](https://max578.github.io/masque/reference/masque.md)'s
`out`,
[`write_set()`](https://max578.github.io/masque/reference/write_set.md))
until it is resolved or explicitly overridden. Which columns are
aliased, kept, or dropped is decided by the `action` column of `roles` -
[`propose_roles()`](https://max578.github.io/masque/reference/propose_roles.md)
resolves mode-appropriate defaults, so the table you reviewed is the
plan that runs.

Collaborate mode changes the transformations and runs the audit. Whether
a synthetic table is appropriate for a given collaborator, environment
or jurisdiction is a release decision for the data custodian; masque
informs that decision, it does not make it.

## Behaviour by action

- `keep`:

  Byte-identical pass-through, both modes.

- `scramble`:

  Numeric outcome / covariate columns are re-simulated jointly via a
  Gaussian copula on the global Pearson covariance, with
  empirical-quantile marginals. Categorical, date, and text columns are
  row-permuted within non-NA positions, class preserved. Treatment
  columns get a seeded label permutation - the assignment structure
  never moves.

- `alias`:

  As `scramble` where applicable, plus opaque label substitution:
  treatments become `trt_NNN` (`<col>_trt_NNN` when two or more
  treatments are aliased. A numeric treatment becomes text, and
  [`unmask()`](https://max578.github.io/masque/reference/unmask.md)
  restores its exact values), categorical covariates `<col>_LNNN`,
  design labels `<col>_DNNN` (in place - structure intact), ids
  `<col>_INNN` (in place - row linkage intact), text values
  `<col>_TNNN`. A key
  [`mask_set()`](https://max578.github.io/masque/reference/mask_set.md)
  shares across tables becomes `<col>_KNNN`. `NNN` has at least three
  digits.

- `drop`:

  Column excluded from the synthetic, both modes.

The NA mask of every retained column is preserved cell-by-cell. RNG
state is preserved across the call.

## See also

[`propose_roles()`](https://max578.github.io/masque/reference/propose_roles.md),
[`set_role()`](https://max578.github.io/masque/reference/set_role.md),
[`roles_validate()`](https://max578.github.io/masque/reference/roles_validate.md),
[`synthetic()`](https://max578.github.io/masque/reference/synthetic.md),
[`recipe()`](https://max578.github.io/masque/reference/recipe.md),
[`roles()`](https://max578.github.io/masque/reference/roles.md),
[`reveal_maps()`](https://max578.github.io/masque/reference/reveal_maps.md),
[`audit_mask()`](https://max578.github.io/masque/reference/audit_mask.md),
[`data_card()`](https://max578.github.io/masque/reference/data_card.md).

## Examples

``` r
r <- propose_roles(iris)
r <- set_role(r, "Sepal.Length", role = "outcome")
m <- mask(iris, r, seed = 1)
head(synthetic(m))
#>    Sepal.Length Sepal.Width Petal.Length Petal.Width    Species
#>           <num>       <num>        <num>       <num>     <fctr>
#> 1:          5.1         3.2          4.0         1.5 versicolor
#> 2:          6.0         3.0          3.7         0.4  virginica
#> 3:          5.0         3.0          4.6         1.1     setosa
#> 4:          7.2         2.6          5.8         1.7 versicolor
#> 5:          6.1         2.4          5.8         1.5  virginica
#> 6:          5.0         2.7          4.5         1.4 versicolor
```
