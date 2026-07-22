# API stability policy

`masque` follows a published, two-phase policy. The phase boundary is the
1.0.0 release.

## Pre-1.0 (current)

Versions `0.x.y` follow **additive-by-policy** evolution. The maintainer's
intent is that every minor release (`0.x → 0.(x+1)`) adds new exports without
breaking existing signatures. The track record so far:

- `0.2.0` — first public surface (11 exports).
- `0.3.0` — added `detect_design()`, `plot_design_summary()`, and the
  `design_summary` S7 class. `propose_roles()` gained `detect = TRUE`
  as a new default with `detect = FALSE` recovering v0.2.x behaviour
  byte-for-byte. **No breaking changes.**
- `0.4.0` — added `synthesise_geospatial()`. **No breaking changes.**
- `0.5.0` — joint-treatment masking; the `keep` role; first-class
  date/time covariates. **No breaking changes.**
- `0.6.0` — the **two-axis roles model**: the roles table gains an
  `action` column and the role vocabulary changes (`keep` / `ignore`
  become the `keep` / `drop` *actions*; new roles `date` / `id` /
  `text` / `other`). New exports: `masque()` (guided verb),
  `set_role()`, `clean_table()`, `mask_set()`, `read_set()`,
  `write_set()`. `mask()` no longer requires an `outcome`.
  **This is a breaking change, listed in `NEWS.md`.** Roles tables
  built by masque <= 0.5.0 are upgraded automatically with a one-time
  deprecation warning, so existing scripts keep working; the warning
  signposts re-running `propose_roles()`.
- `0.7.0` — added opt-in conditional numeric synthesis. **No signature
  breaks.**
- `0.8.0` — strengthened warning propagation and the package-managed write
  gate. Added `allow_high` at the end of affected signatures. **Behavioural
  safety change, listed in `NEWS.md`.**
- `0.9.1` — supersedes the untagged 0.9.0 release candidate. Added the
  append-only `env` argument to `detect_design()` and
  additive environment-scope properties to `design_summary`. Conservative
  automatic scope detection changes `propose_roles()` defaults for
  high-confidence MET environment columns. `env = FALSE` and
  `detect = FALSE` retain the former detector and name-only role paths.
  `mask()` and `mask_set()` now inherit the mode provenance recorded on role
  plans when `mode` is omitted, with an explicit warning for a downgrade.
  **Behaviour changes are listed first in `NEWS.md`.**

The policy is "additive-by-intent" rather than "frozen": pre-1.0 reserves the
right to break an existing signature when a design flaw surfaces, but every
such change must be:

1. Listed under a `## Breaking changes` heading in `NEWS.md`, first.
2. Justified in the release notes.
3. Where feasible, accompanied by a temporary back-compat shim.

If you depend on `masque` pre-1.0, pin the version in `renv.lock` or
`DESCRIPTION` (`Imports: masque (>= 0.4.0)`).

## 1.0 and after

From `1.0.0`, `masque` adopts **strict frozen-API additive evolution** —
the same policy as `glmnet` and `mgcv`:

- Signatures of exported functions never change in a backwards-incompatible
  way across major versions.
- New capability arrives via new entry points (new exports), never via
  changes to existing ones.
- If an existing function genuinely needs to be retired, it is marked with
  `lifecycle::deprecate_warn()`, kept for ≥ 2 minor versions, then promoted
  to `lifecycle::deprecate_stop()` for ≥ 1 more minor version, then removed
  in the next major release. Successors are signposted in the deprecation
  message.

This policy is chosen because `masque` is invoked from pipeline code that
the maintainer cannot edit (the whole point of the `recipe` round-trip is
that pipeline code runs unchanged against the synthetic). Silent breakage
across versions would defeat that contract.

## Versioning and tags

`masque` uses [Semantic Versioning 2.0.0](https://semver.org/). Every
release is git-tagged `vX.Y.Z` on `main`; the tag is annotated and carries
the NEWS.md entry as its message.

## Reporting an unintended break

If you discover that a `masque` release has silently broken your pipeline,
open an issue at <https://github.com/max578/masque/issues> with the version
you upgraded from and to plus a small reproducible example. Unintended
breaks at any stage are treated as bugs.
