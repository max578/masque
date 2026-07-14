# List every role and action combination masque accepts

Renders the two-axis vocabulary as a table: every `role` paired with
every `action`, the storage kinds the pair works for, and the reason the
pair is constrained when it is. The table is generated from the same
compatibility rules
[`roles_validate()`](https://max578.github.io/masque/reference/roles_validate.md)
applies at [`mask()`](https://max578.github.io/masque/reference/mask.md)
time, so what it shows is exactly what a roles table is allowed to say.

## Usage

``` r
role_options(kind = NULL)
```

## Arguments

- kind:

  Optional storage kind to filter for: one of `"numeric"`, `"integer"`,
  `"factor"`, `"character"`, `"logical"`, `"date"`, `"datetime"`, or
  `"other"`. When supplied, only the combinations workable for a column
  of that kind are returned. The default `NULL` returns the full grid.

## Value

A tibble with one row per role-action pair and four columns: `role`,
`action`, `kinds` (the storage kinds the pair is valid for: `"all"`,
`"none"`, `"all except other"`, or a comma-separated list), and `notes`
(why the pair is constrained, empty when it is not).

## Details

A column's `kind` is never chosen:
[`propose_roles()`](https://max578.github.io/masque/reference/propose_roles.md)
derives it from the column's class. To move a column to a different
kind, convert the column in the data and re-propose.

## See also

[`propose_roles()`](https://max578.github.io/masque/reference/propose_roles.md),
[`set_role()`](https://max578.github.io/masque/reference/set_role.md),
[`roles_validate()`](https://max578.github.io/masque/reference/roles_validate.md).

## Examples

``` r
role_options()
#> # A tibble: 32 × 4
#>    role      action   kinds                      notes                          
#>    <chr>     <chr>    <chr>                      <chr>                          
#>  1 design    keep     all                        ""                             
#>  2 design    scramble none                       "design columns are structure,…
#>  3 design    alias    factor, character, logical "design label aliasing require…
#>  4 design    drop     all                        ""                             
#>  5 treatment keep     all                        ""                             
#>  6 treatment scramble factor, character, logical "treatment scramble / alias re…
#>  7 treatment alias    factor, character, logical "treatment scramble / alias re…
#>  8 treatment drop     all                        ""                             
#>  9 outcome   keep     all                        ""                             
#> 10 outcome   scramble numeric, integer           "only numeric / integer outcom…
#> # ℹ 22 more rows
role_options(kind = "factor")
#> # A tibble: 24 × 4
#>    role      action   kinds                      notes                          
#>    <chr>     <chr>    <chr>                      <chr>                          
#>  1 design    keep     all                        ""                             
#>  2 design    alias    factor, character, logical "design label aliasing require…
#>  3 design    drop     all                        ""                             
#>  4 treatment keep     all                        ""                             
#>  5 treatment scramble factor, character, logical "treatment scramble / alias re…
#>  6 treatment alias    factor, character, logical "treatment scramble / alias re…
#>  7 treatment drop     all                        ""                             
#>  8 outcome   keep     all                        ""                             
#>  9 outcome   drop     all                        ""                             
#> 10 covariate keep     all                        ""                             
#> # ℹ 14 more rows
subset(role_options(), role == "design")
#> # A tibble: 4 × 4
#>   role   action   kinds                      notes                              
#>   <chr>  <chr>    <chr>                      <chr>                              
#> 1 design keep     all                        ""                                 
#> 2 design scramble none                       "design columns are structure, not…
#> 3 design alias    factor, character, logical "design label aliasing requires a …
#> 4 design drop     all                        ""                                 
```
