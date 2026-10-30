# Audit a masque object for leakage and shareability risks

Returns a per-column audit data.table, with table-level checks attached,
and prints a severity-grouped report. Auto-runs in
`mode = "collaborate"` at
[`mask()`](https://max578.github.io/masque/reference/mask.md) time and
stores the result on the masque object (`m@audit`); for local-mode
audits or explicit re-audits, pass the original data frame via
`original`.

## Usage

``` r
audit_mask(m, original = NULL, print = TRUE)
```

## Arguments

- m:

  A `masque` object from
  [`mask()`](https://max578.github.io/masque/reference/mask.md), or a
  `masque_set` from
  [`mask_set()`](https://max578.github.io/masque/reference/mask_set.md).

- original:

  Optional. Required when `m@audit` is NULL (typically in local mode).
  Used to recompute exact-match-pct etc. on demand. The original data
  frame for a `masque`; for a `masque_set`, a named list holding the
  original table of every table in the set.

- print:

  Logical; if TRUE (default), print a styled report.

## Value

The audit data.table, returned invisibly. For a `masque_set`, a named
list of per-table audit data.tables, printed table by table.

## Details

Each row of the returned data.table holds:

- `col`: column name in the original.

- `role`: assigned role.

- `kind`: storage kind.

- `leakage_class`: `low`, `medium`, or `high`.

- `n_unique_levels`: distinct non-NA values (categorical only).

- `freq_min`: minimum per-level frequency (categorical only).

- `exact_match_pct`: percentage of synthetic cells equal to the original
  cell (numeric only; cell-by-cell).

- `na_pct`: percentage of NA cells in the original column.

- `na_pattern_uniqueness`: fraction of rows in the original with a
  globally unique NA pattern (one number per data frame, repeated on
  every row).

- `alias_status`: `aliased`, `permuted`, `passthrough`, or `dropped`.

- `notes`: short human summary.

- `same_row_pct`: percentage of rows where the clone value equals the
  original value in the same row, read back through the level map
  (categorical, logical, date and two-valued numeric columns).

- `baseline_pct`: the same share expected by chance, under a random
  permutation of the original column: \\100 \sum_k p_k^2\\ over its
  level frequencies (within the conditioning strata for a scrambled
  numeric column of a conditional clone).

- `excess_pct`: `same_row_pct - baseline_pct`.

The table-level checks sit in `attr(audit, "joint")`, a data.table with
one row per check (`check`, `cols`, `observed`, `baseline`, `excess`,
`sd`, `leakage_class`, `notes`). Each baseline comes from independent
permutations of the original content columns (outcomes, covariates,
dates, kept text), drawn under a fixed internal seed that leaves the
caller's random number stream untouched; design, treatment, id, aliased
text and linked columns are held fixed:

- `same_row_joint`: rows whose every content column equals the original
  row.

- `whole_row`: clone rows equal to some original row on every retained
  column.

- `rare_cross`: in the cross of visible (not aliased) categorical
  covariates and outcomes, clone cells holding one row whose combination
  is also a single row in the original.

- `unit_sizes`: a note, never graded, when design units differ in size,
  since the multiset of sizes can link a clone to a public trial list.

Classification heuristics:

- Retained PII-pattern column -\> `high`.

- Outcome with action `keep` in collaborate -\> `high`, or `medium` when
  [`mask()`](https://max578.github.io/masque/reference/mask.md) was
  called with `allow_kept_outcome = TRUE`, which the recipe records.

- Treatment unaliased in collaborate -\> `high`. A numeric treatment (a
  dose) is aliased like a categorical one.

- Categorical covariate with a frequency-1 level in collaborate -\>
  `high`.

- Outcome with exact-match-pct \> 1\\

- Numeric covariate with exact-match-pct \> 5\\ `medium`.

- Two-valued numeric columns skip the two exact-match rules: a 0/1
  column matches its own cell about half the time by chance. So do
  columns synthesised once per design unit (see `grain` in
  [`mask()`](https://max578.github.io/masque/reference/mask.md)) and
  whole-valued numeric covariates, which repeat real values by
  construction; all three are graded on `excess_pct` instead.

- Content column whose `excess_pct` is at least 10 points and four
  binomial standard deviations in collaborate -\> `medium`.

- Joint match excess of at least 20 points and four permutation standard
  deviations -\> `high` (5 points -\> `medium`); rare-cross excess of at
  least 3 cells and four standard deviations -\> `high` (1 cell and
  three -\> `medium`). In collaborate mode these verdicts raise
  `masque_high_leakage` and block package-managed writers; in local mode
  they are reported in the notes and graded `low`.

- Ignore column retained in local -\> `low` (informational).

A column constant within a design unit that was synthesised row by row
(`grain = FALSE`, or a collaborate grain with fewer than five units)
carries a note saying the clone does not keep that grain.

As a reference point, a collaborate-mode clone of
[`agridat::besag.met`](https://kwstat.github.io/agridat/reference/besag.met.html)
(yield as the outcome, design columns kept) scores `low` on every
column, and none of its yields equals the original value.

## See also

[`mask()`](https://max578.github.io/masque/reference/mask.md).

## Examples

``` r
r <- propose_roles(iris)
r$role[r$col == "Sepal.Length"] <- "outcome"
r$role[r$col == "Species"] <- "covariate"
m <- mask(iris, r, mode = "collaborate", seed = 1)
#> Re-resolved default actions for mode "collaborate" (explicit edits always win):
#> • Species: scramble -> alias
audit_mask(m)
#> 
#> ── masque audit (mode = collaborate) ───────────────────────────────────────────
#> • 0 HIGH, 0 medium, 5 low across 5 columns
#> • Rows with a globally unique NA pattern: 0.0%
#> 
#> ── LOW (5) ──
#> 
#> ℹ   outcome   Sepal.Length                      ok
#> ℹ   covariate Sepal.Width                       ok
#> ℹ   covariate Petal.Length                      ok
#> ℹ   covariate Petal.Width                       ok
#> ℹ   covariate Species                           levels aliased
#> 
#> ── Table-level checks ──
#> 
#> ℹ   LOW       same-row joint match 0.0% vs chance 0.0% (sd 0.7)
#> ℹ   LOW       whole-row match 0.0% vs chance 0.0% (sd 0.7)
```
