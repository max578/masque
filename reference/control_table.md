# Produce one control dataset

Regenerates a control dataset of a
[`controls()`](https://max578.github.io/masque/reference/controls.md)
object from its seed: the null, or negative or positive replicate `i`.
Positive replicate `i` is negative replicate `i` plus the planted shift.
The result carries a `masque_control` attribute naming its kind and
replicate; its values alone do not tell it from the table it came from,
so keep the manifest with it.

## Usage

``` r
control_table(ctl, kind = c("null", "negative", "positive"), i = 1L)
```

## Arguments

- ctl:

  A `masque_controls` object from
  [`controls()`](https://max578.github.io/masque/reference/controls.md).

- kind:

  One of `"null"`, `"negative"`, `"positive"`.

- i:

  The replicate, from 1 to `n` of the spec; ignored for the null.

## Value

A data.table with the columns, classes, NA mask and row order of the
input table.

## See also

[`controls()`](https://max578.github.io/masque/reference/controls.md),
[`control_spec()`](https://max578.github.io/masque/reference/control_spec.md).

## Examples

``` r
trial <- read.csv(system.file("extdata", "john_alpha.csv", package = "masque"))
r <- propose_roles(trial, detect = FALSE)
r <- set_role(r, c("rep", "block"), role = "design", action = "keep")
r <- set_role(r, "gen", role = "treatment", action = "keep")
r <- set_role(r, "yield", role = "outcome", action = "scramble")
r <- set_role(r, c("plot", "row", "col"), role = "id", action = "keep")
spec <- control_spec(on = "gen", strata = "rep", n = 3L, seed = 1L)
ctl <- controls(trial, r, spec)
neg <- control_table(ctl, "negative", 2L)
table(neg$block, neg$gen)[1:2, 1:6]
#>     
#>      G01 G02 G03 G04 G05 G06
#>   B1   0   0   0   0   2   0
#>   B2   1   0   0   1   0   1
```
