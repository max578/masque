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
#> 1          5.1         3            1.5         1.2 setosa 
#> 2          6.2         3            4.7         1.2 setosa 
#> 3          4.8         3.4          1.6         1.2 setosa 
#> 4          7.2         3.2          6.4         2.1 setosa 
#> 5          5.8         3.7          5.1         1.8 setosa 
#> 6          5           3.7          1.5         1.2 setosa 
```
