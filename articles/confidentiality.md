# Confidentiality and threat model

## What masque protects, and what it does not

`masque` is **not** a privacy-preserving or differential-privacy tool.
It is a **structurally faithful development surrogate**. Read this
vignette before sharing any `masque` output beyond your own machine.

### Threat model

| Actor holds | Wants to learn | What `masque` protects |
|----|----|----|
| Synthetic only | Original raw values | Numeric exact values (collaborate); treatment vocabulary (collaborate); column identities (collaborate, optional) |
| Synthetic + recipe | Original raw values | Numeric exact values. The combination is **as sensitive as the original**. |
| Recipe only | Original raw values | Nothing useful — recipe is meaningless without synthetic |
| Synthetic + external side info (e.g., publicly registered trial) | Identity of treatments / sites | Only the label vocabulary; the design footprint is preserved by design and is recognisable. Side info wins. |

**The recipe is private.** Never share the recipe alongside the
synthetic. The collaborator workflow assumes only the synthetic crosses
the trust boundary.

### What `masque` does

- Preserves enough structure for pipelines to run unchanged.
- Provides two explicit modes (`local` vs `collaborate`) so the privacy
  / fidelity trade-off is never hidden.
- Records every translation in a private recipe that round-trips a
  finished pipeline back onto the original data.
