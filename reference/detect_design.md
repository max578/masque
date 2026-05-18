# Detect the experimental-design structure of a data frame

Inspects `df` and returns an S7 `design_summary` describing the most
likely experimental design — one of `"CRD"`, `"RCBD"`,
`"IBD/alpha-lattice"`, `"row-column"`, `"split-plot"`, `"factorial"`, or
`"none"` (observational / no detectable design).

## Usage

``` r
detect_design(
  df,
  roles = NULL,
  interactive = FALSE,
  threshold = 0.5,
  tie_delta = 0.02
)
```

## Arguments

- df:

  A data frame.

- roles:

  Optional roles tibble (as returned by
  [`propose_roles()`](https://max578.github.io/masque/reference/propose_roles.md)).
  When supplied, columns roled `outcome` / `ignore` are excluded from
  factor candidates, and any column roled `treatment` is forced as the
  working treatment.

- interactive:

  If `TRUE`, when the top-2 rule scores are within `tie_delta` the user
  is asked to choose between them via a cli menu. Default `FALSE`.

- threshold:

  Minimum top-rule score for a class to be reported. Below this,
  `class_label` is `"none"`. Default `0.5`.

- tie_delta:

  Score difference within which two rules are treated as tied. Default
  `0.02` — tight enough that 0.05-point score differences (the typical
  name-bonus / coverage gap) are decisive.

## Value

An S7 `design_summary` object with slots `class_label`, `treatment_col`,
`block_cols`, `whole_plot_col`, `sub_plot_col`, `spatial_cols`,
`scores`, `evidence`, `recommended_roles`, `candidates`, `warnings`.

## Details

Detection runs six independent rules; each returns a score in \\\[0,
1\]\\. The orchestrator picks the highest-scoring class above
`threshold`. Ties within `tie_delta` are broken in favour of the simpler
design (CRD \< RCBD \< factorial \< IBD \< row-column \< split-plot).

The detector never edits `df`. Its job is to recommend a role
assignment, surface the evidence, and (optionally) draw a sanity check
via [`plot()`](https://rdrr.io/r/graphics/plot.default.html).

## See also

[`propose_roles()`](https://max578.github.io/masque/reference/propose_roles.md)
for the role tibble that feeds detection;
[`plot_design_summary()`](https://max578.github.io/masque/reference/plot_design_summary.md)
for the sanity-check visualisation.

## Examples

``` r
# Classic alpha-lattice (24 genotypes, 3 reps, 6 blocks per rep).
if (requireNamespace("agridat", quietly = TRUE)) {
  d  <- agridat::john.alpha
  ds <- detect_design(d)
  print(ds)
}
#> ── design_summary  <IBD/alpha-lattice> ─────────────────────────────────────────
#> • Treatment: gen
#> • Blocks: rep : block
#> ── Alternates (top rule scores) ────────────────────────────────────────────────
#> x <IBD/alpha-lattice > score = 1.00
#> <RCBD > score = 0.95
#> <CRD > score = 0.40
#> ── Recommended role hints ──────────────────────────────────────────────────────
#> = gen -> treatment
#> = rep -> design
#> = block -> design
#> ℹ Use `plot(x)` for a sanity-check visualisation; pass to `propose_roles(df, detect = TRUE)` to seed role hints.

# Observational data frame -> class_label "none".
detect_design(mtcars)
#> ── design_summary  <none> ──────────────────────────────────────────────────────
#> ℹ No experimental design detected above threshold.
#> • Top rule scores all below 0.5. Treat as observational.
#> ── Alternates (top rule scores) ────────────────────────────────────────────────
#> <factorial > score = 0.46
#> <IBD/alpha-lattice > score = 0.30
#> <CRD > score = 0.00
#> ℹ Use `plot(x)` for a sanity-check visualisation; pass to `propose_roles(df, detect = TRUE)` to seed role hints.
```
