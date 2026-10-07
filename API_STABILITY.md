# API stability policy

`masque` follows a published, two-phase policy. The phase boundary is
the 1.0.0 release.

## Pre-1.0 (current)

Versions `0.x.y` follow an **additive-by-intent** policy: every minor
release (`0.x` to `0.(x+1)`) is meant to add new exports without
breaking existing signatures. The track record so far:

- `0.2.0`: first public surface (11 exports).
- `0.3.0`: added
  [`detect_design()`](https://max578.github.io/masque/reference/detect_design.md),
  [`plot_design_summary()`](https://max578.github.io/masque/reference/plot_design_summary.md),
  and the `design_summary` S7 class.
  [`propose_roles()`](https://max578.github.io/masque/reference/propose_roles.md)
  gained `detect = TRUE` as a new default with `detect = FALSE`
  recovering v0.2.x behaviour byte-for-byte. **No breaking changes.**
- `0.4.0`: added
  [`synthesise_geospatial()`](https://max578.github.io/masque/reference/synthesise_geospatial.md).
  **No breaking changes.**
- `0.5.0`: joint-treatment masking; the `keep` role; first-class
  date/time covariates. **No breaking changes.**
- `0.6.0`: the **two-axis roles model**: the roles table gains an
  `action` column and the role vocabulary changes (`keep` / `ignore`
  become the `keep` / `drop` *actions*; new roles `date` / `id` / `text`
  / `other`). New exports:
  [`masque()`](https://max578.github.io/masque/reference/masque.md)
  (guided verb),
  [`set_role()`](https://max578.github.io/masque/reference/set_role.md),
  [`clean_table()`](https://max578.github.io/masque/reference/clean_table.md),
  [`mask_set()`](https://max578.github.io/masque/reference/mask_set.md),
  [`read_set()`](https://max578.github.io/masque/reference/read_set.md),
  [`write_set()`](https://max578.github.io/masque/reference/write_set.md).
  [`mask()`](https://max578.github.io/masque/reference/mask.md) no
  longer requires an `outcome`. **This is a breaking change, listed in
  `NEWS.md`.** Roles tables built by masque \<= 0.5.0 are upgraded
  automatically with a one-time deprecation warning, so existing scripts
  keep working; the warning signposts re-running
  [`propose_roles()`](https://max578.github.io/masque/reference/propose_roles.md).
- `0.7.0`: added opt-in conditional numeric synthesis. **No signature
  breaks.**
- `0.8.0`: strengthened warning propagation and the package-managed
  write gate. Added `allow_high` at the end of affected signatures.
  **Behavioural safety change, listed in `NEWS.md`.**
- `0.9.1`: supersedes the untagged 0.9.0 release candidate. Added the
  append-only `env` argument to
  [`detect_design()`](https://max578.github.io/masque/reference/detect_design.md)
  and additive environment-scope properties to `design_summary`.
  Conservative automatic scope detection changes
  [`propose_roles()`](https://max578.github.io/masque/reference/propose_roles.md)
  defaults for high-confidence MET environment columns. `env = FALSE`
  and `detect = FALSE` retain the former detector and name-only role
  paths. [`mask()`](https://max578.github.io/masque/reference/mask.md)
  and
  [`mask_set()`](https://max578.github.io/masque/reference/mask_set.md)
  now inherit the mode provenance recorded on role plans when `mode` is
  omitted, with an explicit warning for a downgrade. **Behaviour changes
  are listed first in `NEWS.md`.**
- `0.9.2`: added
  [`jitter_coordinates()`](https://max578.github.io/masque/reference/jitter_coordinates.md)
  and the [`mask()`](https://max578.github.io/masque/reference/mask.md)
  `coords` argument. **No breaking changes.**
- `0.10.0`: the geomask now draws one displacement per **site** rather
  than per row, and a site that cannot be placed on land fails closed to
  `NA` instead of retaining its true coordinate.
  [`jitter_coordinates()`](https://max578.github.io/masque/reference/jitter_coordinates.md)
  gains `by` (appended after `lon_col`), and a coordinate spec passed to
  `mask(coords = )` accepts `by`. `by = FALSE` recovers the pre-0.10.0
  per-row behaviour, and genuinely point-level input reproduces its
  0.9.2 output exactly under the same seed. **This is a behaviour change
  and a confidentiality fix, listed first in `NEWS.md`.**
- `0.11.0`: a coordinate column kept unmasked now stops
  [`mask()`](https://max578.github.io/masque/reference/mask.md) unless
  the caller states otherwise, via `coords`, a masking action, or the
  new `allow_unmasked_coords` argument (appended, default `FALSE`).
  Value-shaped coordinate detection warns rather than stops.
  [`audit_mask()`](https://max578.github.io/masque/reference/audit_mask.md)
  no longer classes a geomask-coarsened coordinate as HIGH. **Behaviour
  change, listed first in `NEWS.md`.**
- `0.12.0`: added
  [`conform_table()`](https://max578.github.io/masque/reference/conform_table.md).
  The collaborate-mode alias map is drawn from a seeded random
  permutation instead of the sort order, which changes the integer codes
  of an aliased factor. `conditional = TRUE` coarsens its strata until
  they are large enough, instead of pooling the whole clone silently.
  **Behaviour change and a confidentiality fix, listed in `NEWS.md`.**
- `0.13.0`:
  [`mask()`](https://max578.github.io/masque/reference/mask.md),
  [`mask_set()`](https://max578.github.io/masque/reference/mask_set.md)
  and [`masque()`](https://max578.github.io/masque/reference/masque.md)
  gain `ladder` (appended). The new default, `"hierarchy"`, coarsens a
  conditional clone along the design hierarchy; `ladder = "levels"`
  reproduces 0.11.1 to 0.12.0. **Breaking change, listed first in
  `NEWS.md`.**
- `0.14.0`: a scrambled factor keeps the original level order, and an
  aliased join key lists its aliases in sorted order, so
  [`levels()`](https://rdrr.io/r/base/levels.html) of a clone no longer
  reveals its label map. Values under the same seed are unchanged.
  [`apply_recipe()`](https://max578.github.io/masque/reference/apply_recipe.md)
  returns the clone’s level order. **Confidentiality fix, listed first
  in `NEWS.md`; re-make any clone shared from 0.13.0 or earlier.**

Additive by intent is not frozen: before 1.0 a release may break an
existing signature when a design flaw surfaces, but every such change
must be:

1.  Listed under a `## Breaking changes` heading in `NEWS.md`, first.
2.  Justified in the release notes.
3.  Where feasible, accompanied by a temporary back-compat shim.

If you depend on `masque` before 1.0, set a version floor in
`DESCRIPTION` (`Imports: masque (>= 0.14.0)`) and record the exact
version with `renv` (`renv::snapshot()`).

## 1.0 and after

From `1.0.0`, `masque` adopts a **frozen API**:

- Signatures of exported functions never change in a
  backwards-incompatible way within a major version.
- New capability arrives via new entry points (new exports), never via
  changes to existing ones.
- If an existing function genuinely needs to be retired, it is marked
  with
  [`lifecycle::deprecate_warn()`](https://lifecycle.r-lib.org/reference/deprecate_soft.html),
  kept for at least 2 minor versions, then promoted to
  [`lifecycle::deprecate_stop()`](https://lifecycle.r-lib.org/reference/deprecate_soft.html)
  for at least 1 more minor version, then removed in the next major
  release. Successors are signposted in the deprecation message.

Pipeline code written against a clone is later run unchanged on the real
data, so it has to keep working when `masque` is upgraded.

## Versioning and tags

`masque` uses [Semantic Versioning 2.0.0](https://semver.org/). Every
release is git-tagged `vX.Y.Z` on `main`; the tag is annotated and
carries the NEWS.md entry as its message.

## Reporting an unintended break

If you discover that a `masque` release has silently broken your
pipeline, open an issue at <https://github.com/max578/masque/issues>
with the version you upgraded from and to plus a small reproducible
example. Unintended breaks at any stage are treated as bugs.
