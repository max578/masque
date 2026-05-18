# Mask a tabular dataset into a structurally faithful development surrogate

Takes one data frame and a user-edited `roles` tibble (from
[`propose_roles()`](https://max578.github.io/masque/reference/propose_roles.md))
and produces a synthetic clone whose experimental design and NA pattern
are preserved, while outcome and numeric-covariate values are
re-simulated via a Gaussian copula and categorical-covariate values are
row-permuted. Returns a `masque` S7 object holding the synthetic data
and a private `masque_recipe`.

## Usage

``` r
mask(df, roles, mode = c("local", "collaborate"), seed = NULL, ...)
```

## Arguments

- df:

  A data frame.

- roles:

  A tibble produced by
  [`propose_roles()`](https://max578.github.io/masque/reference/propose_roles.md)
  (possibly edited). May optionally include a `mask_levels` column
  (`"permute"` enables local-mode seeded permutation on the treatment
  column).

- mode:

  Either `"local"` (default) or `"collaborate"`.

- seed:

  Optional integer for reproducibility.

- ...:

  Currently ignored.

## Value

A `masque` S7 object. Use
[`synthetic()`](https://max578.github.io/masque/reference/synthetic.md)
and [`recipe()`](https://max578.github.io/masque/reference/recipe.md) to
extract the components.

## Details

`mode = "local"` keeps original column / level vocabularies and warns
that the synthetic is for owner development only. `mode = "collaborate"`
opaque-aliases treatment and categorical-covariate level vocabularies
(`trt_001`, `<col>_L01`) and drops `ignore` columns; the resulting
synthetic can be passed to a collaborator while the recipe stays
private. In `collaborate` mode, numeric draws are jittered within their
measurement resolution, integer columns are stochastically rounded, and
[`audit_mask()`](https://max578.github.io/masque/reference/audit_mask.md)
runs automatically.

## Behaviour by role

- `design`:

  Byte-identical pass-through.

- `treatment`:

  Local: pass-through (optional opt-in seeded permutation via
  `roles$mask_levels = "permute"`). Collaborate: opaque alias `trt_NNN`.

- `outcome` + numeric `covariate`:

  Re-simulated jointly via a Gaussian copula on global Pearson
  covariance. Empirical-quantile marginals (type 1: returns observed
  values).

- categorical `covariate`:

  Row-permuted within non-NA positions. Local: vocabulary preserved.
  Collaborate: opaque alias `<col>_LNN`.

- `ignore`:

  Local: passes through. Collaborate: dropped.

RNG state is preserved across the call.

## See also

[`propose_roles()`](https://max578.github.io/masque/reference/propose_roles.md),
[`roles_validate()`](https://max578.github.io/masque/reference/roles_validate.md),
[`synthetic()`](https://max578.github.io/masque/reference/synthetic.md),
[`recipe()`](https://max578.github.io/masque/reference/recipe.md),
[`reveal_maps()`](https://max578.github.io/masque/reference/reveal_maps.md).

## Examples

``` r
r <- propose_roles(iris)
r$role[r$col == "Sepal.Length"] <- "outcome"
m <- suppressWarnings(mask(iris, r, seed = 1))
head(synthetic(m))
#> # A tibble: 6 × 5
#>   Sepal.Length Sepal.Width Petal.Length Petal.Width Species
#>          <dbl>       <dbl>        <dbl>       <dbl> <fct>  
#> 1          5.1         3            1.5         1.2 setosa 
#> 2          6.2         3            4.7         1.2 setosa 
#> 3          4.8         3.4          1.6         1.2 setosa 
#> 4          7.2         3.2          6.4         2.1 setosa 
#> 5          5.8         3.7          5.1         1.8 setosa 
#> 6          5           3.7          1.5         1.2 setosa 
```
