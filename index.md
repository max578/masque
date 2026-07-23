# masque

> Structurally faithful development surrogates for tabular data.

`masque` turns a confidential tabular dataset – a single table, a folder
of files, or a multi-sheet workbook – into a structurally faithful
synthetic clone whose experimental design, NA pattern, and global
covariance are close enough to the original that pipeline code runs
unchanged. It returns a private `recipe` that round-trips: a pipeline
written against the synthetic re-targets to the original data with no
source changes.

The custodian holds the data and the recipe; the analyst gets only the
synthetic. `masque` bridges that gap.

Version 0.9.1 (development). Pre-CRAN; tagged releases on the GitHub
repository.

------------------------------------------------------------------------

## Installation

From GitHub:

``` r

# install.packages("pak")
pak::pak("max578/masque")
```

A companion r-universe distribution will provide pre-built binaries once
the registry is live:

``` r

install.packages("masque", repos = "https://max578.r-universe.dev")
```

CRAN submission is in preparation.

------------------------------------------------------------------------

## Two-minute example

``` r

library(masque)

# Read a small public fixture (alpha-design field trial; John & Williams, 1995).
f  <- system.file("extdata", "john_alpha.csv", package = "masque")
df <- read.csv(f, stringsAsFactors = TRUE)

# One guided call: read -> propose roles -> (review) -> mask -> audit.
# In an interactive session it pauses to let you review the plan.
m <- masque(df, mode = "collaborate", seed = 1L)

synth <- synthetic(m)   # hand this to the analyst
rec   <- recipe(m)      # keep this private

# Analyst builds a pipeline against the synthetic namespace ...
fit <- lm(yield ~ gen + rep, data = synth)

# ... and the custodian re-targets it to the original data.
preds <- predict(fit, newdata = apply_recipe(df, rec))
```

A folder of files or a multi-sheet workbook works the same way – pass
the path to
[`masque()`](https://max578.github.io/masque/reference/masque.md) and it
masks every table at once, aliasing shared keys consistently so the
synthetic tables still join.

See
[`vignette("getting_started", package = "masque")`](https://max578.github.io/masque/articles/getting_started.md)
for the full walk-through.

### Multi-environment trials

[`detect_design()`](https://max578.github.io/masque/reference/detect_design.md)
treats environment scope, treatment connectivity, and within-environment
design as separate questions. It conservatively recognises explicit
environment columns and common site-year structures, while uncertain or
competing candidates remain unresolved.
[`propose_roles()`](https://max578.github.io/masque/reference/propose_roles.md)
protects only high-confidence environment allocations automatically:
local mode keeps the values, while collaborate mode aliases categorical
environment labels without moving observations between environments.
Numeric environment labels remain visible and raise a disclosure warning
for review.

Preserving allocation structure does not preserve
genotype-by-environment effects in synthesised outcomes. The clone
remains a pipeline-development surrogate, not a substitute dataset for
scientific inference.

------------------------------------------------------------------------

## Threat model

`masque` is **not** a privacy-preserving or differential-privacy tool.
It is a **structurally faithful development surrogate** with explicit
confidentiality guardrails. Read
[`vignette("confidentiality", package = "masque")`](https://max578.github.io/masque/articles/confidentiality.md)
before using.

**What `masque` does**

- Preserves enough structure for pipelines to run unchanged.
- Provides two explicit modes: `local` for owner-only realistic
  surrogates, and `collaborate` for controlled sharing with opaque
  aliasing, numeric jitter, and an automatic leakage audit.
- Preserves the treatment-to-outcome relationship on request
  (`conditional = TRUE`), so a causal model fitted on the clone recovers
  the real treatment effect, not just the marginal distribution.
- Records every translation (column names, factor levels) in a private
  `recipe` object that is, at minimum, as sensitive as the original
  data.
- Audits its own output
  ([`audit_mask()`](https://max578.github.io/masque/reference/audit_mask.md)),
  raises HIGH findings as classed warnings the guided flow never
  silences, and refuses package-managed writes while a HIGH finding
  stands (an explicit `allow_high = TRUE` override is available, warned
  and recorded in the recipe).

**What `masque` does not do**

- It is not a universal anonymiser, and it does not provide
  differential-privacy guarantees.
- It does not make outputs safe for public release.
- It does not anonymise rare strata, small designs, or operational
  metadata (small site-by-year combinations, contact names,
  geolocations).
- It does not certify compliance with any privacy, health, banking, or
  research-governance obligation. It can contribute evidence to such a
  decision; the decision itself is organisational and legal.
- It does not rewrite arbitrary pipeline source code.

**Bottom line.** Generating a synthetic table is not a release decision.
In Five Safes terms, `masque` contributes to *Safe Data* and *Safe
Outputs*; Safe People, Safe Projects, and Safe Settings are governance
questions no package can answer. The recipe is at least as sensitive as
the original. Never share the recipe and the synthetic together. The
collaborate workflow assumes only the synthetic crosses the trust
boundary.

------------------------------------------------------------------------

## Documentation

- [`vignette("getting_started")`](https://max578.github.io/masque/articles/getting_started.md)
  — the one-call path on a public fixture.
- [`vignette("confidentiality")`](https://max578.github.io/masque/articles/confidentiality.md)
  — full threat model, the two modes, and the depth controls.
- [`vignette("recipe_anatomy")`](https://max578.github.io/masque/articles/recipe_anatomy.md)
  — what a recipe holds and how the round-trip re-targets a pipeline
  onto the original.

Reference index: <https://max578.github.io/masque/> — full per-function
docs + rendered vignettes, deployed from the `gh-pages` branch.

API stability policy: see `API_STABILITY.md`.

------------------------------------------------------------------------

## Citation

``` r

citation("masque")
```

The package also ships a `CITATION.cff` file; GitHub renders a “Cite
this repository” widget on the repo landing page.

------------------------------------------------------------------------

## License

MIT. See `LICENSE` and `LICENSE.md`.
