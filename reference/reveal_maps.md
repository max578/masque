# Reveal the level maps held inside a recipe

Explicit, audited reveal: prints each `original -> synthetic` level map
held by the recipe. **Use sparingly.** Recipe maps are at least as
sensitive as the original data; printing them defeats the redaction
built into [`print()`](https://rdrr.io/r/base/print.html) and
[`summary()`](https://rdrr.io/r/base/summary.html).

## Usage

``` r
reveal_maps(rec)
```

## Arguments

- rec:

  A `masque_recipe` object (e.g., from `recipe(m)`).

## Value

`rec`, invisibly.

## Examples

``` r
r <- propose_roles(iris)
r$role[r$col == "Sepal.Length"] <- "outcome"
r$role[r$col == "Species"] <- "covariate"
m <- suppressWarnings(mask(iris, r, mode = "collaborate", seed = 1))
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
