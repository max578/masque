# Extract the synthetic data from a masque object

Extract the synthetic data from a masque object

## Usage

``` r
synthetic(m)
```

## Arguments

- m:

  A `masque` object from
  [`mask()`](https://max578.github.io/masque/reference/mask.md), or a
  `masque_set` from
  [`mask_set()`](https://max578.github.io/masque/reference/mask_set.md).

## Value

For a `masque`, a tibble (the synthetic data frame); for a `masque_set`,
a named list of synthetic tables.

## See also

[`recipe()`](https://max578.github.io/masque/reference/recipe.md),
[`mask()`](https://max578.github.io/masque/reference/mask.md),
[`mask_set()`](https://max578.github.io/masque/reference/mask_set.md).

## Examples

``` r
r <- propose_roles(iris)
r$role[r$col == "Sepal.Length"] <- "outcome"
m <- suppressWarnings(mask(iris, r, seed = 1))
head(synthetic(m))
#> # A tibble: 6 × 5
#>   Sepal.Length Sepal.Width Petal.Length Petal.Width Species
#>          <dbl>       <dbl>        <dbl>       <dbl> <fct>  
#> 1          5.1         3.2          4           1.5 setosa 
#> 2          6           3            3.7         0.4 setosa 
#> 3          5           3            4.6         1.1 setosa 
#> 4          7.2         2.6          5.8         1.7 setosa 
#> 5          6.1         2.4          5.8         1.5 setosa 
#> 6          5           2.7          4.5         1.4 setosa 
```
