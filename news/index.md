# Changelog

## masque 0.6.0

A two-axis roles step, a hygiene layer, column-name aliasing, a
multi-table set layer, and a single guided verb turn masque into an
end-to-end tool for confidential tabular data.

### Breaking changes

- The roles table is now **two-axis**: a `role` column (what a column
  is) and a new `action` column (what
  [`mask()`](https://max578.github.io/masque/reference/mask.md) does to
  it). The role vocabulary changed – the old `keep` and `ignore` roles
  become the `keep` and `drop` *actions*, and new roles `date`, `id`,
  `text`, and `other` join `design` / `treatment` / `outcome` /
  `covariate`.
- [`mask()`](https://max578.github.io/masque/reference/mask.md) no
  longer requires a column roled `outcome`.
- Roles tables produced by masque 0.5.0 and earlier are upgraded
  automatically by
  [`roles_validate()`](https://max578.github.io/masque/reference/roles_validate.md)
  (and therefore by
  [`mask()`](https://max578.github.io/masque/reference/mask.md)) with a
  one-time deprecation warning that preserves the old mode semantics, so
  existing scripts keep working. Re-run
  [`propose_roles()`](https://max578.github.io/masque/reference/propose_roles.md)
  to silence the warning and adopt the new schema.

### The guided verb

- New [`masque()`](https://max578.github.io/masque/reference/masque.md)
  is the front door: one call reads the input (a data frame, a file, a
  folder, an Excel workbook, or a named list), proposes column roles,
  pauses for review in an interactive session, masks, audits, and -
  given an `out` path - writes the result. It dispatches a single table
  through [`mask()`](https://max578.github.io/masque/reference/mask.md)
  and a multi-table input through
  [`mask_set()`](https://max578.github.io/masque/reference/mask_set.md),
  and returns the same object the lower-level verbs do, so it stays
  fully scriptable: pass an edited `roles` table to skip the prompt.
  (The internal S7 result class previously bound to `masque` is now
  `masque_obj`; the class name is unchanged.)

### Two-axis roles (breaking, with an upgrade path)

- The roles table now carries two columns instead of one: `role` (what a
  column *is*) and `action` (what
  [`mask()`](https://max578.github.io/masque/reference/mask.md) *does*
  to it). `role` is one of `design`, `treatment`, `outcome`,
  `covariate`, `date`, `id`, `text`, `other`; `action` is one of `keep`,
  `scramble`, `alias`, `drop`.
  [`propose_roles()`](https://max578.github.io/masque/reference/propose_roles.md)
  resolves a mode-appropriate default action for every column, so the
  table you review is the masking plan that runs.
- New roles answer the three gaps the previous vocabulary left open: a
  first-class `date` role (date/time columns are row-permuted with class
  and NA pattern preserved), and the explicit “retain untouched” and
  “skip entirely” choices are now the `keep` and `drop` *actions*,
  available on any column rather than only the old `keep` / `ignore`
  roles.
- [`propose_roles()`](https://max578.github.io/masque/reference/propose_roles.md)
  gains a `mode` argument. The proposed actions differ between `local`
  and `collaborate` (for example a treatment is kept locally but aliased
  for collaboration); the table records the mode it was prepared for.
- New
  [`set_role()`](https://max578.github.io/masque/reference/set_role.md)
  helper edits a roles table ergonomically. Re-assigning a column’s role
  re-resolves its default action; passing an explicit `action` pins the
  column so a later mode change leaves it alone. Direct
  `roles$role[...] <-` edits still work.
- [`mask()`](https://max578.github.io/masque/reference/mask.md) no
  longer requires an `outcome` column. With none marked, the Gaussian
  copula simply re-simulates every scrambled numeric column jointly.
- `role = "design", action = "alias"` is a new opt-out from
  byte-identical design preservation: the design *structure* is kept but
  the site / block labels are hidden behind opaque aliases and restored
  by [`unmask()`](https://max578.github.io/masque/reference/unmask.md).
  The default for design columns remains `keep` (byte-identical).
- [`roles_validate()`](https://max578.github.io/masque/reference/roles_validate.md)
  validates the (role, action, kind) combination and fails closed on
  impossible pairings (a scrambled design column, an aliased numeric, a
  scrambled id). It returns the validated table with any `NA` actions
  resolved.
- Roles tables produced by masque \<= 0.5.0 (no `action` column; the
  `keep` / `ignore` roles; the `mask_levels` column) are upgraded
  automatically with a one-time deprecation warning, preserving the v1
  mode semantics exactly.

### Multi-table sets

- New
  [`mask_set()`](https://max578.github.io/masque/reference/mask_set.md)
  masks a whole multi-table dataset at once - a folder of CSV / TSV /
  `.fst` files, a multi-sheet Excel workbook, or a named list of data
  frames - returning one synthetic table per input table and a single
  private recipe bundle.
- **Cross-table-consistent aliasing.** A column that appears in several
  tables (a site code, a genotype name, a plot id) is detected as a
  *link* and aliased identically everywhere it occurs, so a join written
  against the synthetic set still resolves on the masked data. Links are
  proposed automatically and printed; override with the `links`
  argument, or set `links = FALSE` to mask each table independently.
- New
  [`read_set()`](https://max578.github.io/masque/reference/read_set.md)
  ingests the folder / workbook / list into a named list of data frames
  (clean rectangles only - a missing header row or non-rectangular sheet
  fails with an explanatory error). New
  [`write_set()`](https://max578.github.io/masque/reference/write_set.md)
  writes a masked set back out, mirroring the input format (workbook in,
  workbook out; folder in, folder of CSVs out). The private recipe
  bundle is never written by
  [`write_set()`](https://max578.github.io/masque/reference/write_set.md).
- [`synthetic()`](https://max578.github.io/masque/reference/synthetic.md),
  [`recipe()`](https://max578.github.io/masque/reference/recipe.md),
  [`apply_recipe()`](https://max578.github.io/masque/reference/apply_recipe.md),
  and [`unmask()`](https://max578.github.io/masque/reference/unmask.md)
  all dispatch on the set:
  [`synthetic()`](https://max578.github.io/masque/reference/synthetic.md)
  returns the named list of tables,
  [`recipe()`](https://max578.github.io/masque/reference/recipe.md) the
  bundle, and the round-trip verbs operate table by table.
- `data.table` joins Imports (fast `fread` / `fwrite`); `readxl` and
  `writexl` are Suggested for the Excel paths.

### Depth controls

- New `alias_names` argument on
  [`mask()`](https://max578.github.io/masque/reference/mask.md) hides
  the column names themselves - the last identifying surface a kept or
  design column exposes. `TRUE` replaces every retained name with an
  opaque alias (`col_001`, `col_002`, …); a character vector aliases
  just the named columns. The original-to-alias map lives in the
  (private) recipe and is inverted by
  [`apply_recipe()`](https://max578.github.io/masque/reference/apply_recipe.md)
  and [`unmask()`](https://max578.github.io/masque/reference/unmask.md),
  so a pipeline written against the aliased synthetic round-trips. This
  realises the long-reserved `column_name_map` recipe slot.
  [`reveal_maps()`](https://max578.github.io/masque/reference/reveal_maps.md)
  now also prints the column-name map.

### Hygiene

- New
  [`clean_table()`](https://max578.github.io/masque/reference/clean_table.md)
  verb (and a `clean` argument on
  [`mask()`](https://max578.github.io/masque/reference/mask.md), default
  `"auto"`) tidies a dirty table before masking: column names are
  legalised (valid, unique R names), and leading / trailing whitespace
  is trimmed from names and from character / factor labels. Both fixes
  are reported through `cli`, recorded in the recipe, and re-applied by
  [`apply_recipe()`](https://max578.github.io/masque/reference/apply_recipe.md)
  so retargeting still lines up.
- Near-duplicate labels - pairs that differ only in case (`"north"` vs
  `"North"`) or by a single edit (`"Compass"` vs `"Compas"`) - are
  *reported, never merged*: deciding whether two similar labels are the
  same value is a judgement masque leaves to the user. Set
  `clean = "report"` to preview fixes without applying them, or
  `clean = "off"` to skip hygiene entirely.

### Internal

- Dropped the `MASS` dependency: the copula now draws latent normals
  through a Cholesky factor of the regularised covariance, removing a
  hard import.

## masque 0.5.0

New feature release: joint-treatment masking plus role-table usability
and first-class date handling.
[`mask()`](https://max578.github.io/masque/reference/mask.md) and
[`roles_validate()`](https://max578.github.io/masque/reference/roles_validate.md)
now accept designs with two or more treatment factors (factorial,
split-plot trials).

### Usability

- New `keep` role: users can now explicitly mark a column for
  byte-identical pass-through in both local and collaborate mode. This
  is distinct from `design`, which remains for experimental-design
  structure, and from `ignore`, which is still dropped in collaborate
  mode.
- [`propose_roles()`](https://max578.github.io/masque/reference/propose_roles.md)
  now proposes Date / POSIX / difftime columns as `covariate` rather
  than `ignore`. Date/time covariates are row-permuted, retain their
  original class, and preserve the cell-level NA mask.
- Unsupported column classes now default to `keep` with a clear note,
  avoiding a confusing attempt to synthesize objects masque does not
  know how to mask.

### Masking and recipes

- Collaborate-mode logical covariates now receive opaque level aliases,
  matching the documented categorical-covariate contract.
  [`apply_recipe()`](https://max578.github.io/masque/reference/apply_recipe.md)
  and [`unmask()`](https://max578.github.io/masque/reference/unmask.md)
  round-trip those aliases back to logical values.
- [`detect_design()`](https://max578.github.io/masque/reference/detect_design.md)
  and its candidate proposer now honour user-supplied `keep` roles so
  explicitly-kept columns are not promoted into design hints.

### New features

- [`mask()`](https://max578.github.io/masque/reference/mask.md) now
  masks every column flagged `treatment`, not just one. Each treatment
  factor is aliased independently. A single treatment keeps the
  historical `trt_NNN` collaborate-mode alias prefix; with two or more,
  the column name is folded into the prefix (`<col>_trt_NNN`,
  e.g. `variety_trt_001`) so the opaque labels stay distinct and
  self-documenting, mirroring the categorical-covariate `<col>_LNN`
  convention. Aliasing each factor separately (rather than the treatment
  *combination*) preserves the per-factor structure that factorial
  models fit, and keeps each column’s alias namespace — and therefore
  [`audit_mask()`](https://max578.github.io/masque/reference/audit_mask.md)’s
  leakage accounting — unchanged.
- [`roles_validate()`](https://max578.github.io/masque/reference/roles_validate.md)
  no longer errors when more than one column is flagged `treatment`. The
  round-trip path
  ([`apply_recipe()`](https://max578.github.io/masque/reference/apply_recipe.md),
  [`unmask()`](https://max578.github.io/masque/reference/unmask.md))
  already inverted multiple per-column level maps, so recovery of every
  treatment factor works unchanged.

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
  layouts use `desplot::desplot()` or `ggplot2`-based packages.

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
