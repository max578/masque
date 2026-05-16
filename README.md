# masque

> Structurally faithful development surrogates for tabular data.

`masque` turns a single tabular dataset into a synthetic clone whose
experimental design, NA pattern, and global covariance structure are close
enough to the original that pipeline code runs unchanged. It keeps a private
`recipe` object that round-trips: a pipeline built against the synthetic clone
can be re-targeted to the original data.

The package is in early development (v0.2.0.9000). No public API has been
released yet.

---

## Threat model

`masque` is **not** a privacy-preserving or differential-privacy tool. It is a
**structurally faithful development surrogate** with explicit confidentiality
guardrails. Read this section before using.

**What `masque` does**

- Preserves enough structure for pipelines to run unchanged.
- Provides two explicit modes: `local` for owner-only realistic surrogates, and
  `collaborate` for controlled sharing with opaque aliasing and an automatic
  leakage audit.
- Records every translation (column names, factor levels) in a private
  `recipe` object that is, at minimum, as sensitive as the original data.
- Audits its own output and flags realistic leakage risks before sharing.

**What `masque` does not do**

- It does not provide differential-privacy guarantees.
- It does not make outputs safe for public release.
- It does not anonymise rare strata, small designs, or operational metadata
  (small site x year combinations, contact names, geolocations).
- It does not rewrite arbitrary pipeline source code.

**Bottom line.** The recipe is at least as sensitive as the original. Never
share the recipe and the synthetic data together. The synthetic-with-
collaborator workflow assumes only the synthetic crosses the trust boundary.

For the full threat model see
`vignette("confidentiality", package = "masque")` (planned).

---

## Installation

Not yet on CRAN. Development version:

```r
# pak::pak("max578/masque")  # planned
```

---

## Status

This README, and the package, are scaffolding. The CODEX-consolidated
implementation plan lives at `plan/masque_v0.2_plan.md` in the development
workspace. See `NEWS.md` for what has and has not landed.

---

## License

MIT. See `LICENSE` and `LICENSE.md`.
