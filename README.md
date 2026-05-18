# masque

> Structurally faithful development surrogates for tabular data.

`masque` turns one tabular dataset into a synthetic clone whose experimental
design, NA pattern, and global covariance structure are close enough to the
original that pipeline code runs unchanged. It returns a private `recipe`
object that round-trips: a pipeline written against the synthetic can be
re-targeted to the original data with no source changes.

Version 0.4.0. Pre-CRAN; tagged releases on the GitHub repository.

---

## Installation

Once the repository is public:

```r
# install.packages("pak")
pak::pak("max578/masque")
```

A companion r-universe distribution will provide pre-built binaries:

```r
install.packages("masque", repos = "https://max578.r-universe.dev")
```

CRAN submission is in preparation.

---

## Two-minute example

```r
library(masque)

# 1. Read a small public fixture (alpha-design field trial; John, 1987).
f  <- system.file("extdata", "john_alpha.csv", package = "masque")
df <- read.csv(f, stringsAsFactors = TRUE)

# 2. Heuristic role classification; the user edits before passing to mask().
roles <- propose_roles(df)
roles$role[roles$col == "yield"] <- "outcome"

# 3. Mask in collaborate mode: opaque level aliases, numeric jitter,
#    ignore columns dropped, audit_mask() auto-run.
m     <- mask(df, roles, mode = "collaborate", seed = 1L)
synth <- synthetic(m)
rec   <- recipe(m)

# 4. Build a pipeline against the synthetic namespace.
fit <- lm(yield ~ gen + rep, data = synth)

# 5. Translate the original into the synthetic namespace and predict.
df_in_synth <- apply_recipe(df, rec)
preds       <- predict(fit, newdata = df_in_synth)
```

See `vignette("getting_started", package = "masque")` for the full walk-through
and `vignette("design_detection", package = "masque")` for the experimental-
design detector that drives `propose_roles()`.

---

## Threat model

`masque` is **not** a privacy-preserving or differential-privacy tool. It is a
**structurally faithful development surrogate** with explicit confidentiality
guardrails. Read `vignette("confidentiality", package = "masque")` before
using.

**What `masque` does**

- Preserves enough structure for pipelines to run unchanged.
- Provides two explicit modes: `local` for owner-only realistic surrogates,
  and `collaborate` for controlled sharing with opaque aliasing, numeric
  jitter, and an automatic leakage audit.
- Records every translation (column names, factor levels) in a private
  `recipe` object that is, at minimum, as sensitive as the original data.
- Audits its own output (`audit_mask()`) and flags realistic leakage risks
  before sharing.

**What `masque` does not do**

- It does not provide differential-privacy guarantees.
- It does not make outputs safe for public release.
- It does not anonymise rare strata, small designs, or operational metadata
  (small site x year combinations, contact names, geolocations).
- It does not rewrite arbitrary pipeline source code.

**Bottom line.** The recipe is at least as sensitive as the original. Never
share the recipe and the synthetic together. The collaborate workflow assumes
only the synthetic crosses the trust boundary.

---

## Documentation

- `vignette("getting_started")` — five-step worked example on a public fixture.
- `vignette("confidentiality")` — full threat model and mode comparison.
- `vignette("design_detection")` — the rule-engine design detector.
- `vignette("recipe_anatomy")` — what a recipe holds, runtime-minimal vs full,
  redacted print versus `reveal_maps()`.
- `vignette("roadmap")` — what is deferred from v0.4 and why.

Reference index: [https://max578.github.io/masque/](https://max578.github.io/masque/)
(deploys once the repository is public).

API stability policy: see `API_STABILITY.md`.

---

## Citation

```r
citation("masque")
```

The package also ships a `CITATION.cff` file; GitHub renders a "Cite this
repository" widget once the repository is public.

---

## License

MIT. See `LICENSE` and `LICENSE.md`.
