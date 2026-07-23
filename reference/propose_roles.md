# Propose role and action classifications for the columns of a data frame

Generates a heuristic two-axis classification for every column of `df`:
a `role` (what the column *is*) and an `action` (what
[`mask()`](https://max578.github.io/masque/reference/mask.md) will *do*
to it). The user is expected to inspect this table and edit it -
directly or via
[`set_role()`](https://max578.github.io/masque/reference/set_role.md) -
before passing it to
[`mask()`](https://max578.github.io/masque/reference/mask.md).
Heuristics are seeds, not law.

## Usage

``` r
propose_roles(df, mode = c("local", "collaborate"), detect = TRUE)
```

## Arguments

- df:

  A data frame. Must have at least one column.

- mode:

  The masking mode the table is being prepared for: `"local"` (default)
  or `"collaborate"`. Stored as `attr(roles, "mode")` and used to
  resolve default actions.

- detect:

  Logical scalar (default `TRUE`). When `TRUE`, run
  [`detect_design()`](https://max578.github.io/masque/reference/detect_design.md)
  and overlay its recommended role hints.

## Value

A tibble with one row per column: `col`, `role`, `action`, `kind`
(storage kind: `numeric`, `integer`, `factor`, `character`, `logical`,
`date`, `datetime`, `other`), `freq_or_range`, `pii_suspected`, and
`notes`. The target mode is stored as `attr(roles, "mode")`.

## The two axes

`role` describes the column and determines the *mechanics* of any
synthesis:

- `design`:

  Experimental / structural columns (site, block, rep, plot, year).
  Mechanics of `alias`: labels are substituted in place, structure
  intact.

- `treatment`:

  Assignment columns (variety, genotype, dose). Labels are remapped in
  place - the assignment structure never moves. `scramble` = seeded
  label permutation; `alias` = opaque labels (`trt_001`).

- `outcome`:

  Numeric response columns. `scramble` re-simulates via the Gaussian
  copula, jointly with scrambled numeric covariates. Multiple outcomes
  are supported.

- `covariate`:

  Everything measured alongside. Numeric: copula re-simulation.
  Categorical: row permutation, plus opaque label aliasing under
  `alias`.

- `date`:

  Date / POSIX / difftime columns. `scramble` row- permutes within the
  observed values; class and NA pattern are preserved.

- `id`:

  Identifier columns. Never scrambled (that would break row linkage);
  `alias` substitutes opaque per-value labels in place, preserving
  linkage.

- `text`:

  Free-text columns. `scramble` row-permutes; `alias` tokenises each
  distinct string.

- `other`:

  Classes masque cannot synthesise (list columns, exotic S4, ...). Keep
  or drop only.

`action` sets the masking depth per column:

- `keep`:

  Byte-identical pass-through, both modes.

- `scramble`:

  Re-simulate (numeric) or row-permute (categorical / date / text);
  original label vocabulary remains visible.

- `alias`:

  Scramble where applicable, plus opaque label substitution - the
  vocabulary itself is hidden.

- `drop`:

  Column excluded from the synthetic, both modes.

The proposed `action` column is resolved for `mode`, so the table you
edit shows the actual masking plan. Re-assigning a column's role with
[`set_role()`](https://max578.github.io/masque/reference/set_role.md)
re-resolves its default action; a direct `roles$role[...] <- ...` edit
leaves `action` untouched (set it to `NA` to have
[`mask()`](https://max578.github.io/masque/reference/mask.md) re-resolve
the default).

## Default classification rules, applied in order

1.  PII-pattern column names (`contact`, `email`, `phone`, `gps`,
    `latitude` / `longitude`, `postcode`, `ssn`, `password`, `owner`,
    `farmer`, `operator`, etc., case-insensitive substring) -\>
    `pii_suspected = TRUE` and action `drop` in **both** modes. Re-role
    deliberately if the column must survive.

2.  Date / POSIXct / POSIXlt / difftime columns -\> role `date`, action
    `scramble` (row permutation).

3.  ID-pattern names (`\\bid\\b`, `_id$`, `^id_`) -\> role `id`; kept in
    local mode, dropped in collaborate mode.

4.  Design-pattern names (`rep`, `block`, `row`, `col(umn)?`, `range`,
    `plot(no)?`, `site`, `env(ironment)?`, `trial`, `year`, `season`,
    `colrep`, `tos`) -\> role `design`, action `keep`.

5.  Treatment-pattern names (`treatment`, `variety`, `cultivar`,
    `genotype`, `^trt`, `^dose`) -\> role `treatment`; kept in local
    mode, aliased in collaborate mode.

6.  Character columns with \> 50% unique values on non-NA -\> role
    `text`; kept in local mode, dropped in collaborate mode.

7.  Unsupported classes -\> role `other`, action `keep`, with a note.

8.  Everything else -\> role `covariate`, action `scramble`. Re-role
    response variables as `outcome`.

No outcome is required: with no column roled `outcome`, the copula
simply re-simulates all scrambled numeric columns jointly.

Since masque 0.3.0, `propose_roles()` also calls
[`detect_design()`](https://max578.github.io/masque/reference/detect_design.md)
by default (`detect = TRUE`) and applies the detected design's
`recommended_roles` on top of the name-based heuristic, re-resolving the
default action for any promoted column. The design summary is stashed as
`attr(roles, "design")`. Pass `detect = FALSE` for the name-only
heuristic.

## Multi-environment trials

Since masque 0.9.1, high-confidence environment columns detected by
[`detect_design()`](https://max578.github.io/masque/reference/detect_design.md)
are promoted to role `design`. In local mode their values remain
byte-identical. In collaborate mode categorical environment labels
default to `alias`, which preserves row assignment and factor codes
while hiding the vocabulary. Numeric environment columns default to
`keep` and raise a `masque_environment_disclosure` warning for explicit
review.

Weak or competing environment candidates never change roles
automatically. Inspect `attr(roles, "design")` and use
[`set_role()`](https://max578.github.io/masque/reference/set_role.md)
when domain knowledge should override an uncertain result. Preserving
environment allocation does not imply that synthesised outcomes preserve
treatment-by-environment effects. An explicitly chosen action is pinned
and is not overwritten by a later design-role promotion.

## See also

[`set_role()`](https://max578.github.io/masque/reference/set_role.md) to
edit;
[`roles_validate()`](https://max578.github.io/masque/reference/roles_validate.md)
for the fail-closed validation applied at
[`mask()`](https://max578.github.io/masque/reference/mask.md) time.

## Examples

``` r
propose_roles(iris)
#> # A tibble: 5 × 7
#>   col          role      action   kind    freq_or_range pii_suspected notes     
#>   <chr>        <chr>     <chr>    <chr>   <chr>         <lgl>         <chr>     
#> 1 Sepal.Length covariate scramble numeric [4.3, 7.9]    FALSE         Default -…
#> 2 Sepal.Width  covariate scramble numeric [2, 4.4]      FALSE         Default -…
#> 3 Petal.Length covariate scramble numeric [1, 6.9]      FALSE         Default -…
#> 4 Petal.Width  covariate scramble numeric [0.1, 2.5]    FALSE         Default -…
#> 5 Species      treatment keep     factor  n=3 levels    FALSE         detect_de…
propose_roles(iris, mode = "collaborate")
#> # A tibble: 5 × 7
#>   col          role      action   kind    freq_or_range pii_suspected notes     
#>   <chr>        <chr>     <chr>    <chr>   <chr>         <lgl>         <chr>     
#> 1 Sepal.Length covariate scramble numeric [4.3, 7.9]    FALSE         Default -…
#> 2 Sepal.Width  covariate scramble numeric [2, 4.4]      FALSE         Default -…
#> 3 Petal.Length covariate scramble numeric [1, 6.9]      FALSE         Default -…
#> 4 Petal.Width  covariate scramble numeric [0.1, 2.5]    FALSE         Default -…
#> 5 Species      treatment alias    factor  n=3 levels    FALSE         detect_de…

met <- expand.grid(
  env = factor(c("E1", "E2")),
  rep = factor(seq_len(2L)),
  gen = factor(c("G1", "G2", "G3"))
)
propose_roles(met, mode = "collaborate")[, c("col", "role", "action")]
#> # A tibble: 3 × 3
#>   col   role      action
#>   <chr> <chr>     <chr> 
#> 1 env   design    alias 
#> 2 rep   design    keep  
#> 3 gen   treatment alias 
```
