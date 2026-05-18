# Roadmap

## Roadmap

This page tracks features that are **deliberately deferred** from the
current release. Each item has a stable position in the long-term
design; future releases will land them behind explicit opt-in flags and
new exports. Version numbers are intentionally not committed: the order
in which deferred features land depends on user demand and the surface
area each one needs.

### What has already landed

- v0.2.0 — first public surface:
  [`mask()`](https://max578.github.io/masque/reference/mask.md),
  `recipe`,
  [`audit_mask()`](https://max578.github.io/masque/reference/audit_mask.md),
  [`apply_recipe()`](https://max578.github.io/masque/reference/apply_recipe.md)
  / [`unmask()`](https://max578.github.io/masque/reference/unmask.md)
  round-trip.
- v0.3.0 —
  [`detect_design()`](https://max578.github.io/masque/reference/detect_design.md) +
  [`plot_design_summary()`](https://max578.github.io/masque/reference/plot_design_summary.md) +
  `propose_roles(detect = TRUE)` default.
- v0.4.0 —
  [`synthesise_geospatial()`](https://max578.github.io/masque/reference/synthesise_geospatial.md)
  (preserves site-count and within-site clustering without publishing
  real coordinates).
- v0.4.1 — contract sharpening: fail-closed unknown-level handling in
  [`apply_recipe()`](https://max578.github.io/masque/reference/apply_recipe.md)
  / [`unmask()`](https://max578.github.io/masque/reference/unmask.md);
  integrity-fingerprint check on
  [`apply_recipe()`](https://max578.github.io/masque/reference/apply_recipe.md);
  atomic numeric pass-through in
  [`unmask()`](https://max578.github.io/masque/reference/unmask.md);
  honest `exact_match_pct` denominator in
  [`audit_mask()`](https://max578.github.io/masque/reference/audit_mask.md);
  [`synthesise_geospatial()`](https://max578.github.io/masque/reference/synthesise_geospatial.md)
  NA-mask source authority.

### Deferred — joint structure and shareability

#### Design-conditional synthesis

The current Gaussian copula uses a single global Pearson covariance over
all numeric outcomes and covariates. For multi-environment trials where
the genotype-by-environment interaction dominates the variance
structure, this is the wrong unit of analysis.

**Planned API**:

``` r

mask(df, roles,
     mode = "collaborate",
     condition_on = c("rep", "site:year"))
```

The copula would be fit *within* each stratum defined by `condition_on`,
preserving the conditional structure that mixed-effects models will see.
Compute cost scales with the number of strata.

#### Mixed-margin copula

The current package deliberately breaks the joint between categorical
covariates and numerics (categoricals are row-permuted independently of
the numeric copula). For datasets where the joint matters — e.g., soil
type clustering yield outliers — a Gaussian copula with discrete margins
(Smith and Khaled 2012; ordinal probit links) is the natural extension.

**Planned API**: `roles$kind == "ordinal"` plus a covariate-level option
to opt in.

#### `draw_new_synthetic(rec, n)`

Today, regenerating synthetic data requires the original. The recipe
holds enough state to re-translate a pipeline but not to re-simulate. A
future release will persist simulator state under
`save_recipe(rec, path, include_simulator = TRUE)` (currently a no-op)
so:

``` r

rec       <- read_recipe("path/to/rec.rds")
new_synth <- draw_new_synthetic(rec, n = 5000, seed = 99)
```

This is useful for cross-validation folds and bootstrap pipelines that
need many synthetic draws without revealing the original.

#### Joint-treatment masking

[`mask()`](https://max578.github.io/masque/reference/mask.md) currently
requires at most one treatment column. A future release will accept
multiple treatment columns and produce joint aliases (factorial trials,
treatment combinations) with an order-of-magnitude larger alias
namespace and a corresponding update to
[`audit_mask()`](https://max578.github.io/masque/reference/audit_mask.md)’s
leakage thresholds.

### Deferred — collaboration ergonomics

#### Column-name aliasing in collaborate mode

The `column_name_map` slot in the recipe is currently `NULL`. A future
release will support `mask(..., alias_columns = TRUE)` so that even
column identities are hidden behind opaque names (`x_001`, `x_002`, …).
[`apply_recipe()`](https://max578.github.io/masque/reference/apply_recipe.md)
and [`unmask()`](https://max578.github.io/masque/reference/unmask.md)
already invert column-name maps if present.

#### Interactive role builder

[`propose_roles()`](https://max578.github.io/masque/reference/propose_roles.md)
is declarative — the user edits the returned tibble. A thin interactive
wrapper (using `cli` prompts for ambiguous columns) would lower the
barrier for one-off use. The declarative core stays unchanged so scripts
remain reproducible.

#### `mask_csv()` convenience verb

A wrapper that reads a CSV, runs
[`propose_roles()`](https://max578.github.io/masque/reference/propose_roles.md)
with sensible defaults, surfaces the role tibble for the user to
confirm, and returns the masque object. Targets non-R-fluent data
custodians.

### Out of scope, permanently

- **Differential-privacy guarantees.** A different package, different
  algorithms, different threat model. `masque` will not pretend.
- **Public-release safety claims.** Synthetic from `masque` is for
  controlled sharing only; “safe to publish” is never a `masque` claim.
- **Pipeline source-code rewriting.** Translation happens through the
  data via
  [`apply_recipe()`](https://max578.github.io/masque/reference/apply_recipe.md)
  and [`unmask()`](https://max578.github.io/masque/reference/unmask.md),
  not by mutating R or Python source code.

### References

- Smith, M. and Khaled, M. (2012). Estimation of copula models with
  discrete margins via Bayesian data augmentation. *Journal of the
  American Statistical Association* 107: 290-303.
- John, J. A. (1987). *Statistical Analysis of Experiments with
  Different Numbers of Replicates per Treatment.* CRC Press.

If you have a use case that does not fit cleanly in the current release,
open an issue with a small reproducible example.
