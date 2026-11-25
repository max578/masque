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

For a `masque`, a data.table (the synthetic table); for a `masque_set`,
a named list of synthetic tables.

## See also

[`recipe()`](https://max578.github.io/masque/reference/recipe.md),
[`mask()`](https://max578.github.io/masque/reference/mask.md),
[`mask_set()`](https://max578.github.io/masque/reference/mask_set.md).

## Examples

``` r
r <- propose_roles(iris)
r$role[r$col == "Sepal.Length"] <- "outcome"
m <- mask(iris, r, seed = 1)
head(synthetic(m))
#>    Sepal.Length Sepal.Width Petal.Length Petal.Width      Species
#>           <num>       <num>        <num>       <num>       <fctr>
#> 1:     5.959447    2.644060     4.539749   0.1717018 Species_L002
#> 2:     5.078844    3.419512     4.415627   0.3068617 Species_L003
#> 3:     5.483718    3.028314     4.020137   2.4938487 Species_L003
#> 4:     4.655556    3.457193     1.166039   0.2856854 Species_L002
#> 5:     7.314096    3.000000     3.249417   1.6197431 Species_L001
#> 6:     6.716410    2.600369     4.376526   2.2166632 Species_L003
```
