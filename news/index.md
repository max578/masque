# Changelog

## masque (development version)

### Documentation

- The `getting_started` vignette’s environment-overview figure now has a
  `fig.cap`/`fig.alt` and two sentences reading the panel (what even bar
  heights and a single connected component mean, and what a broken MET
  would look like there).
- Fixed a dangling comparative in the `getting_started` mode-comparison
  table (“numeric values that may match observed” -\> “… the observed
  values”).
- `recipe_anatomy` documents the recipe’s `coords` and
  `allow_unmasked_coords` properties (added in 0.10.0/0.11.0) and shows
  `recipe(m)@coords` on a worked coordinate example.
- `README.md` no longer hard-codes a stale version number; points to
  `NEWS.md` instead and flags the 0.10.0/0.11.0 coordinate-handling
  changes for readers coming from an older tag.
- [`apply_recipe()`](https://max578.github.io/masque/reference/apply_recipe.md)’s
  roxygen no longer describes the pre-0.6.0 `ignore` role; step 2 now
  states the current, mode-independent `action == "drop"` rule.
- Added `@examples` to
  [`read_recipe()`](https://max578.github.io/masque/reference/read_recipe.md)
  and [`unmask()`](https://max578.github.io/masque/reference/unmask.md),
  the package’s last two exports without a runnable example.
- Converted seventeen stray Unicode em dashes and one Unicode `±` in
  internal and roxygen comments to the package’s ASCII `--`/`+/-`
  convention (no rendered-text or behaviour change).

## masque 0.11.0

### Breaking changes

- **A coordinate in a masked table is masked unless you say otherwise.**
  [`mask()`](https://max578.github.io/masque/reference/mask.md) now
  **stops** when a column whose name says coordinate (`gps`, `lat`,
  `lon`, `easting`, `northing`, `utm`, `wgs84`, …) would be written
  through with `action = "keep"`. A position locates the site and often
  the operator with it, so the burden is on the caller to say what
  should happen to it, and the default when nothing is said is to refuse
  rather than to emit.

  Three ways to state otherwise, all unchanged in spelling:

  - declare the pair to `coords`, which coarsens it by the on-land
    geomask;
  - give the column a masking action (`drop`, the default
    [`propose_roles()`](https://max578.github.io/masque/reference/propose_roles.md)
    already proposes for a coordinate-named column, or `scramble`);
  - pass the new `allow_unmasked_coords = TRUE`, having decided the
    coordinate is not sensitive. It is recorded on the recipe.

  The refusal is the classed condition `masque_unmasked_coords`.

- A column detected as a coordinate only by the **shape of its values**
  – a numeric pair inside plausible latitude and longitude ranges
  carrying at least four decimal places, which is metre-scale precision
  no temperature or yield column has – raises the classed warning
  `masque_coords_suspected` rather than stopping. Confidence is lower
  there, and a false positive should not block a legitimate mask.
  Ordinary numeric covariates do not trip it: whole numbers,
  low-precision values and unpaired columns are all excluded.

### Bug fixes

- [`audit_mask()`](https://max578.github.io/masque/reference/audit_mask.md)
  reported a coordinate declared to `coords` as HIGH leakage with the
  note “kept as-is - visible to collaborators”. The column had in fact
  been coarsened in place by the geomask, displaced by the requested
  radius and shared across its site. It now audits as **medium** in
  collaborate mode, with the note “coordinate coarsened in place by the
  geomask”. The stale HIGH also tripped the package-managed write gate,
  so every caller who used `coords` had to override it to write.

- The audit
  [`mask()`](https://max578.github.io/masque/reference/mask.md) runs for
  itself in collaborate mode was built on a temporary recipe that
  omitted the coordinate record, so it reached the same wrong conclusion
  as above even after the record existed.

## masque 0.10.0

### Breaking changes

- **A coordinate belongs to a site, not to a row.**
  [`jitter_coordinates()`](https://max578.github.io/masque/reference/jitter_coordinates.md)
  and `mask(coords = )` now draw **one displacement per site** and
  broadcast it to every row of that site, instead of displacing every
  row independently. A table holding many rows per physical place –
  plots within a trial, samples within a paddock, observations within a
  farm – now comes back with one masked coordinate per place, as its
  source table has one true coordinate per place.

  **Tables masked by 0.9.2 or earlier carry the old per-row structure.**
  Their coordinate columns assert that observations kilometres apart
  share a site, and should be treated as invalid for anything spatial
  until the table is rebuilt under 0.10.0.

  The change closes a confidentiality defect as well as a fidelity one.
  Donut displacement is isotropic, so the mean of many independent draws
  around one true site converges on that site: averaging the 360 rows of
  a single trial recovered the true position to a median 0.58 km,
  against the 5 km floor the donut was asked for. One draw per site
  removes that estimator and leaves the full displacement in place.

- [`jitter_coordinates()`](https://max578.github.io/masque/reference/jitter_coordinates.md)
  gains `by`, which chooses how a site is identified. `by = NULL` (the
  default) groups rows sharing an identical input coordinate. A
  character vector names site columns, for the case where a site’s
  recorded coordinates differ slightly between rows; such a group is
  consolidated to its row-weighted centroid and the consolidation is
  reported by a classed `masque_geo_consolidated` warning, with
  `masque_geo_wide_group` raised when a named group spans more than the
  displacement radius. `by = FALSE` restores the pre-0.10.0 per-row draw
  and warns (`masque_geo_ungrouped`) if the input carries repeated
  coordinate pairs. It exists only so a table masked by an earlier
  version can be reproduced.

- A site that cannot be placed on land within `max_tries` re-draws is
  now set to `NA` on both axes rather than left unchanged. Leaving it
  unchanged shipped the **true** coordinate inside a table the caller
  believed was masked, behind a warning. The `masque_geo_unplaced`
  warning is unchanged in class and still names the count.

  Genuinely point-level input – every coordinate pair already distinct –
  is unaffected by all of the above, and reproduces its 0.9.2 output
  exactly under the same seed.

- One displacement per site holds *within* a table, not across rebuilds.
  Each rebuild with a fresh seed is an independent draw, so a site kept
  in several masked versions can be averaged back out: at the 5-20 km
  default, eight kept rebuilds recover it to 4.5 km, below the floor.
  Reuse the seed and the displacement is identical, so there is nothing
  to average. Documented under “Rebuilding, and the displacement budget”
  in
  [`?jitter_coordinates`](https://max578.github.io/masque/reference/jitter_coordinates.md).

### New features

- `mask(coords = )` accepts `by` in a coordinate spec, for example
  `coords = list(list(lat = "GPS_S", lon = "GPS_E", by = "TRIAL"))`. The
  grouping is taken from the **original** table, so a site column that
  is aliased, permuted or dropped in the synthetic still groups
  correctly.

- The recipe records what happened to each declared coordinate pair: the
  jitter parameters, the grouping it was masked under, the number of
  sites that grouping produced, any consolidated sites, and any site set
  to `NA`. It is shown by `print(recipe(m))` and readable at
  `recipe(m)@coords`. Recipes written before 0.10.0 read back with no
  such record.

### Bug fixes

- [`mask()`](https://max578.github.io/masque/reference/mask.md) gave
  every declared coordinate pair the same seed, so two
  latitude/longitude pairs in one table received identical displacement
  vectors. Each pair now draws from its own sub-stream,
  deterministically derived from the
  [`mask()`](https://max578.github.io/masque/reference/mask.md) seed.

## masque 0.9.2

### New features

- [`mask()`](https://max578.github.io/masque/reference/mask.md) gains a
  `coords` argument to coarsen geographic coordinates as part of
  masking. Declare one or more latitude/longitude pairs (for example
  `coords = list(c(lat = "GPS_S", lon = "GPS_E"))`) and each pair is
  passed through synthesis untouched and then displaced in place by the
  on-land
  [`jitter_coordinates()`](https://max578.github.io/masque/reference/jitter_coordinates.md)
  geomask (a 5-20 km donut by default), instead of being
  copula-scrambled into implausible locations. A pair may be a bare
  `c(lat =, lon =)` vector or a
  `list(lat =, lon =, min_km =, max_km =, ...)` that also carries jitter
  parameters; both spellings work (numbers supplied through the vector
  form are coerced back from strings). A declared pair always survives,
  coarsened; the recipe records that it was coarsened, and
  [`apply_recipe()`](https://max578.github.io/masque/reference/apply_recipe.md)
  retargets a pipeline to the real coordinates.

## masque 0.9.1

### Breaking changes

- [`propose_roles()`](https://max578.github.io/masque/reference/propose_roles.md)
  now protects a conservatively detected multi-environment allocation by
  default. Before 0.9.1, an environment column not recognised by the
  name heuristic could remain `covariate/scramble`, which moved
  observations between environments. High-confidence categorical
  environment columns now become `design/keep` in local mode and
  `design/alias` in collaborate mode. Numeric environment columns remain
  `design/keep` and raise a classed disclosure warning in collaborate
  mode. Disable the new scope path explicitly when reproducing the
  former detector output:

  ``` r

  detect_design(df, env = FALSE)
  propose_roles(df, detect = FALSE)
  ```

### New features

- [`detect_design()`](https://max578.github.io/masque/reference/detect_design.md)
  gains an append-only `env` argument and an orthogonal
  environment-scope contract. Use `env = NULL` for conservative
  automatic resolution, `env = c("site", "year")` for an explicit
  composite, or `env = FALSE` for the whole-table compatibility path.
  The returned `design_summary` records scope confidence, environment
  basis, experiment groups, exact treatment-connectivity components, and
  advisory per-environment design summaries without storing the source
  data.
- [`print()`](https://rdrr.io/r/base/print.html) on a `design_summary`
  now leads with scope and reports bounded, aggregated MET diagnostics.
  [`plot()`](https://rdrr.io/r/graphics/plot.default.html) supports
  compact base and ggplot2 environment overviews plus one selected field
  layout through `environment =`. Connectivity and inner-design labels
  are diagnostic and do not claim to reconstruct the original
  randomisation.
- New
  [`jitter_coordinates()`](https://max578.github.io/masque/reference/jitter_coordinates.md)
  coarsens latitude/longitude in place by an on-land geographic-masking
  jitter (donut or Gaussian), so a synthetic table can carry realistic
  coordinates without revealing a true field or farm location. The donut
  default moves every point 5-20 km in a random direction, re-drawing
  until it lands on land (via `maps`); the NA pattern and the
  latitude/longitude pairing are preserved. It complements
  [`synthesise_geospatial()`](https://max578.github.io/masque/reference/synthesise_geospatial.md),
  which instead re-anchors coordinates at user-supplied fake centroids.

### Bug fixes

- Omitting `mode` from
  [`mask()`](https://max578.github.io/masque/reference/mask.md) or
  [`mask_set()`](https://max578.github.io/masque/reference/mask_set.md)
  now inherits the mode stored by
  [`propose_roles()`](https://max578.github.io/masque/reference/propose_roles.md),
  rather than silently falling back to local defaults. An explicit
  collaborate-to-local change raises a classed `masque_mode_downgrade`
  warning.
  [`mask_set()`](https://max578.github.io/masque/reference/mask_set.md)
  rejects role plans carrying mixed mode provenance.

- [`mask()`](https://max578.github.io/masque/reference/mask.md) and
  [`mask_set()`](https://max578.github.io/masque/reference/mask_set.md)
  now warn (classed `masque_mode_unset`) when no `mode` is supplied and
  the `roles` table carries no mode provenance, instead of silently
  masking in `local` mode. A `data.table()` wrap or a
  [`saveRDS()`](https://rdrr.io/r/base/readRDS.html) round-trip strips
  the tibble attribute that records the mode, so the warning turns a
  silent local-mode downgrade into a recoverable one.

- Site-only environment candidates now require replicated treatment
  evidence across sites for automatic promotion. A block nested within
  one farm is left for review rather than being misclassified as an
  environment.

- Environment connectivity diagnostics now guard both dense incidence
  and environment-adjacency allocations. Oversized problems return an
  explicit `not_computed` diagnostic instead of attempting an unsafe
  allocation.

- Experiment-group diagnostics tolerate a small, recorded treatment
  overlap while rejecting genuinely interleaved groups. The evidence now
  reports the confined and shared-treatment fractions.

- Explicitly pinned role actions are no longer overwritten when a
  detected environment recommendation promotes a column to the `design`
  role.

- A medium-confidence or ambiguous environment candidate is now
  preserved as `design/keep` in both modes rather than falling through
  to a `covariate` default. Previously an unreplicated environment named
  with a site token outside the design-name heuristic (for example
  `county`, `location` or `farm`) could be silently row-permuted by a
  default [`mask()`](https://max578.github.io/masque/reference/mask.md),
  moving observations between environments. Such a column is kept
  byte-identical and is never auto-aliased; pass `env =` to enable
  environment-aware masking.

- Invalid (non-syntactic) column names are now legalised in **every**
  `clean` mode, not only `"auto"`, and the repair is raised as a classed
  `masque_name_repaired` warning and recorded in the recipe. Previously,
  under `clean = "off"` an invalid name such as `GY_%VARMAX` was
  silently rewritten by
  [`make.names()`](https://rdrr.io/r/base/make.names.html) inside
  numeric synthesis with no map recorded, so the synthesised column no
  longer matched its source: the original column survived **un-masked**
  alongside the synthetic copy – a leak – and the round-trip broke.
  [`mask()`](https://max578.github.io/masque/reference/mask.md) now
  legalises names up front in all modes, remaps the `roles` table,
  records the map, and `synthesise_numeric_local()` no longer rewrites
  names.

- [`unmask()`](https://max578.github.io/masque/reference/unmask.md) now
  restores the original (pre-legalisation) column names, so a legalised
  name round-trips symmetrically with
  [`apply_recipe()`](https://max578.github.io/masque/reference/apply_recipe.md).

## masque 0.8.2

### New features

- New
  [`role_options()`](https://max578.github.io/masque/reference/role_options.md)
  renders the two-axis vocabulary as data: every role and action pair,
  the storage kinds the pair works for, and the reason it is constrained
  when it is. The grid is generated from the same compatibility rules
  [`roles_validate()`](https://max578.github.io/masque/reference/roles_validate.md)
  enforces at
  [`mask()`](https://max578.github.io/masque/reference/mask.md) time, so
  it cannot drift from the validator. `role_options(kind = "factor")`
  filters to the combinations available for one column’s storage kind.

### Minor improvements and fixes

- The *Getting started* vignette gains an “Editing the plan as code”
  section: vectorised
  [`set_role()`](https://max578.github.io/masque/reference/set_role.md),
  direct data-frame edits with `NA` action re-resolution, the
  [`role_options()`](https://max578.github.io/masque/reference/role_options.md)
  grid, and hand-flagging `pii_suspected` on a sensitively valued column
  the name heuristic cannot see.

## masque 0.8.1

### Bug fixes

- The guided review’s edit option (`e`) no longer destroys the session
  when the spreadsheet editor cannot start.
  [`utils::edit()`](https://rdrr.io/r/utils/edit.html) on a data frame
  requires the X11 dataentry widget - missing on macOS without XQuartz
  and on headless systems - and its error previously propagated out of
  [`masque()`](https://max578.github.io/masque/reference/masque.md),
  losing the proposal and the user’s place. The editor call is now
  guarded: on failure a dependency-free console editor takes over (pick
  a column, then a role and an action from numbered menus). Every
  console edit is applied through
  [`set_role()`](https://max578.github.io/masque/reference/set_role.md),
  so vocabulary validation and default-action re-resolution match the
  scriptable path exactly, and the roles table’s provenance attributes
  survive.
- The review prompt now accepts the bracketed forms it advertises (`[e]`
  is read as `e`).

## masque 0.8.0

### Safety fix: HIGH leakage findings are never silenced (breaking behaviour)

This release corrects a safety-contract defect in the guided workflow.
In 0.5.0 through 0.7.1,
[`masque()`](https://max578.github.io/masque/reference/masque.md) and
[`mask_set()`](https://max578.github.io/masque/reference/mask_set.md)
wrapped their internal
[`mask()`](https://max578.github.io/masque/reference/mask.md) calls in
[`suppressWarnings()`](https://rdrr.io/r/base/warning.html), so the
HIGH-leakage warning raised by the collaborate-mode audit never reached
the caller - and the guided summary could then print sharing language
for output the audit had flagged. Generation must never imply release;
the behaviour now matches the documentation.

- [`masque()`](https://max578.github.io/masque/reference/masque.md) and
  [`mask_set()`](https://max578.github.io/masque/reference/mask_set.md)
  no longer suppress warnings from
  [`mask()`](https://max578.github.io/masque/reference/mask.md). The
  HIGH-leakage finding is raised as a classed warning
  (`masque_high_leakage`) so callers can handle it programmatically.
- The package-managed writers -
  [`masque()`](https://max578.github.io/masque/reference/masque.md)’s
  `out` and
  [`write_set()`](https://max578.github.io/masque/reference/write_set.md) -
  now **refuse to write** while a HIGH finding stands: nothing is
  written, and the flagged columns are listed with the remedy. A new
  `allow_high` argument (default `FALSE`) overrides the refusal after
  the custodian’s own review; the override raises a
  `masque_high_override` warning and is recorded in the recipe’s
  warnings, so the exception stays auditable. Local mode is never gated.
- The guided completion summary is status-first: it reports the audit
  tally (HIGH / medium / low), prints a `BLOCKED` block with the next
  corrective action when HIGH findings stand, and no longer prints
  “share only the synthetic output”.
  [`print()`](https://rdrr.io/r/base/print.html) on a masque object
  shows the same tally.
- The unconditional local-mode advisory is no longer a
  [`warning()`](https://rdrr.io/r/base/warning.html). It forced callers
  (and this package’s own examples) to blanket-suppress, which is
  exactly how the HIGH warning was lost - an alarm-fatigue defect. The
  reminder is recorded on the recipe and shown by
  [`print()`](https://rdrr.io/r/base/print.html) and the guided summary
  instead. Genuine findings keep the warning channel to themselves.
- [`mask()`](https://max578.github.io/masque/reference/mask.md) now
  errors on unused `...` arguments instead of silently ignoring them, so
  a misspelled argument (e.g. `sedd = 1`) can no longer look like
  success.
- Documentation: README and the *Confidentiality model* vignette now
  describe the write gate, state plainly that
  [`save_recipe()`](https://max578.github.io/masque/reference/save_recipe.md)
  does not encrypt, that generating a synthetic table is not a release
  decision, and that `masque` contributes evidence to Safe Data / Safe
  Outputs while the remaining Five Safes are organisational.

## masque 0.7.1

### Minor improvements and fixes

- The `masque_recipe` no longer carries the
  [`detect_design()`](https://max578.github.io/masque/reference/detect_design.md)
  artefact that
  [`propose_roles()`](https://max578.github.io/masque/reference/propose_roles.md)
  stashes on the roles table (`attr(roles, "design")`, plus the
  `proposed_actions` / `mode` provenance). The recipe is contractually
  runtime-minimal, and the design object is not part of its contract; it
  inflated the saved recipe and, because its serialised size varies
  across R versions, could push
  [`save_recipe()`](https://max578.github.io/masque/reference/save_recipe.md)
  output past the documented small-file budget on R-devel. Saved recipes
  are now smaller and deterministic across toolchains. No public API or
  round-trip behaviour changes – `recipe(m)@roles` keeps every role and
  action assignment.

## masque 0.7.0

A conditional clone mode that preserves the treatment-to-outcome
relationship, so a causal model fitted on the synthetic recovers the
real treatment effect – not just the marginal distribution.

### New features

- [`mask()`](https://max578.github.io/masque/reference/mask.md),
  [`mask_set()`](https://max578.github.io/masque/reference/mask_set.md),
  and [`masque()`](https://max578.github.io/masque/reference/masque.md)
  gain a `conditional` argument (default `FALSE`). With
  `conditional = TRUE`, the numeric block is re-simulated *within each
  treatment-by-design stratum* rather than from one global Gaussian
  copula, so a row’s synthetic outcome inherits the location of the
  treatment that row carries. The treatment-to-outcome map – the
  quantity a causal model reads – survives the clone, within sampling
  tolerance. The default `conditional = FALSE` preserves the exact 0.6.0
  behaviour (global copula, marginal and structural fidelity only), so
  existing scripts are byte-identical.

  The motivation: structural and marginal fidelity alone are *not*
  sufficient for causal inference. A clone that matches every marginal
  and the global covariance can still sever the relationship between an
  arm and its response, because the outcomes are drawn from the pooled
  distribution and the treatment labels are relabelled independently. A
  model fitted on such a clone returns a null effect. Conditional
  cloning is the data-side analogue of preserving a conditional mean
  embedding rather than a pooled marginal.

### Minor improvements and fixes

- The `masque_recipe` records two new fields, `conditional` (logical)
  and `conditioning_cols` (the treatment and retained design columns the
  clone stratified on), and `print(recipe(m))` now reports the clone
  fidelity (marginal / structural versus conditional). Recipes written
  by masque 0.6.0 and earlier read back with the back-compatible
  defaults (`conditional = FALSE`, no conditioning columns).
- Strata too small to fit a stratum-local copula are pooled into a
  graceful global fallback, so a conditional clone never fails on a
  sparse design cell; with no treatment or design column to condition
  on, the path degrades cleanly to the global copula with a note.

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
