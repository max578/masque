# Make a synthetic copy of one table

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
  mode = c("null", "local", "collaborate"),
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
  noise = c("summary", "standard"),
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
  (possibly edited), or a
  [`masque_plan()`](https://max578.github.io/masque/reference/masque_plan.md).
  A plan supplies `coords`, `events`, `conditional`, `ladder`, `grain`
  and `alias_names` where the call leaves them out, and its control
  specs are resolved on `df` and written back to the recipe. Tables from
  masque \<= 0.5.0 are upgraded with a deprecation warning; see
  [`roles_validate()`](https://max578.github.io/masque/reference/roles_validate.md).

- mode:

  One of `"null"`, `"local"` or `"collaborate"`. When omitted, inherit
  `attr(roles, "mode")`, falling back to `"null"` (with a
  `masque_mode_unset` warning) for a roles table with no mode
  provenance. A conditional clone needs `"local"` or `"collaborate"`;
  under `"null"` it is refused with `masque_null_conditional_refusal`.
  An explicit downgrade from `"null"` or `"collaborate"` to `"local"`
  raises a classed `masque_mode_downgrade` warning. A table of fewer
  than five rows in which any column would be re-simulated (a scrambled
  covariate, outcome, date or text column, a numeric or date noise
  column, or an `events` spec) is refused in null and collaborate mode
  with `masque_too_few_rows_refusal`, because such a clone is the
  original values resampled, or drawn from a summary that is close to
  them; local mode warns with `masque_too_few_rows`. A logical noise
  column counts, since it is drawn over the values it holds. Kept,
  aliased and dropped columns are not re-simulated, and factor and
  character noise draws codes only, so a short lookup table of those
  masks in any mode.

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

  `FALSE` (default), `TRUE`, `"design"`, or a character vector of column
  names. The *collaborate-grade conditional clone*. When `FALSE`,
  scrambled numeric columns are re-simulated from one global Gaussian
  copula - marginals and global covariance survive, but the
  treatment-to-outcome relationship does not, so a causal model fitted
  on the clone recovers a null effect. When `TRUE`, the numeric block is
  re-simulated *within each treatment-by-design stratum*, so a row's
  synthetic outcome inherits the location of the treatment that row
  carries. A causal model fitted on the conditional clone recovers the
  real treatment effect within sampling tolerance. The conditioning
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

  `"design"` conditions on the retained design columns alone. The clone
  keeps the design means, block and environment variance, while a
  treatment effect is not carried: a real effect moves into the
  residual, as it does when an owner permutes the treatment for a
  negative control, so the clone stands in for those negatives. The
  residual is not the one a real fit has. Linked `events` are stratified
  only by treatment columns of the partition, so `"design"` and a
  design-only partition do not keep their design means. A character
  vector of names gives the partition explicitly, from the retained
  design and treatment columns, and runs through the same ladder;
  treatment columns are still never dropped. The single word `"design"`
  always means this option, even where a column has that name.

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
  recipe as `conditioning_shifted`. The interaction of a dropped column
  with a kept treatment is not carried, so a multi-environment clone can
  keep its genotype and environment means and lose the
  genotype-by-environment pattern. Shrinkage of a shift uses the mean
  level size, so on unbalanced columns the small levels are shrunk less
  than their own size would give. `"levels"` is the ladder of masque
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
  and do not publish more than one jittered release of the same sites. A
  seed has 31 bits: where a clone shows site labels and holds two pairs
  at one place, it can be found by search.

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
  graded medium and the choice is recorded on the recipe. Null mode
  grades it the same way; local mode is unaffected.

- noise:

  The draw behind the `noise` action: `"summary"` (default) draws each
  numeric or date column independently from its 1st percentile, deciles
  and 99th percentile, interpolated linearly, so every draw lies between
  the 1st and 99th percentiles. Whole numbers stay whole, and the
  rounding can take a value just outside those percentiles. A column
  with fewer than 12 finite values takes the standard draw (see
  Details). `"standard"` reads only the column's type and draws on a
  fixed scale: a proportion from Beta(2, 2), a non-negative number from
  Gamma(2, 1), other numbers from N(0, 1), 0/1 values from
  Bernoulli(0.5), counts from Poisson(5) and dates uniformly within the
  year 2000. Columns with the same type flags draw the same values under
  one seed, whatever their means. Categorical columns are drawn
  uniformly over their levels either way.

- quiet:

  Single logical. `TRUE` silences the `masque_mode_downgrade` warning
  raised when a roles table prepared for `"null"` or `"collaborate"` is
  used in `"local"` mode, for a plan that is deliberately shared across
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

By default (`mode = "null"`), every outcome and covariate is simulated
independently. Each numeric column keeps only an eleven-point summary:
its 1st percentile, deciles and 99th percentile. Only the experimental
design and the pattern of missing values are kept exactly, and category
labels are replaced by codes. Identifier, free-text and unsupported
columns are dropped. The clone carries no relationship between columns,
so it suits writing and testing code, not estimating effects.

`mode = "local"` keeps structure (a Gaussian copula over the numeric
columns, empirical marginals, real labels by default) and marks the
synthetic for owner development only; the reminder is recorded on the
recipe and shown when the object prints. `mode = "collaborate"` keeps
that structure, hides labels, jitters re-simulated numerics within their
measurement resolution (stochastically rounding integers) and runs
[`audit_mask()`](https://max578.github.io/masque/reference/audit_mask.md)
automatically. Null mode runs the audit too. In both, a HIGH finding is
raised as a classed warning (`masque_high_leakage`) and blocks the
package-managed writers
([`masque()`](https://max578.github.io/masque/reference/masque.md)'s
`out`,
[`write_set()`](https://max578.github.io/masque/reference/write_set.md))
until it is resolved or explicitly overridden. Which columns are
aliased, kept, or dropped is decided by the `action` column of `roles` -
[`propose_roles()`](https://max578.github.io/masque/reference/propose_roles.md)
resolves mode-appropriate defaults, so the table you reviewed is the
plan that runs.

The mode changes the transformations and decides whether the audit runs.
Whether a synthetic table is appropriate for a given collaborator,
environment or jurisdiction is a release decision for the data owner.
masque informs that decision. It does not make it.

## Behaviour by action

- `keep`:

  Byte-identical pass-through, in every mode.

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

  Column excluded from the synthetic, in every mode.

- `noise`:

  Outcome, covariate and date columns only. The column is replaced by
  independent draws, row by row, that use nothing from its values except
  a coarse summary (see `noise`). Categorical columns are drawn
  uniformly over their levels, which are replaced by codes `<col>_LNNN`.
  A logical column stays logical and is drawn uniformly over the values
  it holds, so a logical that is always `TRUE` stays `TRUE` (with a
  `masque_noise_single_value` warning, as for a numeric column with one
  observed value). A column constant within a design unit gets one draw
  per unit. The default for these roles in null mode.

Summary noise needs at least 12 finite values, since eleven or fewer are
recovered exactly from the eleven summary points. A shorter numeric,
date or logical noise column takes the standard draw instead, with a
`masque_noise_small_sample` warning; for a column constant within a
design unit the count is of units with an observed value.

The NA mask of every retained column is preserved cell-by-cell, and
`NaN`, `Inf` and `-Inf` cells are kept in place like the missing cells.
A `POSIXlt` column is returned as `POSIXct`. An `integer64` column that
would be read (any action other than `keep` or `drop`) is refused with
`masque_integer64_refusal`; convert it with
[`as.numeric()`](https://rdrr.io/r/base/numeric.html) or
[`as.character()`](https://rdrr.io/r/base/character.html) first. RNG
state is preserved across the call. Null mode draws from a stream of its
own, so a null clone and a local or collaborate clone made with the same
seed are not paired row by row.

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
#>    Sepal.Length Sepal.Width Petal.Length Petal.Width      Species
#>           <num>       <num>        <num>       <num>       <fctr>
#> 1:     5.959447    2.644060     4.539749   0.1717018 Species_L002
#> 2:     5.078844    3.419512     4.415627   0.3068617 Species_L003
#> 3:     5.483718    3.028314     4.020137   2.4938487 Species_L003
#> 4:     4.655556    3.457193     1.166039   0.2856854 Species_L002
#> 5:     7.314096    3.000000     3.249417   1.6197431 Species_L001
#> 6:     6.716410    2.600369     4.376526   2.2166632 Species_L003

# Structure (a copula over the numeric columns) is opt-in.
r_local <- propose_roles(iris, mode = "local")
m_local <- mask(iris, r_local, seed = 1)
head(synthetic(m_local))
#>    Sepal.Length Sepal.Width Petal.Length Petal.Width    Species
#>           <num>       <num>        <num>       <num>     <fctr>
#> 1:          5.1         3.2          4.0         1.5 versicolor
#> 2:          6.0         3.0          3.7         0.4  virginica
#> 3:          5.0         3.0          4.6         1.1     setosa
#> 4:          7.2         2.6          5.8         1.7 versicolor
#> 5:          6.1         2.4          5.8         1.5  virginica
#> 6:          5.0         2.7          4.5         1.4 versicolor
```
