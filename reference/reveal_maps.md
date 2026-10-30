# Reveal the level maps held inside a recipe

Explicit, audited reveal: prints each `original -> synthetic` level map
held by the recipe. **Use sparingly.** Recipe maps are at least as
sensitive as the original data; printing them defeats the redaction
built into the [`print()`](https://rdrr.io/r/base/print.html),
[`format()`](https://rdrr.io/r/base/format.html),
[`str()`](https://rdrr.io/r/utils/str.html) and
[`knitr::knit_print()`](https://rdrr.io/pkg/knitr/man/knit_print.html)
methods of recipes, recipe bundles, `masque` and `masque_set` objects.
[`saveRDS()`](https://rdrr.io/r/base/readRDS.html) and
[`dput()`](https://rdrr.io/r/base/dput.html) write the maps by design.

## Usage

``` r
reveal_maps(rec, table = NULL)
```

## Arguments

- rec:

  A `masque_recipe` object (e.g., from `recipe(m)`), or the
  `masque_recipe_set` bundle of a
  [`mask_set()`](https://max578.github.io/masque/reference/mask_set.md)
  result.

- table:

  For a bundle, the names of the tables whose maps to reveal. `NULL`
  (default) reveals every table. Must be `NULL` for a single recipe.

## Value

`rec`, invisibly.

## Details

For each recipe it prints the column-name map (when names were aliased),
every level map as `original -> alias`, and the seed. The alias labels
follow the scheme described under `alias` in
[`mask()`](https://max578.github.io/masque/reference/mask.md): `trt_NNN`
or `<col>_trt_NNN` for treatments, `<col>_LNNN`, `<col>_DNNN`,
`<col>_INNN` and `<col>_TNNN` for covariates, design columns, ids and
text, and `<col>_KNNN` for a key shared across the tables of a set.

## Examples

``` r
r <- propose_roles(iris)
r$role[r$col == "Sepal.Length"] <- "outcome"
r$role[r$col == "Species"] <- "covariate"
m <- mask(iris, r, mode = "collaborate", seed = 1)
#> Re-resolved default actions for mode "collaborate" (explicit edits always win):
#> • Species: scramble -> alias
rec <- recipe(m)
reveal_maps(rec)
#> ! Revealing sensitive level maps. Proceed at your discretion.
#> 
#> 
#> ── Species 
#>   setosa  ->  Species_L001
#>   versicolor  ->  Species_L002
#>   virginica  ->  Species_L003
#> 
#> ── seed 
#>   1
```
