# Save and read a masking plan as YAML

A plan on disk can be read and compared as text. `save_plan()` needs the
`yaml` package. A custom `on_land` function cannot be written, and is
refused. A source-vocabulary plan names real columns and labels, so it
stays with the owner. The analyst's file comes from
[`clone_plan()`](https://max578.github.io/masque/reference/clone_plan.md)
or
[`handover()`](https://max578.github.io/masque/reference/handover.md).

## Usage

``` r
save_plan(plan, path)

read_plan(path)
```

## Arguments

- plan:

  A
  [`masque_plan()`](https://max578.github.io/masque/reference/masque_plan.md).

- path:

  Path of a `.yaml` or `.yml` file.

## Value

`save_plan()` returns `path` invisibly; `read_plan()` a `masque_plan`.

## Examples

``` r
if (requireNamespace("yaml", quietly = TRUE)) {
  r <- propose_roles(iris, detect = FALSE)
  f <- tempfile(fileext = ".yaml")
  save_plan(masque_plan(r), f)
  read_plan(f)
}
#> 
#> ── masque_plan (source vocabulary) ─────────────────────────────────────────────
#> • Roles: 5 covariate
#> • Conditional: FALSE
#> • Ladder: hierarchy; grain: TRUE
#> • Column names aliased: FALSE
#> • Coordinate pairs: 0
#> • Linked-event specs: 0
#> • Control specs: 0
```
