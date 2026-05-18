# Changelog

## masque 0.4.1

Maintenance release: contract-sharpening corrections plus the
documentation and metadata that were prepared for v0.4.0 but not
released. No new public exports. The two behaviour changes below are
deliberate fail-closed corrections to existing exports; user code that
depended on the silent failure mode will need to be updated.

### Behaviour: fail-closed corrections

- [`apply_recipe()`](https://max578.github.io/masque/reference/apply_recipe.md)
  and [`unmask()`](https://max578.github.io/masque/reference/unmask.md)
  now **error** when a non-NA value is not present in the recipe’s level
  map. Previously the row was silently coerced to `NA`, which could
  quietly poison downstream model matrices. Schema drift or a new
  treatment level in the input now fails closed with the offending
  values listed.
- [`apply_recipe()`](https://max578.github.io/masque/reference/apply_recipe.md)
  now verifies that the NA mask of `original` matches the recipe’s
  recorded `integrity_fp`. A mismatch errors with guidance. New
  `check_integrity = TRUE` parameter (default) gives an escape hatch
  (`check_integrity = FALSE`) for workflows where the missingness has
  legitimately changed since the recipe was built.

### Bug fixes

- `unmask(x, rec)` now passes through atomic numeric, integer, logical,
  and `Date` / `POSIXct` vectors unchanged, matching the documented
  numeric pass-through contract. Previously these inputs errored when
  the recipe held no level maps.
- [`audit_mask()`](https://max578.github.io/masque/reference/audit_mask.md)’s
  `exact_match_pct` now divides by the number of jointly-observed
  comparable cells, not by `nrow(df)`. Columns dominated by NAs no
  longer underreport leakage. The audit tibble gains a new
  `comparable_n` column for interpretability.
- [`synthesise_geospatial()`](https://max578.github.io/masque/reference/synthesise_geospatial.md)
  now uses `original`’s NA mask as the authority for cell-level
  preservation (previously used `synth`’s mask, which could let
  synthesised coordinates leak into rows that the original had missing).
  Adds a `nrow(synth) == nrow(original)` check.

### Documentation

- [`roles_validate()`](https://max578.github.io/masque/reference/roles_validate.md)
  error message for the multiple-treatment case is refreshed: drops the
  stale “v0.2 / deferred to v0.3” wording and guides the user to either
  edit the roles tibble or call `propose_roles(df, detect = FALSE)` for
  byte-stable v0.2.x behaviour.
- Stale “arrive in build-order steps 6-7” comment in
  [`mask()`](https://max578.github.io/masque/reference/mask.md)’s
  roxygen removed.
- `recipe_io.R` doc and the `recipe_anatomy` vignette reword the
  `include_simulator = TRUE` no-op without pinning it to v0.2 / v0.3.
- `roadmap` vignette restructured around feature areas. The hard version
  pins (“v0.3”, “v0.4”) are gone — v0.3 / v0.4 shipped different
  features from the prior roadmap, so the pins were stale.
- `getting_started` vignette: “vignette(‘roadmap’) — what’s planned for
  v0.3+” replaced by “features deliberately deferred from the current
  release”.

### Test suite

- Local MET integration tests (`test-mask-end-to-end.R`,
  `test-mask-roundtrip-integration.R`) call
  `propose_roles(df, detect = FALSE)` so the suite is clean against the
  maintainer’s local fixtures while the multi-treatment design decision
  remains roadmap.
- Three jitter tests that intentionally trigger the collaborate-mode
  HIGH-leakage warning now wrap with `expect_warning("HIGH leakage")` so
  future warning regressions remain visible.
- New tests cover: atomic numeric / integer / logical pass-through in
  [`unmask()`](https://max578.github.io/masque/reference/unmask.md);
  fail-closed unknown-level handling in
  [`apply_recipe()`](https://max578.github.io/masque/reference/apply_recipe.md)
  and [`unmask()`](https://max578.github.io/masque/reference/unmask.md);
  `integrity_fp` enforcement (positive, negative, and the
  `check_integrity = FALSE` escape hatch);
  [`synthesise_geospatial()`](https://max578.github.io/masque/reference/synthesise_geospatial.md)
  NA-mask source authority and row-count check.

## masque 0.4.0

Adds first-class geospatial synthesis. One new export, no breaking
changes to the v0.3.0 surface.

### New export

- `synthesise_geospatial(synth, original, anchor_col, lat_col, lon_col, anchor_centroids, site_spread_deg, jitter_deg, seed)`
  — re-anchors the latitude / longitude columns in a masqued data frame
  at user-supplied centroids, while preserving (a) the count of distinct
  sites per anchor level, (b) the per-site replication distribution,
  and (c) within-site tight clustering with between-site spread. The
  original positions are never published; the function reads them only
  to count distinct sites. NA pattern in coordinates is preserved
  cell-by-cell. RNG hygiene via
  [`withr::local_preserve_seed()`](https://withr.r-lib.org/reference/with_seed.html).

  Motivated by the masque release walkthrough, where state-centroid

  - uniform-jitter (per-walkthrough recipe) failed to preserve the
    within-state clustering of real trial sites.

### CRAN and r-universe readiness

- Added `cran-comments.md` for first-submission notes.
- Added `.github/workflows/R-CMD-check.yaml` (r-lib standard matrix:
  Linux release / devel / oldrel-1, macOS release, Windows release).
- `R CMD check --as-cran` reports 0 errors, 0 warnings, 2 NOTEs
  (new-submission boilerplate and local HTML Tidy environmental).

### Documentation

- `R/synthesise_geospatial.R` carries the full roxygen doc + a
  `\donttest{}` example.

## masque 0.3.0

Adds automatic experimental-design detection and a sanity-check
visualisation. New public surface: 3 exports, 1 vignette.

### New exports

- `detect_design(df, roles = NULL, interactive = FALSE, threshold = 0.5, tie_delta = 0.02)`
  — returns an S7 `design_summary` with the most likely design class
  (`CRD`, `RCBD`, `IBD/alpha-lattice`, `row-column`, `split-plot`,
  `factorial`, or `none`), per-rule scores, evidence, and a
  `recommended_roles` tibble. Rule engine, not ML.
- `design_summary` — S7 class wrapping the detection result.
  [`print()`](https://rdrr.io/r/base/print.html) is cli-styled and
  surfaces top-3 alternates so the user can see how confident the call
  was. Slots include `class_label`, `treatment_col`, `block_cols`,
  `whole_plot_col`, `sub_plot_col`, `spatial_cols`, `scores`,
  `evidence`, `recommended_roles`, `candidates`, `warnings`.
- `plot_design_summary(x, df, engine = c("base", "ggplot2"))` — also
  registered as an S7
  [`plot()`](https://rdrr.io/r/graphics/plot.default.html) method.
  Base-graphics sanity-check visualisation dispatched per class:
  replication tile, spatial layout, factor-nesting tree,
  treatment-frequency + NA-pattern.

### Behaviour change

- `propose_roles(df)` flips to `detect = TRUE` by default. The detected
  design’s `recommended_roles` are overlaid on the name-based proposal,
  promoting structurally-identified treatments and blocks even when
  their column names don’t match the design / treatment regexes (e.g.,
  `gen` in an alpha-lattice). The `design_summary` is stashed as
  `attr(roles, "design")`. Pass `detect = FALSE` to recover the v0.2.x
  byte-stable behaviour.

### Design philosophy

- Detection is **read-only**.
  [`mask()`](https://max578.github.io/masque/reference/mask.md)
  synthesis behaviour is unchanged. Only
  [`propose_roles()`](https://max578.github.io/masque/reference/propose_roles.md)
  consumes detection output, and only as role hints.
- Rule engine over ML: each of the six rules is a pure function
  returning a score in `[0, 1]` with evidence; the orchestrator picks
  the top above threshold, breaking ties in favour of the simpler design
  (CRD \< RCBD \< factorial \< IBD \< row-column \< split-plot).
- Visualisation is sanity-check grade. For publication-quality field
  layouts use
  [`desplot::desplot()`](http://kwstat.github.io/desplot/reference/desplot.md)
  or `ggplot2`-based packages.

### Suggests

- `agridat` — canonical fixtures for tests and the new vignette.
- `ggplot2` — optional plot engine via `engine = "ggplot2"`; base
  graphics is the default and the fallback.

### Limitations

- The detector cannot distinguish a true split-plot from a
  factorial-in-blocks: both have the same data layout. The whole-plot /
  sub-plot assignment uses cardinality (fewer levels = whole-plot),
  which is heuristic.
- Detection on fewer than ~20 rows is unreliable. Pass `detect = FALSE`
  for toy fixtures.

## masque 0.2.0

First public release of `masque` — a structurally faithful development
surrogate for tabular datasets. Successor to the unreleased `synthPR`
v0.1.0 (folder-scanning multi-file API), rewritten around a single-file
data-frame-first interface and a round-trippable `recipe` object.

`masque` is not an anonymisation or differential-privacy tool. It
produces development surrogates suitable for building and debugging
pipelines, and a private `recipe` that re-targets a pipeline built
against the synthetic clone back onto the original data. See
[`vignette("confidentiality")`](https://max578.github.io/masque/articles/confidentiality.md)
for the threat model.

### Design

- **Strict 5-role taxonomy** for columns: `design`, `treatment`,
  `outcome`, `covariate`, `ignore`. Multi-outcome supported. Date /
  POSIX columns and PII-pattern column names default to `ignore`.
- **Two modes** with different safety postures:
  - `local` — realistic dev surrogate for the data owner. Column names
    and level vocabularies preserved. Treatment-level permutation is
    opt-in. Issues a load-time warning when the synthetic is extracted.
  - `collaborate` — give the synthetic to a collaborator while keeping
    the recipe private. Treatment + categorical-covariate levels are
    opaque-aliased (`trt_001`, `<col>_L01`). Numeric draws are jittered
    within column resolution; integer columns are stochastically
    rounded. `ignore` columns are dropped.
    [`audit_mask()`](https://max578.github.io/masque/reference/audit_mask.md)
    runs automatically and warns on HIGH leakage.

### Public API (11 exports)

- `propose_roles(df)` — heuristics-driven role tibble; the user edits
  and passes to
  [`mask()`](https://max578.github.io/masque/reference/mask.md).
- `roles_validate(roles, df)` — fail-closed structural + semantic check.
- `mask(df, roles, mode, seed, ...)` — returns an S7 `masque` object.
- `synthetic(m)` / `recipe(m)` — accessors that hide S7.
- `apply_recipe(original, recipe)` — forward translate
  original-namespace data into the synthetic namespace.
- `unmask(x, recipe, column = NULL)` — inverse on a data frame or atomic
  vector; round-trips a pipeline back to the original.
- `save_recipe(rec, path, include_simulator = FALSE)` /
  `read_recipe(path)` — runtime-minimal `.rds` persistence (under 10 KB
  on a 17,000-row, 38-column MET fixture).
- `audit_mask(m, original = NULL, print = TRUE)` — first-class leakage
  audit returning the per-column severity tibble.
- `reveal_maps(recipe)` — explicit, banner-fenced unmasked-map reveal
  (never automatic; `print(recipe)` is redacted by default).

### Synthesis engine

- Numeric: per-column empirical-quantile marginals + a single global
  Pearson copula correlation matrix sampled via Gaussian copula.
- Categorical: within-column row permutation that preserves the level
  set and marginal frequencies.
- NA mask: preserved cell-by-cell from the original.
- Design columns: byte-identical pass-through in both modes.

### Confidentiality

- RNG hygiene throughout
  ([`withr::with_seed`](https://withr.r-lib.org/reference/with_seed.html)
  / `local_preserve_seed`);
  [`mask()`](https://max578.github.io/masque/reference/mask.md) does not
  mutate the caller’s `.Random.seed`.
- `recipe` is runtime-minimal by default — no copula matrix or raw
  marginals stored. SHA-256 NA-mask fingerprint provided as an integrity
  check, not a privacy primitive.
- `print(recipe)` redacted by default;
  [`reveal_maps()`](https://max578.github.io/masque/reference/reveal_maps.md)
  is the only unmasked path.
- [`audit_mask()`](https://max578.github.io/masque/reference/audit_mask.md)
  flags retained PII-pattern columns, unaliased treatments under
  collaborate, rare-level leakage, and numeric exact- match rates above
  the per-role thresholds.

### Documentation

- Four vignettes: `getting_started`, `confidentiality`,
  `recipe_anatomy`, `roadmap`.
- `inst/extdata/john_alpha.csv` — 72-row, 7-column public fixture
  derived from
  [`agridat::john.alpha`](https://kwstat.github.io/agridat/reference/john.alpha.html)
  (John 1987, alpha design).

### History

Predecessor `synthPR` v0.1.0 (folder-scanning, multi-file) is archived
at `_legacy/synthPR_v0.1.0/` in the development workspace and is not
distributed.