- Audits its own output via
  [`audit_mask()`](https://max578.github.io/masque/reference/audit_mask.md)
  and flags realistic leakage before sharing.

### What `masque` does not do

- It does not provide differential-privacy guarantees.
- It does not make outputs safe for public release.
- It does not anonymise rare strata, small designs, or operational
  metadata (small site x year combinations, contact names,
  geolocations).
- It does not rewrite arbitrary pipeline source code.

### Mode comparison

| Knob | `mode = "local"` | `mode = "collaborate"` |
|----|----|----|
| Treatment levels | preserved | opaque alias (`trt_001`) |
| Categorical covariate levels | preserved | opaque alias (`<col>_L001`) |
| `ignore` columns | pass-through | dropped |
| Numeric synthesis | empirical-quantile (may emit observed values) | empirical-quantile + within-resolution jitter; integers stochastically rounded |
| NA mask | preserved cell-by-cell | preserved cell-by-cell with explicit warning |
| [`audit_mask()`](https://max578.github.io/masque/reference/audit_mask.md) | on demand | automatic at [`mask()`](https://max578.github.io/masque/reference/mask.md) time |
| `print(recipe)` | full info | redacted; explicit [`reveal_maps()`](https://max578.github.io/masque/reference/reveal_maps.md) required |

### A deliberately leaky fixture

To see
[`audit_mask()`](https://max578.github.io/masque/reference/audit_mask.md)
fire, build a fixture with patterns that trip the heuristics: a
PII-pattern column the user keeps (against
[`propose_roles()`](https://max578.github.io/masque/reference/propose_roles.md)’s
default), and a categorical covariate with a frequency-1 level.

``` r

set.seed(0)
n <- 60
df <- data.frame(
  rep = rep(1:3, each = 20),
  variety = factor(rep(paste0("V", 1:6), 10)),
  contact_email = factor(rep(c("a@x", "b@y"), 30)),
  rare_treatment = factor(c(
    "only_one",
    sample(c("alpha", "beta", "gamma"), 59, replace = TRUE)
  )),
  yield = rnorm(60, 5, 1),
  stringsAsFactors = FALSE
)

roles <- propose_roles(df)
roles
#> # A tibble: 5 × 6
#>   col            role      kind    freq_or_range      pii_suspected notes                           
#>   <chr>          <chr>     <chr>   <chr>              <lgl>         <chr>                           
#> 1 rep            design    integer [1, 3]             FALSE         Design-pattern name -> design (…
#> 2 variety        treatment factor  n=6 levels         FALSE         Treatment-pattern name -> treat…
#> 3 contact_email  ignore    factor  n=2 levels         TRUE          PII pattern in column name -> i…
#> 4 rare_treatment treatment factor  n=4 levels         FALSE         Treatment-pattern name -> treat…
#> 5 yield          covariate numeric [3.19504, 7.40162] FALSE         Default -> covariate; re-role t…
```

`contact_email` was auto-flagged `pii_suspected = TRUE` and assigned to
`ignore`. We override that — pretending the user explicitly retains the
column — to see what the audit flags.

``` r

roles$role[roles$col == "yield"] <- "outcome"
roles$role[roles$col == "contact_email"] <- "covariate"
roles$role[roles$col == "rare_treatment"] <- "covariate"
roles
#> # A tibble: 5 × 6
#>   col            role      kind    freq_or_range      pii_suspected notes                           
#>   <chr>          <chr>     <chr>   <chr>              <lgl>         <chr>                           
#> 1 rep            design    integer [1, 3]             FALSE         Design-pattern name -> design (…
#> 2 variety        treatment factor  n=6 levels         FALSE         Treatment-pattern name -> treat…
#> 3 contact_email  covariate factor  n=2 levels         TRUE          PII pattern in column name -> i…
#> 4 rare_treatment covariate factor  n=4 levels         FALSE         Treatment-pattern name -> treat…
#> 5 yield          outcome   numeric [3.19504, 7.40162] FALSE         Default -> covariate; re-role t…
```

``` r

m <- mask(df, roles, mode = "collaborate", seed = 1)
#> Warning: audit_mask() flagged HIGH leakage on column(s): contact_email, rare_treatment
```

[`mask()`](https://max578.github.io/masque/reference/mask.md) printed
two warnings: one for the high-leakage PII column retained as a
covariate, one for the frequency-1 categorical level. The audit is
stored on `m@audit` (and accessible via `audit_mask(m)`):

``` r

audit_mask(m)
#> 
#> ── masque audit (mode = collaborate) ───────────────────────────────────────────────────────────────
#> • 2 HIGH, 0 medium, 3 low across 5 columns
#> • Rows with a globally unique NA pattern: 0.0%
#> 
#> ── HIGH (2) ──
#> 
#> ✖   covariate contact_email                     PII-pattern column name; levels aliased
#> ✖   covariate rare_treatment                    levels aliased; rare level (freq = 1)
#> 
#> ── LOW (3) ──
#> 
#> ℹ   design    rep                               exact-match 100.0% (jitter due step 7)
#> ℹ   treatment variety                           levels aliased
#> ℹ   outcome   yield                             ok
```

Both `contact_email` (PII retained) and `rare_treatment` (frequency-1
level) are flagged HIGH. The user gets to decide whether to share the
synthetic anyway — `masque` records the risks in `recipe@warnings`,
warns at construction time, but does not block.

### Operational guidance

1.  **Default to collaborate mode** when in doubt. Local mode is for
    owner-only development.
2.  **Treat the recipe as you treat the original data.** Same security
    class, same access controls.
3.  **Run
    [`audit_mask()`](https://max578.github.io/masque/reference/audit_mask.md)
    before any sharing.** Even when collaborate mode auto-runs it,
    re-print before handing the synthetic over.
4.  **Never override `pii_suspected = TRUE` without thinking.** The
    heuristic is conservative; if it triggers, decide explicitly whether
    to keep the column.
5.  **Small designs leak.** Cell counts of 1 in any categorical column
    under collaborate mode are HIGH leakage. Aggregate or drop before
    masking.
6.  **Exact-design preservation is recognisable.** A publicly registered
    trial design (site x year x rep) is a fingerprint. The synthetic
    does not hide that. If exact-design recognisability is a concern,
    roll up to higher-level groupings before calling
    [`mask()`](https://max578.github.io/masque/reference/mask.md).

For internals of the recipe object — what it stores, what it doesn’t,
how [`print()`](https://rdrr.io/r/base/print.html) redacts — see
[`vignette("recipe_anatomy")`](https://max578.github.io/masque/articles/recipe_anatomy.md).
