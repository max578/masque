# The role table of a masked clone

Returns the role each column of the clone was masked under, in the
clone's own vocabulary: one row per column of
[`synthetic()`](https://max578.github.io/masque/reference/synthetic.md),
in the same order and under the same names. When the column names were
aliased (`alias_names` in
[`mask()`](https://max578.github.io/masque/reference/mask.md)), the rows
carry the aliases, so the table can travel with the clone without
disclosing the original names. A dropped column is not in the clone and
has no row.

## Usage

``` r
roles(m)
```

## Arguments

- m:

  A `masque` object from
  [`mask()`](https://max578.github.io/masque/reference/mask.md), or a
  `masque_set` from
  [`mask_set()`](https://max578.github.io/masque/reference/mask_set.md).

## Value

For a `masque`, a data.table with columns `col`, `role`, `action` and
`kind`. For a `masque_set`, a named list of such tables, one per table
of the set.

## Details

Only the four public columns are returned. The proposal's notes and its
value summaries describe the original table and stay on the private
recipe, as does the full role table used on the original
(`recipe(m)@roles`).

## See also

[`synthetic()`](https://max578.github.io/masque/reference/synthetic.md),
[`data_card()`](https://max578.github.io/masque/reference/data_card.md),
[`mask()`](https://max578.github.io/masque/reference/mask.md).

## Examples

``` r
r <- propose_roles(iris)
r <- set_role(r, "Sepal.Length", role = "outcome")
m <- mask(iris, r, seed = 1)
roles(m)
#>             col      role   action    kind
#>          <char>    <char>   <char>  <char>
#> 1: Sepal.Length   outcome scramble numeric
#> 2:  Sepal.Width covariate scramble numeric
#> 3: Petal.Length covariate scramble numeric
#> 4:  Petal.Width covariate scramble numeric
#> 5:      Species covariate scramble  factor
```
