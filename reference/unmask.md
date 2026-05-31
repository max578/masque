# Translate data from the synthetic namespace back to the original

Inverse of
[`apply_recipe()`](https://max578.github.io/masque/reference/apply_recipe.md).
Accepts a data frame or an atomic vector. For an atomic factor /
character vector with a recipe that holds multiple level maps, `column`
must name which map to invert. Atomic numeric, integer, logical, and
`Date` / `POSIXct` vectors are returned unchanged (no inverse map
applies — these are pass-through under
[`apply_recipe()`](https://max578.github.io/masque/reference/apply_recipe.md)
too).

## Usage

``` r
unmask(x, rec, column = NULL)
```

## Arguments

- x:

  A data frame or an atomic vector to translate from synthetic-namespace
  to original-namespace.

- rec:

  A `masque_recipe` object.

- column:

  Optional column name. Only consulted for atomic factor / character `x`
  when the recipe holds more than one level map. Ignored for atomic
  numeric / logical / Date-like input (pass-through), but if supplied is
  validated against the recipe's known columns.

## Value

An object of the same type as `x`, in the original namespace.

## Details

The most common pattern is round-tripping pipeline predictions:


    fit                 <- my_model(synthetic(m))            # train on synthetic
    orig_in_synth_space <- apply_recipe(original, recipe(m)) # forward
    preds_synth         <- predict(fit, orig_in_synth_space)
    preds_orig          <- unmask(preds_synth, recipe(m))    # inverse

Unknown levels (synthetic aliases not in the recipe's map) fail closed
with an informative error rather than silently coercing to `NA`.

## See also

[`apply_recipe()`](https://max578.github.io/masque/reference/apply_recipe.md),
[`mask()`](https://max578.github.io/masque/reference/mask.md).
