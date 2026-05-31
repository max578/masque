# Extract the recipe from a masque object

The recipe is **private**: at least as sensitive as the original data.
Never share alongside the synthetic. By default `print(recipe(m))`
redacts all level maps; use
[`reveal_maps()`](https://max578.github.io/masque/reference/reveal_maps.md)
for an explicit reveal.

## Usage

``` r
recipe(m)
```

## Arguments

- m:

  A `masque` object returned by
  [`mask()`](https://max578.github.io/masque/reference/mask.md).

## Value

A `masque_recipe` S7 object.

## See also

[`synthetic()`](https://max578.github.io/masque/reference/synthetic.md),
[`reveal_maps()`](https://max578.github.io/masque/reference/reveal_maps.md),
[`mask()`](https://max578.github.io/masque/reference/mask.md).

## Examples

``` r
r <- propose_roles(iris)
r$role[r$col == "Sepal.Length"] <- "outcome"
m <- suppressWarnings(mask(iris, r, seed = 1))
recipe(m)
#> 
#> ── masque_recipe ───────────────────────────────────────────────────────────────
#> • Created: 2026-05-31 11:07:23 UTC
#> • Mode: local
#> • Seed: present (redacted)
#> • masque version: 0.4.1
#> • Integrity fingerprint: 62a4affb7e41...
#> 
#> ── Columns (5 total; 0 level-map(s); 0 column-name map(s)) ──
#> 
#>   = outcome    Sepal.Length                      (numeric)
#>   = covariate  Sepal.Width                       (numeric)
#>   = covariate  Petal.Length                      (numeric)
#>   = covariate  Petal.Width                       (numeric)
#>   = treatment  Species                           (factor)
#> ── Warnings ──
#> 
#> ! local mode: synthetic data is for owner development only, not external sharing.
#> 
#> ✖ PRIVATE - never share this recipe alongside the synthetic.
#> Use `reveal_maps(rec)` to inspect level maps explicitly.
```
