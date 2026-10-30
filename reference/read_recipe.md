# Read a masque recipe from disk

Loads a recipe written by
[`save_recipe()`](https://max578.github.io/masque/reference/save_recipe.md).
Validates that the file contains a `masque_recipe` or a
`masque_recipe_set` bundle and informs (does not error) if it was
written by a different package version than the one currently installed.
Bundles are read from masque 0.16.0 on.

## Usage

``` r
read_recipe(path)
```

## Arguments

- path:

  File path.

## Value

A `masque_recipe`, or a `masque_recipe_set` bundle.

## See also

[`save_recipe()`](https://max578.github.io/masque/reference/save_recipe.md),
[`recipe()`](https://max578.github.io/masque/reference/recipe.md).

## Examples

``` r
r <- propose_roles(iris)
r$role[r$col == "Sepal.Length"] <- "outcome"
m <- mask(iris, r, mode = "collaborate", seed = 1)
#> Re-resolved default actions for mode "collaborate" (explicit edits always win):
#> • Species: scramble -> alias
tmp <- tempfile(fileext = ".rds")
save_recipe(recipe(m), tmp)
rec2 <- read_recipe(tmp)
rec2
#> 
#> ── masque_recipe ───────────────────────────────────────────────────────────────
#> • Created: 2026-10-30 23:38:11 UTC
#> • Mode: collaborate
#> • Clone fidelity: marginal / structural (global copula)
#> • Seed: present (redacted)
#> • masque version: 0.16.0
#> • Integrity fingerprint: 62a4affb7e41...
#> 
#> ── Columns (5 total; 1 level map; 0 column-name maps) ──
#> 
#>   = outcome   scramble  Sepal.Length                  (numeric)
#>   = covariate scramble  Sepal.Width                   (numeric)
#>   = covariate scramble  Petal.Length                  (numeric)
#>   = covariate scramble  Petal.Width                   (numeric)
#>   * covariate alias     Species                       (factor)
#> 
#> ✖ PRIVATE - never share this recipe alongside the synthetic.
#> Use `reveal_maps(rec)` to inspect level maps explicitly.
```
