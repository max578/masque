# masque 0.2.0

First public release of `masque` — a structurally faithful development
surrogate for tabular datasets. Successor to the unreleased `synthPR`
v0.1.0 (folder-scanning multi-file API), rewritten around a single-file
data-frame-first interface and a round-trippable `recipe` object.

`masque` is not an anonymisation or differential-privacy tool. It produces
development surrogates suitable for building and debugging pipelines, and
a private `recipe` that re-targets a pipeline built against the synthetic
clone back onto the original data. See `vignette("confidentiality")` for
the threat model.

## Design

* **Strict 5-role taxonomy** for columns: `design`, `treatment`,
  `outcome`, `covariate`, `ignore`. Multi-outcome supported. Date /
  POSIX columns and PII-pattern column names default to `ignore`.
* **Two modes** with different safety postures:
  * `local` — realistic dev surrogate for the data owner. Column names
    and level vocabularies preserved. Treatment-level permutation is
    opt-in. Issues a load-time warning when the synthetic is extracted.
  * `collaborate` — give the synthetic to a collaborator while keeping
    the recipe private. Treatment + categorical-covariate levels are
    opaque-aliased (`trt_001`, `<col>_L01`). Numeric draws are
    jittered within column resolution; integer columns are
    stochastically rounded. `ignore` columns are dropped.
    `audit_mask()` runs automatically and warns on HIGH leakage.

## Public API (11 exports)

* `propose_roles(df)` — heuristics-driven role tibble; the user edits
  and passes to `mask()`.
* `roles_validate(roles, df)` — fail-closed structural + semantic check.
* `mask(df, roles, mode, seed, ...)` — returns an S7 `masque` object.
* `synthetic(m)` / `recipe(m)` — accessors that hide S7.
* `apply_recipe(original, recipe)` — forward translate original-namespace
  data into the synthetic namespace.
* `unmask(x, recipe, column = NULL)` — inverse on a data frame or atomic
  vector; round-trips a pipeline back to the original.
* `save_recipe(rec, path, include_simulator = FALSE)` /
  `read_recipe(path)` — runtime-minimal `.rds` persistence (under 10 KB
  on a 17,000-row, 38-column MET fixture).
* `audit_mask(m, original = NULL, print = TRUE)` — first-class leakage
  audit returning the per-column severity tibble.
* `reveal_maps(recipe)` — explicit, banner-fenced unmasked-map reveal
  (never automatic; `print(recipe)` is redacted by default).

## Synthesis engine

* Numeric: per-column empirical-quantile marginals + a single global
  Pearson copula correlation matrix sampled via Gaussian copula.
* Categorical: within-column row permutation that preserves the level
  set and marginal frequencies.
* NA mask: preserved cell-by-cell from the original.
* Design columns: byte-identical pass-through in both modes.

## Confidentiality

* RNG hygiene throughout (`withr::with_seed` / `local_preserve_seed`);
  `mask()` does not mutate the caller's `.Random.seed`.
* `recipe` is runtime-minimal by default — no copula matrix or raw
  marginals stored. SHA-256 NA-mask fingerprint provided as an
  integrity check, not a privacy primitive.
* `print(recipe)` redacted by default; `reveal_maps()` is the only
  unmasked path.
* `audit_mask()` flags retained PII-pattern columns, unaliased
  treatments under collaborate, rare-level leakage, and numeric exact-
  match rates above the per-role thresholds.

## Documentation

* Four vignettes: `getting_started`, `confidentiality`,
  `recipe_anatomy`, `roadmap`.
* `inst/extdata/john_alpha.csv` — 72-row, 7-column public fixture
  derived from `agridat::john.alpha` (John 1987, alpha design).

## History

Predecessor `synthPR` v0.1.0 (folder-scanning, multi-file) is archived
at `_legacy/synthPR_v0.1.0/` in the development workspace and is not
distributed.
