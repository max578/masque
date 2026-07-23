# Detect environment scope and experimental-design structure

Inspects `df` and returns an S7 `design_summary`. Environment scope and
experimental-design class are separate conclusions: a table can be a
multi-environment trial (MET) even when its within-environment
randomisation cannot be recovered from the recorded columns.

## Usage

``` r
detect_design(
  df,
  roles = NULL,
  interactive = FALSE,
  threshold = 0.5,
  tie_delta = 0.02,
  env = NULL
)
```

## Arguments

- df:

  A data frame.

- roles:

  Optional roles tibble (as returned by
  [`propose_roles()`](https://max578.github.io/masque/reference/propose_roles.md)).
  When supplied, declared roles constrain candidate generation, and
  columns roled `treatment` define the treatment basis.

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

- env:

  Environment specification. `NULL` performs conservative automatic
  resolution and leaves ambiguous or weak evidence unresolved. `FALSE`
  disables MET handling and runs the legacy whole-table path. A
  character vector names one or more columns whose interaction defines
  the environment.

## Value

An S7 `design_summary` object. Legacy design fields include
`class_label`, `treatment_col`, `block_cols`, `whole_plot_col`,
`sub_plot_col`, `spatial_cols`, `scores`, `evidence`,
`recommended_roles`, `candidates`, and `warnings`. Scope fields include
`scope_label`, `scope_status`, `scope_confidence`, `is_met`, `env_cols`,
`env_method`, `n_env`, `group_cols`, `connectivity`, `per_env`, and
`within_design_label`.

## Details

With `env = NULL`, exact environment names and a bounded set of
site-year patterns are assessed conservatively. A site-only candidate
auto-resolves only when treatments are replicated across sites. Weak or
competing evidence produces an explicit uncertain result rather than a
guessed single trial. Supply `env` to define the environment basis, or
use `env = FALSE` to run the pre-0.9 whole-table path exactly.

After the scope step, the pooled legacy detector runs six independent
design rules. Each returns a score in \\\[0, 1\]\\. The highest-scoring
class above `threshold` is one of `"CRD"`, `"RCBD"`,
`"IBD/alpha-lattice"`, `"row-column"`, `"split-plot"`, `"factorial"`, or
`"none"`. Ties within `tie_delta` favour the simpler design. For a MET,
per-environment classes, treatment connectivity, and near-disjoint
experiment groups are diagnostics only. Dense connectivity calculations
that exceed the package safety bound are reported as `not_computed`.
None of these diagnostics proves the original randomisation protocol.

The detector never edits `df`. Its job is to recommend a role
assignment, surface the evidence, and (optionally) draw a sanity check
via [`plot()`](https://rdrr.io/r/graphics/plot.default.html).

## See also

[`propose_roles()`](https://max578.github.io/masque/reference/propose_roles.md)
for the role tibble that feeds detection and
[`plot_design_summary()`](https://max578.github.io/masque/reference/plot_design_summary.md)
for the sanity-check visualisation.

## Examples

``` r
# Classic alpha-lattice (24 genotypes, 3 reps, 6 blocks per rep).
if (requireNamespace("agridat", quietly = TRUE)) {
  d <- agridat::john.alpha
  ds <- detect_design(d)
  print(ds)
}
#> ── Environment scope  <uncertain> ──────────────────────────────────────────────
#> ! No environment candidate passed the conservative validity gates.
#> ── design_summary  <IBD/alpha-lattice> ─────────────────────────────────────────
#> • Treatment: gen
#> • Blocks: rep : block
#> ── Alternates (top rule scores) ────────────────────────────────────────────────
#> x <IBD/alpha-lattice > score = 1.00
#> <RCBD > score = 0.95
#> <CRD > score = 0.40
#> ── Recommended role hints ──────────────────────────────────────────────────────
#> = gen -> treatment [local=keep; collaborate=alias; auto]
#> = rep -> design [local=keep; collaborate=keep; auto]
#> = block -> design [local=keep; collaborate=keep; auto]
#> ℹ Use `plot(x)` for a sanity-check visualisation; pass to `propose_roles(df, detect = TRUE)` to seed role hints.

# Observational data frame -> class_label "none".
detect_design(mtcars)
#> ── Environment scope  <uncertain> ──────────────────────────────────────────────
#> ! No environment candidate passed the conservative validity gates.
#> ── design_summary  <none> ──────────────────────────────────────────────────────
#> ℹ No experimental design detected above threshold.
#> • Top rule scores all below 0.5. Treat as observational.
#> ── Alternates (top rule scores) ────────────────────────────────────────────────
#> <factorial > score = 0.46
#> <IBD/alpha-lattice > score = 0.30
#> <CRD > score = 0.00
#> ℹ Use `plot(x)` for a sanity-check visualisation; pass to `propose_roles(df, detect = TRUE)` to seed role hints.

# Explicit two-environment trial.
met <- expand.grid(
  env = factor(c("E1", "E2")),
  rep = factor(seq_len(2L)),
  gen = factor(c("G1", "G2", "G3"))
)
met$yield <- seq_len(nrow(met))
met_design <- detect_design(met, env = "env")
met_design@scope_label
#> [1] "multi_environment"
met_design@connectivity$status
#> [1] "connected"
```
