# Audit a masque object for leakage and shareability risks

Returns a per-column audit tibble and prints a severity-grouped report.
Auto-runs in `mode = "collaborate"` at
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
  [`mask()`](https://max578.github.io/masque/reference/mask.md).

- original:

  Optional. Required when `m@audit` is NULL (typically in local mode).
  Used to recompute exact-match-pct etc. on demand.

- print:

  Logical; if TRUE (default), print a styled report.

## Value

The audit tibble, returned invisibly.

## Details

Each row of the returned tibble holds:

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

- `alias_status`: `aliased`, `passthrough`, or `dropped`.

- `notes`: short human summary.

Classification heuristics (CODEX-aligned):

- Retained PII-pattern column -\> `high`.

- Treatment unaliased in collaborate -\> `high`.

- Categorical covariate with a frequency-1 level in collaborate -\>
  `high`.

- Outcome with exact-match-pct \> 1\\

- Numeric covariate with exact-match-pct \> 5\\ `medium`.

- Ignore column retained in local -\> `low` (informational).

Step 7 will lower numeric exact-match-pct under collaborate by adding
within-resolution jitter; until then, expect `medium` leakage on
collaborate-mode numerics.

## See also

[`mask()`](https://max578.github.io/masque/reference/mask.md).

## Examples

``` r
r <- propose_roles(iris)
r$role[r$col == "Sepal.Length"] <- "outcome"
r$role[r$col == "Species"] <- "covariate"
m <- mask(iris, r, mode = "collaborate", seed = 1)
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
```
