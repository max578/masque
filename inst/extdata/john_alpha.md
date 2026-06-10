# `john_alpha.csv` — attribution

This CSV is a verbatim copy of `agridat::john.alpha`, a classical
alpha-design field trial. It is included in `masque` as a small,
public, licence-clean fixture for examples and vignettes. The source
documented by `agridat` for this dataset is:

> John, J. A., & Williams, E. R. (1995). *Cyclic and Computer Generated
> Designs* (page 146). London: Chapman and Hall.

Re-distributed in the `agridat` R package (Wright, K.). `agridat`'s
collection of agricultural datasets covers historical field trials
documented in textbooks and peer-reviewed publications; the underlying
datasets are primary-literature public reference, included with the
agridat package under GPL.

This CSV ships under masque's MIT licence as a derivative work that
re-formats but does not modify the values. Attribution chain:

- Primary reference: John & Williams (1995), as cited in `?agridat::john.alpha`.
- Re-distribution package: agridat (`agridat::john.alpha`).
- This copy: extracted via `agridat::john.alpha` and written via
  `write.csv()` on 2026-05-16.

## Schema

72 rows x 7 columns from an alpha-design trial:

| Column | Type     | Meaning                              |
|--------|----------|--------------------------------------|
| plot   | integer  | Plot index                           |
| rep    | factor   | Replicate label (R1, R2, R3)         |
| block  | factor   | Block within rep (B1-B6 per rep)     |
| gen    | factor   | Genotype label (G01-G24)             |
| yield  | numeric  | Grain yield (t/ha)                   |
| row    | integer  | Spatial row                          |
| col    | integer  | Spatial column                       |
