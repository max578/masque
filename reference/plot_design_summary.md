# Sanity-check visualisation for detected scope and design

Plots the structure that drove the
[`detect_design()`](https://max578.github.io/masque/reference/detect_design.md)
verdict. A detected MET uses a compact environment-coverage overview by
default. Set `environment` to draw one selected environment. A
single-trial panel depends on the detected design class:

## Usage

``` r
plot_design_summary(
  x,
  df,
  engine = c("base", "ggplot2"),
  environment = NULL,
  ...
)
```

## Arguments

- x:

  A `design_summary` object from
  [`detect_design()`](https://max578.github.io/masque/reference/detect_design.md).

- df:

  The data frame that was passed to
  [`detect_design()`](https://max578.github.io/masque/reference/detect_design.md).
  It is used to draw replication tiles, spatial layouts, and the
  NA-pattern. The data are deliberately not stored in the summary.

- engine:

  `"base"` (default) or `"ggplot2"`. The latter requires ggplot2 and
  falls back to `"base"` with a warning if unavailable.

- environment:

  Optional single environment label. For a detected MET, the default is
  a compact all-environment overview. Supplying a label draws the
  selected environment's field layout or legacy design diagnostic.

- ...:

  Ignored.

## Value

The input `x`, invisibly. Called for the plot side-effect.

## Details

- `CRD`, `factorial`, `none` -\> frequency-of-treatment + NA-pattern.

- `RCBD`, `IBD/alpha-lattice` -\> treatment x block replication tile.

- `row-column` -\> spatial layout tile (row x col, fill = treatment).

- `split-plot` -\> factor-nesting tree + within-block replication.

Output is purely diagnostic. Do not use it as a publication figure (use
`desplot::desplot()` or `ggplot2`-based packages for that).

## Examples

``` r
if (requireNamespace("agridat", quietly = TRUE)) {
  d <- agridat::john.alpha
  ds <- detect_design(d)
  plot(ds, df = d)
}


met <- expand.grid(
  env = factor(c("E1", "E2")),
  rep = factor(seq_len(2L)),
  gen = factor(c("G1", "G2", "G3"))
)
met$yield <- seq_len(nrow(met))
met_design <- detect_design(met, env = "env")
plot(met_design, df = met)

```
