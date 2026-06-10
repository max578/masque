# Translate a data frame into the synthetic namespace

Forward translation: takes an `original`-namespace data frame and
returns it renamed and re-labelled to match the synthetic namespace
produced by
[`mask()`](https://max578.github.io/masque/reference/mask.md). Use this
to run a pipeline (trained on the synthetic) against the original data
without modifying pipeline code.

## Usage

``` r
apply_recipe(original, rec, check_integrity = TRUE)
```

## Arguments

- original:

  A data frame in the original namespace.

- rec:

  A `masque_recipe` object (e.g. from `recipe(m)`).

- check_integrity:

  Logical. When `TRUE` (default), verifies that the NA mask of
  `original` matches the recipe's recorded `integrity_fp`. Mismatches
  error with guidance. Pass `FALSE` to bypass when the missingness has
  legitimately changed since the recipe was built.

## Value

A tibble in the synthetic namespace, ready for the pipeline.

## Details

Operations applied (in order):

1.  **Verify integrity** by comparing the NA mask of `original` to the
    SHA-256 fingerprint stored on the recipe (controlled by
    `check_integrity`).

2.  **Drop** columns that
    [`mask()`](https://max578.github.io/masque/reference/mask.md)
    dropped (in `collaborate` mode this is every `ignore` column; in
    `local` mode no columns are dropped).

3.  **Subset and reorder** to the columns the recipe knows about.

4.  **Re-label factors / characters** for any column with a level map
    held by the recipe (i.e., treatment and categorical covariates in
    `collaborate` mode; or treatment in `local` mode with opt-in
    permutation). Unknown non-NA values fail closed.

5.  **Rename columns** per `recipe@column_name_map` when
    [`mask()`](https://max578.github.io/masque/reference/mask.md) was
    called with `alias_names` (otherwise `NULL`, and names are
    unchanged).

Numeric columns are passed through unchanged: the synthetic-namespace
for numeric columns is the same as the original. NA cells in the input
remain NA in the output (no synthesis is performed here).

## See also

[`unmask()`](https://max578.github.io/masque/reference/unmask.md),
[`mask()`](https://max578.github.io/masque/reference/mask.md).

## Examples

``` r
r <- propose_roles(iris)
r$role[r$col == "Sepal.Length"] <- "outcome"
r$role[r$col == "Species"] <- "covariate"
m <- mask(iris, r, mode = "collaborate", seed = 1)
#> Re-resolved default actions for mode "collaborate" (explicit edits always win):
#> • Species: keep -> alias
rec <- recipe(m)
iris_in_synth_space <- apply_recipe(iris, rec)
head(iris_in_synth_space)
#> # A tibble: 6 × 5
#>   Sepal.Length Sepal.Width Petal.Length Petal.Width Species     
#>          <dbl>       <dbl>        <dbl>       <dbl> <fct>       
#> 1          5.1         3.5          1.4         0.2 Species_L001
#> 2          4.9         3            1.4         0.2 Species_L001
#> 3          4.7         3.2          1.3         0.2 Species_L001
#> 4          4.6         3.1          1.5         0.2 Species_L001
#> 5          5           3.6          1.4         0.2 Species_L001
#> 6          5.4         3.9          1.7         0.4 Species_L001
```
