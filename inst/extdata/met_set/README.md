# `met_set` — a two-table multi-environment-trial fixture

A small, public, multi-table example for `mask_set()`. The two CSVs are
two views of the same multi-environment soybean trial:

- `agronomy.csv` — field measurements: `env`, `loc`, `year`, `gen`,
  `yield`, `height`, `lodging`.
- `quality.csv` — laboratory measurements on the same plots: `env`,
  `gen`, `size`, `protein`, `oil`.

Both tables share the keys `env` (environment) and `gen` (genotype), so
they demonstrate cross-table-consistent aliasing: a join of the two
synthetic tables on `env` + `gen` still resolves after masking.

## Provenance

Derived from the `australia.soybean` dataset in the **agridat** R
package (Kevin Wright, MIT-licensed), itself reproducing a published
Australian soybean multi-environment trial. Redistributed here under the
package's MIT licence as a small teaching fixture; no values were
altered. See the agridat documentation (`?agridat::australia.soybean`)
for the original source and citation.
