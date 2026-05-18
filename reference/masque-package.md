# masque: Structurally Faithful Development Surrogates for Tabular Data

`masque` turns a single tabular dataset into a structurally faithful
synthetic clone suitable for pipeline development. Experimental-design
columns and the NA pattern are preserved exactly; treatment and
categorical-covariate level vocabularies are optionally aliased; outcome
and numeric-covariate values are re-simulated via a Gaussian copula that
preserves the global covariance structure. A private `recipe` object
round-trips a pipeline written against the synthetic clone onto the
original data.

## Honest claim

`masque` is **not** a differential-privacy or anonymisation tool. Its
outputs are development surrogates: structurally faithful enough that
pipeline code runs unchanged, controlled enough that raw values are not
exposed in collaborate mode. See
[`vignette("confidentiality", package = "masque")`](https://max578.github.io/masque/articles/confidentiality.md)
for the full threat model and limitations.

## Two modes

- `mode = "local"`: owner's realistic dev surrogate; preserves names and
  level vocabularies; may emit observed values; not for external
  sharing.

- `mode = "collaborate"`: opaque aliasing for treatment and
  categorical-covariate levels; within-resolution jitter on numerics;
  integers stochastically rounded;
  [`audit_mask()`](https://max578.github.io/masque/reference/audit_mask.md)
  auto-runs at construction.

## See also

Useful links:

- <https://github.com/max578/masque>

- Report bugs at <https://github.com/max578/masque/issues>

## Author

**Maintainer**: Max Moldovan <max.moldovan@gmail.com>
([ORCID](https://orcid.org/0000-0001-9680-8474)) (Adelaide University)
