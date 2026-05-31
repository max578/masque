# Extract the synthetic data from a masque object

Extract the synthetic data from a masque object

## Usage

``` r
synthetic(m)
```

## Arguments

- m:

  A `masque` object returned by
  [`mask()`](https://max578.github.io/masque/reference/mask.md).

## Value

A tibble: the synthetic data frame.

## See also

[`recipe()`](https://max578.github.io/masque/reference/recipe.md),
[`mask()`](https://max578.github.io/masque/reference/mask.md).

## Examples

``` r
r <- propose_roles(iris)
r$role[r$col == "Sepal.Length"] <- "outcome"
m <- suppressWarnings(mask(iris, r, seed = 1))
head(synthetic(m))
#> # A tibble: 6 × 5
#>   Sepal.Length Sepal.Width Petal.Length Petal.Width Species
#>          <dbl>       <dbl>        <dbl>       <dbl> <fct>  
#> 1          5.5         3            1.5         0.2 setosa 
#> 2          5.6         3            4.7         1.6 setosa 
#> 3          5.6         3.2          1.6         0.2 setosa 
#> 4          6.9         3.2          6.4         2.3 setosa 
#> 5          6.7         3.6          5.1         1   setosa 
#> 6          5.7         3.6          1.5         0.2 setosa 
```
