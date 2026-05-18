# Read a masque recipe from disk

Loads a recipe written by
[`save_recipe()`](https://max578.github.io/masque/reference/save_recipe.md).
Validates that the file contains a `masque_recipe` and informs (does not
error) if the recipe was written by a different package version than the
one currently installed.

## Usage

``` r
read_recipe(path)
```

## Arguments

- path:

  File path.

## Value

A `masque_recipe` object.

## See also

[`save_recipe()`](https://max578.github.io/masque/reference/save_recipe.md),
[`recipe()`](https://max578.github.io/masque/reference/recipe.md).
