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
  .shared_maps = list(),
  ...
)
```

## Arguments

- df:

  A data frame.

- roles:

  A roles table from
  [`propose_roles()`](https://max578.github.io/masque/reference/propose_roles.md)
  (possibly edited). Tables from masque \<= 0.5.0 are upgraded with a
  deprecation warning; see
  [`roles_validate()`](https://max578.github.io/masque/reference/roles_validate.md).

- mode:

  Either `"local"` (default) or `"collaborate"`.

- seed:

  Optional integer for reproducibility.

- clean:

  Column-name and label hygiene before masking, passed to
  [`clean_table()`](https://max578.github.io/masque/reference/clean_table.md):
  one of `"auto"` (default - legalise names, trim whitespace, report
  near-duplicates), `"report"`, or `"off"`. When names are legalised,
  the `roles` table's column references are remapped to match, so a
  `roles` table built against the dirty names still applies. The fixes
  are recorded in the recipe and re-applied by
  [`apply_recipe()`](https://max578.github.io/masque/reference/apply_recipe.md).

- alias_names:

  Hide the column names themselves. `FALSE` (the default) keeps them.
  `TRUE` replaces every retained column name with an opaque alias
  (`col_001`, `col_002`, ... in column order). A character vector names
  just the columns to alias. The original-to-alias map is stored in the
  recipe and inverted by
  [`apply_recipe()`](https://max578.github.io/masque/reference/apply_recipe.md)
  / [`unmask()`](https://max578.github.io/masque/reference/unmask.md),
  so a pipeline written against the aliased synthetic round-trips.
  Column names are the last identifying surface a kept or design column
  exposes; alias them when even the schema is sensitive.

- conditional:

  Logical scalar (default `FALSE`). The *collaborate-grade conditional
  clone*. When `FALSE`, scrambled numeric columns are re-simulated from
  one global Gaussian copula - marginals and global covariance survive,
  but the treatment-to-outcome relationship does not, so a causal model
  fitted on the clone recovers a null effect. When `TRUE`, the numeric
  block is re-simulated *within each treatment-by-design stratum*, so a
  row's synthetic outcome inherits the location of the treatment that
  row carries. A causal model fitted on the conditional clone recovers
  the real treatment effect within sampling tolerance - the data-side
  analogue of preserving a conditional mean embedding rather than a
  pooled marginal. The conditioning columns (treatment plus retained
  design) are recorded on the recipe. With no treatment or design column
  to condition on, the path degrades cleanly to the global copula and a
  note is emitted.

- .shared_maps:

  Internal. A named list of pre-computed `original -> alias` level maps
  for cross-table linked columns, set by
  [`mask_set()`](https://max578.github.io/masque/reference/mask_set.md).
  Not for direct use.

- ...:

  Must be empty. An unused argument (for example a misspelled name)
  errors rather than being silently ignored.

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

Collaborate mode adjusts the transformations and runs the audit; it does
not model where the output will go. Whether a synthetic table is
appropriate for a given collaborator, environment, or jurisdiction is a
release decision that stays with the data custodian - masque informs
that decision, it does not make it.

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
  treatment factors are aliased), categorical covariates `<col>_LNNN`,
  design labels `<col>_DNNN` (in place - structure intact), ids
  `<col>_INNN` (in place - row linkage intact), text values
  `<col>_TNNN`.

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
[`reveal_maps()`](https://max578.github.io/masque/reference/reveal_maps.md).

## Examples

``` r
r <- propose_roles(iris)
r <- set_role(r, "Sepal.Length", role = "outcome")
m <- mask(iris, r, seed = 1)
head(synthetic(m))
#> # A tibble: 6 × 5
#>   Sepal.Length Sepal.Width Petal.Length Petal.Width Species
#>          <dbl>       <dbl>        <dbl>       <dbl> <fct>  
#> 1          5.1         3.2          4           1.5 setosa 
#> 2          6           3            3.7         0.4 setosa 
#> 3          5           3            4.6         1.1 setosa 
#> 4          7.2         2.6          5.8         1.7 setosa 
#> 5          6.1         2.4          5.8         1.5 setosa 
#> 6          5           2.7          4.5         1.4 setosa 
```
