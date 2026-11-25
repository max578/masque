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

  A `masque` object from
  [`mask()`](https://max578.github.io/masque/reference/mask.md), or a
  `masque_set` from
  [`mask_set()`](https://max578.github.io/masque/reference/mask_set.md).

## Value

A `masque_recipe`, or for a set a `masque_recipe_set` bundle.

## See also

[`synthetic()`](https://max578.github.io/masque/reference/synthetic.md),
[`reveal_maps()`](https://max578.github.io/masque/reference/reveal_maps.md),
[`mask()`](https://max578.github.io/masque/reference/mask.md),
[`mask_set()`](https://max578.github.io/masque/reference/mask_set.md).

## Examples

``` r
r <- propose_roles(iris)
r$role[r$col == "Sepal.Length"] <- "outcome"
m <- mask(iris, r, seed = 1)
recipe(m)
#> 
#> ── masque_recipe ───────────────────────────────────────────────────────────────
#> • Created: 2026-11-25 05:55:25 UTC
#> • Mode: null
#> • Clone fidelity: null (independent draws; design and missing-value pattern
#>   exact)
#> • Seed: present (redacted)
#> • masque version: 0.18.0
#> • Integrity fingerprint: 62a4affb7e41...
#> 
#> ── Columns (5 total; 1 level map; 0 column-name maps) ──
#> 
#>   = outcome   noise     Sepal.Length                  (numeric)
#>   = covariate noise     Sepal.Width                   (numeric)
#>   = covariate noise     Petal.Length                  (numeric)
#>   = covariate noise     Petal.Width                   (numeric)
#>   * covariate noise     Species                       (factor)
#> 
#> ✖ PRIVATE - never share this recipe alongside the synthetic.
#> Use `reveal_maps(rec)` to inspect level maps explicitly.
```
