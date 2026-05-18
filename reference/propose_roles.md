# Propose role classifications for the columns of a data frame

Generates a heuristic role tibble for every column of `df`. The user is
expected to inspect this tibble and edit it before passing it to
[`mask()`](https://max578.github.io/masque/reference/mask.md).
Heuristics are seeds, not law.

## Usage

``` r
propose_roles(df, detect = TRUE)
```

## Arguments

- df:

  A data frame. Must have at least one column.

- detect:

  Logical scalar (default `TRUE`). When `TRUE`, run
  [`detect_design()`](https://max578.github.io/masque/reference/detect_design.md)
  and overlay its recommended role hints on the name-based heuristic.
  Stash the `design_summary` as `attr(roles, "design")`. When `FALSE`,
  only the v0.2.x name-based heuristic runs.

## Value

A tibble with one row per column, containing:

- `col`: column name.

- `role`: one of `design`, `treatment`, `outcome`, `covariate`,
  `ignore`.

- `kind`: storage kind (`numeric`, `integer`, `factor`, `character`,
  `logical`, `date`, `datetime`, `other`).

- `freq_or_range`: brief summary string (range for numeric, level count
  for factor, etc.).

- `pii_suspected`: `TRUE` if column name matches a PII pattern.

- `notes`: short explanation of the auto-classification.

## Details

Roles are exactly one of:

- `design`:

  Byte-identical pass-through. Trial / site / replicate / block / plot /
  row / column / year etc.

- `treatment`:

  Same factor cardinality and per-level frequency; optional label
  aliasing or seeded permutation.

- `outcome`:

  Re-simulated via Gaussian copula. Multiple allowed.

- `covariate`:

  Numeric: Gaussian copula (joint with outcomes). Categorical:
  row-permuted, levels preserved (local) or aliased (collaborate).

- `ignore`:

  Dropped or passed through depending on
  [`mask()`](https://max578.github.io/masque/reference/mask.md) options;
  auto-assigned for date/time, free text, and PII-pattern names.

Default classification rules, applied in order:

1.  PII-pattern column names (`contact`, `email`, `phone`, `gps`,
    `latitude`/`longitude`, `postcode`, `ssn`, `password`, `owner`,
    `farmer`, `operator`, etc., case-insensitive substring) -\> `ignore`
    with `pii_suspected = TRUE`.

2.  Date / POSIXct / POSIXlt / difftime columns -\> `ignore`.

3.  ID-pattern names (`\\bid\\b`, `_id$`, `^id_`) -\> `ignore`.

4.  Design-pattern names (`rep`, `block`, `row`, `col(umn)?`, `range`,
    `plot(no)?`, `site`, `env(ironment)?`, `trial`, `year`, `season`,
    `colrep`, `tos`) -\> `design`.

5.  Treatment-pattern names (`treatment`, `variety`, `cultivar`,
    `genotype`, `^trt`, `^dose`) -\> `treatment`.

6.  Character columns with \> 50% unique values on non-NA -\> `ignore`
    (likely free text).

7.  Everything else -\> `covariate`. The user re-classifies one or more
    columns as `outcome`.

Failing to designate at least one `outcome` is a hard error at
[`mask()`](https://max578.github.io/masque/reference/mask.md) time (via
[`roles_validate()`](https://max578.github.io/masque/reference/roles_validate.md)).

Since masque 0.3.0, `propose_roles()` also calls
[`detect_design()`](https://max578.github.io/masque/reference/detect_design.md)
by default (`detect = TRUE`) and applies the detected design's
`recommended_roles` on top of the name-based heuristic. This promotes
structurally-identified block / treatment columns even when the column
names do not match the design / treatment regexes. The resulting design
summary is stashed as `attr(roles, "design")` so the user can
[`plot()`](https://rdrr.io/r/graphics/plot.default.html) it or inspect
alternates. Pass `detect = FALSE` to recover the v0.2.x name-only
behaviour byte-for-byte.

## See also

[`roles_validate()`](https://max578.github.io/masque/reference/roles_validate.md)
for the fail-closed validation applied at
[`mask()`](https://max578.github.io/masque/reference/mask.md) time.

## Examples

``` r
propose_roles(iris)
#> # A tibble: 5 × 6
#>   col          role      kind    freq_or_range pii_suspected notes              
#>   <chr>        <chr>     <chr>   <chr>         <lgl>         <chr>              
#> 1 Sepal.Length covariate numeric [4.3, 7.9]    FALSE         Default -> covaria…
#> 2 Sepal.Width  covariate numeric [2, 4.4]      FALSE         Default -> covaria…
#> 3 Petal.Length covariate numeric [1, 6.9]      FALSE         Default -> covaria…
#> 4 Petal.Width  covariate numeric [0.1, 2.5]    FALSE         Default -> covaria…
#> 5 Species      treatment factor  n=3 levels    FALSE         detect_design: cov…
```
