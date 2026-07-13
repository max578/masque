# Save a masque recipe to disk

Writes the recipe to a single `.rds` file. The default is
**runtime-minimal**: no simulator state (copula covariance, raw margins)
is written, only the translation maps, factor metadata, storage classes,
integrity fingerprint, and warnings. This keeps the saved artefact small
and reduces the information that would leak if the recipe file alone
were shared.

## Usage

``` r
save_recipe(rec, path, include_simulator = FALSE)
```

## Arguments

- rec:

  A `masque_recipe` object, e.g. from `recipe(m)`.

- path:

  File path. By convention, `.rds` extension.

- include_simulator:

  Logical. Reserved for a future release. Currently a no-op (recipe is
  always written runtime-minimal).

## Value

`path`, invisibly.

## Details

`include_simulator = TRUE` is accepted but is currently a no-op: the
recipe does not carry simulator state. The flag is reserved for a future
release that will let
[`read_recipe()`](https://max578.github.io/masque/reference/read_recipe.md)
regenerate fresh synthetic samples without access to the original data.

Recipes are at least as sensitive as the original data. Protect the
saved file at the same security class as the original. Note that
`save_recipe()` writes plain R serialisation - it does not encrypt. The
saved recipe is a re-identification key: store it under your
organisation's access controls and key-management practice, not
alongside the synthetic output.

## See also

[`read_recipe()`](https://max578.github.io/masque/reference/read_recipe.md),
[`recipe()`](https://max578.github.io/masque/reference/recipe.md).

## Examples

``` r
r <- propose_roles(iris)
r$role[r$col == "Sepal.Length"] <- "outcome"
m <- mask(iris, r, mode = "collaborate", seed = 1)
#> Re-resolved default actions for mode "collaborate" (explicit edits always win):
#> • Species: keep -> alias
tmp <- tempfile(fileext = ".rds")
save_recipe(recipe(m), tmp)
rec2 <- read_recipe(tmp)
```
