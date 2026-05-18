# Getting started with masque

## masque: development surrogates for tabular data

`masque` turns a single tabular dataset into a structurally faithful
synthetic clone you can develop a pipeline against. It preserves the
experimental design, the NA pattern, and the global covariance of your
outcome and numeric covariates. It does **not** anonymise; it produces
controlled substitutes with a private `recipe` that round-trips the
finished pipeline back onto the original data.

### Read this first: threat model

`masque` is *not* a privacy-preserving or differential-privacy tool. It
is a **structurally faithful development surrogate**. The recipe
returned by
[`mask()`](https://max578.github.io/masque/reference/mask.md) is at
least as sensitive as the original data: never share it alongside the
synthetic.

| Mode | Use case | Defaults |
|----|----|----|
| `local` | Owner develops on a realistic surrogate locally | Vocabulary preserved; numeric values may match observed |
| `collaborate` | Owner shares synthetic with a collaborator while keeping the recipe private | Opaque aliasing of treatment + categorical-covariate levels; jitter on numerics; ignore columns dropped; [`audit_mask()`](https://max578.github.io/masque/reference/audit_mask.md) auto-runs |

For the full threat model and limitations, see
[`vignette("confidentiality")`](https://max578.github.io/masque/articles/confidentiality.md).

### A worked example: an alpha-design field trial

We use the classical John (1987) alpha-design dataset, shipped as a
small CSV in `inst/extdata/`.

``` r

library(masque)

f  <- system.file("extdata", "john_alpha.csv", package = "masque")
df <- read.csv(f, stringsAsFactors = TRUE)
str(df)
#> 'data.frame':    72 obs. of  7 variables:
#>  $ plot : int  1 2 3 4 5 6 7 8 9 10 ...
#>  $ rep  : Factor w/ 3 levels "R1","R2","R3": 1 1 1 1 1 1 1 1 1 1 ...
#>  $ block: Factor w/ 6 levels "B1","B2","B3",..: 1 1 1 1 2 2 2 2 3 3 ...
#>  $ gen  : Factor w/ 24 levels "G01","G02","G03",..: 11 4 5 22 21 10 20 2 23 14 ...
#>  $ yield: num  4.12 4.45 5.88 4.58 4.65 ...
#>  $ row  : int  1 2 3 4 5 6 7 8 9 10 ...
#>  $ col  : int  1 1 1 1 1 1 1 1 1 1 ...
head(df)
#>   plot rep block gen  yield row col
#> 1    1  R1    B1 G11 4.1172   1   1
#> 2    2  R1    B1 G04 4.4461   2   1
#> 3    3  R1    B1 G05 5.8757   3   1
#> 4    4  R1    B1 G22 4.5784   4   1
#> 5    5  R1    B2 G21 4.6540   5   1
#> 6    6  R1    B2 G10 4.1736   6   1
```

### Step 1: propose roles, edit, validate

[`propose_roles()`](https://max578.github.io/masque/reference/propose_roles.md)
runs a heuristic classification of every column into one of
`{design, treatment, outcome, covariate, ignore}`. The result is a
tibble that you inspect and edit.

``` r

roles <- propose_roles(df)
roles
#> # A tibble: 7 × 6
#>   col   role      kind    freq_or_range    pii_suspected notes                                      
#>   <chr> <chr>     <chr>   <chr>            <lgl>         <chr>                                      
#> 1 plot  design    integer [1, 72]          FALSE         Design-pattern name -> design (byte-identi…
#> 2 rep   design    factor  n=3 levels       FALSE         Design-pattern name -> design (byte-identi…
#> 3 block design    factor  n=6 levels       FALSE         Design-pattern name -> design (byte-identi…
#> 4 gen   treatment factor  n=24 levels      FALSE         detect_design: covariate -> treatment (was…
#> 5 yield covariate numeric [2.8873, 5.8757] FALSE         Default -> covariate; re-role to outcome i…
#> 6 row   design    integer [1, 72]          FALSE         Design-pattern name -> design (byte-identi…
#> 7 col   design    integer [1, 1]           FALSE         Design-pattern name -> design (byte-identi…
```

`plot`, `rep`, `block`, `row`, and `col` are detected as design columns
(byte-identical pass-through). `gen` is detected as a treatment factor.
`yield` defaults to `covariate` — we re-role it as `outcome`.

``` r

roles$role[roles$col == "yield"] <- "outcome"
roles
#> # A tibble: 7 × 6
#>   col   role      kind    freq_or_range    pii_suspected notes                                      
#>   <chr> <chr>     <chr>   <chr>            <lgl>         <chr>                                      
#> 1 plot  design    integer [1, 72]          FALSE         Design-pattern name -> design (byte-identi…
#> 2 rep   design    factor  n=3 levels       FALSE         Design-pattern name -> design (byte-identi…
#> 3 block design    factor  n=6 levels       FALSE         Design-pattern name -> design (byte-identi…
#> 4 gen   treatment factor  n=24 levels      FALSE         detect_design: covariate -> treatment (was…
#> 5 yield outcome   numeric [2.8873, 5.8757] FALSE         Default -> covariate; re-role to outcome i…
#> 6 row   design    integer [1, 72]          FALSE         Design-pattern name -> design (byte-identi…
#> 7 col   design    integer [1, 1]           FALSE         Design-pattern name -> design (byte-identi…
```

Validation is a single call:

``` r

roles_validate(roles, df)
```

### Step 2: mask in local mode

Local mode is the owner’s realistic surrogate: it preserves the
treatment vocabulary, the design pattern, and the NA mask. The synthetic
is suitable for pipeline development on the owner’s machine but not for
external sharing.

``` r

m_local <- mask(df, roles, mode = "local", seed = 2026)
#> Warning: local mode: synthetic data is for owner development only, not external sharing.
```

The construction-time warning is part of the contract — local-mode
synthetic is not for external sharing.

``` r

m_local
#> 
#> ── masque ──────────────────────────────────────────────────────────────────────────────────────────
#> • Mode: local
#> • Synthetic: 72 row(s) x 7 column(s)
#> • Audit: not run (use audit_mask())
#> ! local mode: synthetic data is for owner development only, not external sharing.
#> Use `synthetic(m)` to extract data; `recipe(m)` for the recipe.
#> 
#> ── masque_recipe ───────────────────────────────────────────────────────────────────────────────────
#> • Created: 2026-05-18 11:53:16 ACST
#> • Mode: local
#> • Seed: present (redacted)
#> • masque version: 0.4.1
#> • Integrity fingerprint: 0cec319ba9e2...
#> 
#> ── Columns (7 total; 0 level-map(s); 0 column-name map(s)) ──
#> 
#>   = design     plot                              (integer)
#>   = design     rep                               (factor)
#>   = design     block                             (factor)
#>   = treatment  gen                               (factor)
#>   = outcome    yield                             (numeric)
#>   = design     row                               (integer)
#>   = design     col                               (integer)
#> ── Warnings ──
#> ! local mode: synthetic data is for owner development only, not external sharing.
#> 
#> ✖ PRIVATE - never share this recipe alongside the synthetic.
#> Use `reveal_maps(rec)` to inspect level maps explicitly.
```

Extract the synthetic data via
[`synthetic()`](https://max578.github.io/masque/reference/synthetic.md):

``` r

synth_local <- synthetic(m_local)
head(synth_local)
#> # A tibble: 6 × 7
#>    plot rep   block gen   yield   row   col
#>   <int> <fct> <fct> <fct> <dbl> <int> <int>
#> 1     1 R1    B1    G11    4.79     1     1
#> 2     2 R1    B1    G04    4.56     2     1
#> 3     3 R1    B1    G05    3.90     3     1
#> 4     4 R1    B1    G22    4.17     4     1
#> 5     5 R1    B2    G21    4.53     5     1
#> 6     6 R1    B2    G10    3.14     6     1
```

Design columns are byte-identical to the original; treatment labels are
preserved.

``` r

identical(synth_local$rep,   df$rep)
#> [1] TRUE
identical(synth_local$block, df$block)
#> [1] TRUE
identical(levels(synth_local$gen), levels(df$gen))
#> [1] TRUE
```

### Step 3: mask in collaborate mode

Collaborate mode opaquely aliases the treatment and categorical-
covariate vocabularies (`G01 -> trt_001` etc.), drops `ignore` columns,
jitters numerics within their observed measurement resolution, and
auto-runs
[`audit_mask()`](https://max578.github.io/masque/reference/audit_mask.md).
The synthetic is suitable for handing to a pipeline developer while the
recipe stays private.

``` r

m_collab <- mask(df, roles, mode = "collaborate", seed = 2026)
synth_collab <- synthetic(m_collab)
head(synth_collab)
#> # A tibble: 6 × 7
#>    plot rep   block gen     yield   row   col
#>   <int> <fct> <fct> <fct>   <dbl> <int> <int>
#> 1     1 R1    B1    trt_011  4.79     1     1
#> 2     2 R1    B1    trt_004  4.56     2     1
#> 3     3 R1    B1    trt_005  3.90     3     1
#> 4     4 R1    B1    trt_022  4.17     4     1
#> 5     5 R1    B2    trt_021  4.53     5     1
#> 6     6 R1    B2    trt_010  3.14     6     1
```

Note `gen` is now `trt_NNN`:

``` r

head(levels(synth_collab$gen))
#> [1] "trt_001" "trt_002" "trt_003" "trt_004" "trt_005" "trt_006"
```

Original labels never leak through `print(recipe(m))`:

``` r

recipe(m_collab)
#> 
#> ── masque_recipe ───────────────────────────────────────────────────────────────────────────────────
#> • Created: 2026-05-18 11:53:16 ACST
#> • Mode: collaborate
#> • Seed: present (redacted)
#> • masque version: 0.4.1
#> • Integrity fingerprint: 0cec319ba9e2...
#> 
#> ── Columns (7 total; 1 level-map(s); 0 column-name map(s)) ──
#> 
#>   = design     plot                              (integer)
#>   = design     rep                               (factor)
#>   = design     block                             (factor)
#>   * treatment  gen                               (factor)
#>   = outcome    yield                             (numeric)
#>   = design     row                               (integer)
#>   = design     col                               (integer)
#> 
#> ✖ PRIVATE - never share this recipe alongside the synthetic.
#> Use `reveal_maps(rec)` to inspect level maps explicitly.
```

To see them you must call
[`reveal_maps()`](https://max578.github.io/masque/reference/reveal_maps.md)
explicitly.

### Step 4: round-trip a pipeline

The classic `masque` workflow:

``` r

# Train a model against the synthetic namespace
fit <- lm(yield ~ gen + rep, data = synth_collab)

# Translate the original into the synthetic namespace via the recipe
df_in_synth <- apply_recipe(df, recipe(m_collab))
head(df_in_synth)
#> # A tibble: 6 × 7
#>    plot rep   block gen     yield   row   col
#>   <int> <fct> <fct> <fct>   <dbl> <int> <int>
#> 1     1 R1    B1    trt_011  4.12     1     1
#> 2     2 R1    B1    trt_004  4.45     2     1
#> 3     3 R1    B1    trt_005  5.88     3     1
#> 4     4 R1    B1    trt_022  4.58     4     1
#> 5     5 R1    B2    trt_021  4.65     5     1
#> 6     6 R1    B2    trt_010  4.17     6     1

# Predict on the translated data
preds_synth <- predict(fit, newdata = df_in_synth)
length(preds_synth)
#> [1] 72

# Numeric predictions need no inverse map
head(preds_synth)
#>        1        2        3        4        5        6 
#> 3.920561 4.408952 4.010521 3.833775 4.280694 4.027520
```

If the pipeline returned factor-valued predictions (e.g., a classifier
predicting a treatment),
[`unmask()`](https://max578.github.io/masque/reference/unmask.md)
translates them back into the original vocabulary:

``` r

pred_factor_synth <- synth_collab$gen[1:5]
pred_factor_orig  <- unmask(pred_factor_synth, recipe(m_collab),
                            column = "gen")
data.frame(synth = as.character(pred_factor_synth),
           original = as.character(pred_factor_orig))
#>     synth original
#> 1 trt_011      G11
#> 2 trt_004      G04
#> 3 trt_005      G05
#> 4 trt_022      G22
#> 5 trt_021      G21
```

### Step 5: audit and ship

[`audit_mask()`](https://max578.github.io/masque/reference/audit_mask.md)
returns a per-column leakage audit. In collaborate mode it runs
automatically at
[`mask()`](https://max578.github.io/masque/reference/mask.md) time and
is stored on the object.

``` r

audit_mask(m_collab)
#> 
#> ── masque audit (mode = collaborate) ───────────────────────────────────────────────────────────────
#> • 0 HIGH, 0 medium, 7 low across 7 columns
#> • Rows with a globally unique NA pattern: 0.0%
#> 
#> ── LOW (7) ──
#> 
#> ℹ   design    plot                              exact-match 100.0% (jitter due step 7)
#> ℹ   design    rep                               ok
#> ℹ   design    block                             ok
#> ℹ   treatment gen                               levels aliased
#> ℹ   outcome   yield                             ok
#> ℹ   design    row                               exact-match 100.0% (jitter due step 7)
#> ℹ   design    col                               exact-match 100.0% (jitter due step 7)
```

The recipe can be persisted alongside the original data (treat as
sensitive); the synthetic alone is what crosses the trust boundary.

``` r

tmp <- tempfile(fileext = ".rds")
save_recipe(recipe(m_collab), tmp)
file.info(tmp)$size
#> [1] 6811
rec2 <- read_recipe(tmp)
identical(rec2@masque_version, recipe(m_collab)@masque_version)
#> [1] TRUE
```

### Next steps

- [`vignette("confidentiality")`](https://max578.github.io/masque/articles/confidentiality.md)
  — the full threat model, mode comparison, and
  [`audit_mask()`](https://max578.github.io/masque/reference/audit_mask.md)
  walk-through with deliberately leaky fixtures.
- [`vignette("recipe_anatomy")`](https://max578.github.io/masque/articles/recipe_anatomy.md)
  — what’s inside a recipe, runtime vs full,
  [`print()`](https://rdrr.io/r/base/print.html) vs
  [`reveal_maps()`](https://max578.github.io/masque/reference/reveal_maps.md).
- [`vignette("roadmap")`](https://max578.github.io/masque/articles/roadmap.md)
  — features deliberately deferred from the current release.
