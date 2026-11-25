# The plan in clone vocabulary, for the analyst

The plan of a
[`mask()`](https://max578.github.io/masque/reference/mask.md) result, in
the names and labels of the clone. It carries the roles as
[`roles()`](https://max578.github.io/masque/reference/roles.md) gives
them, the linked events and each control spec as resolved on the source.
It holds no coordinate declaration, and nothing else from the recipe.
With
[`controls()`](https://max578.github.io/masque/reference/controls.md) it
gives the analyst the pre-declared controls on the clone.

## Usage

``` r
clone_plan(m)
```

## Arguments

- m:

  A `masque` object from
  [`mask()`](https://max578.github.io/masque/reference/mask.md). A clone
  masked without a plan gives a plan with no control specs.

## Value

A `masque_plan` in clone vocabulary.

## See also

[`masque_plan()`](https://max578.github.io/masque/reference/masque_plan.md),
[`controls()`](https://max578.github.io/masque/reference/controls.md),
[`handover()`](https://max578.github.io/masque/reference/handover.md).

## Examples

``` r
r <- propose_roles(iris, mode = "local", detect = FALSE)
clone_plan(mask(iris, r, seed = 1L))
#> 
#> ── masque_plan (clone vocabulary) ──────────────────────────────────────────────
#> • Roles: 5 covariate
#> • Conditional: FALSE
#> • Ladder: hierarchy; grain: TRUE
#> • Column names aliased: FALSE
#> • Coordinate pairs: 0
#> • Linked-event specs: 0
#> • Control specs: 0
```
