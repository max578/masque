# Recipe anatomy and the round-trip

## Why the recipe matters

This vignette is written for the analyst’s side of the workflow. The
custodian masks the data and keeps the recipe; you receive only the
synthetic. But the recipe is what makes a pipeline you write against the
synthetic re-target to the real data, so it is worth understanding what
it carries and how the round-trip works.

The `masque_recipe` is the only artefact that *must* stay confidential
alongside the original. It is an S7 object, but you never touch the
class directly – two accessors hide it:

``` r

m <- mask(df, roles, mode = "collaborate", seed = 1)
rec <- recipe(m)
class(rec)
#> [1] "masque::masque_recipe" "S7_object"
```

## What a recipe holds

A recipe is runtime-minimal by default:

- `masque_version`, `created_at`, `mode`, `seed` – provenance.
- `roles` – the two-axis role and action table.
- `level_maps` – the per-column original-to-alias maps. The sensitive
  part.
- `column_name_map` – the column-name aliases, when `alias_names` was
  used (otherwise `NULL`).
- `cleaning` – the hygiene record (name legalisation, whitespace trims)
  so
  [`apply_recipe()`](https://max578.github.io/masque/reference/apply_recipe.md)
  re-applies the identical tidying.
- `storage_classes`, `factor_meta` – the original column classes and
  factor metadata, for faithful reconstruction.
- `integrity_fp` – a SHA-256 of `is.na(original)`: an integrity
  fingerprint, not a privacy guarantee.

It deliberately does not hold the copula covariance, the raw observed
values, or any file paths or usernames.

## Printing is redacted

The print method shows the role and action table with a marker for which
columns hold a level map (`*` mapped, `=` not), but never the
vocabularies themselves:

``` r

rec
#> 
#> ── masque_recipe ───────────────────────────────────────────────────────────────────────────────────
#> • Created: 2026-07-14 01:31:27 UTC
#> • Mode: collaborate
#> • Clone fidelity: marginal / structural (global copula)
#> • Seed: present (redacted)
#> • masque version: 0.8.2
#> • Integrity fingerprint: 0cec319ba9e2...
#> 
#> ── Columns (7 total; 1 level-map(s); 0 column-name map(s)) ──
#> 
#>   = design    keep      plot                          (integer)
#>   = design    keep      rep                           (factor)
#>   = design    keep      block                         (factor)
#>   * treatment alias     gen                           (factor)
#>   = outcome   scramble  yield                         (numeric)
#>   = design    keep      row                           (integer)
#>   = design    keep      col                           (integer)
#> 
#> ✖ PRIVATE - never share this recipe alongside the synthetic.
#> Use `reveal_maps(rec)` to inspect level maps explicitly.
```

The custodian – and only the custodian – can reveal the maps with an
explicit, warning-gated call:

``` r

reveal_maps(rec)
#> ! Revealing sensitive level maps. Proceed at your discretion.
#> 
#> ── gen
#> 
#> ── seed
```

## The round-trip

The recipe is a bidirectional translator.
[`apply_recipe()`](https://max578.github.io/masque/reference/apply_recipe.md)
carries the original *into* the synthetic namespace;
[`unmask()`](https://max578.github.io/masque/reference/unmask.md)
carries results *back*. The usual pattern is to fit on the synthetic,
then score the original:

``` r

# Analyst trains on the synthetic clone.
fit <- lm(yield ~ gen, data = synthetic(m))

# Custodian re-targets the same pipeline onto the real data.
orig_in_synth_space <- apply_recipe(df, rec)
preds <- predict(fit, newdata = orig_in_synth_space)
length(preds) == nrow(df)
#> [1] TRUE
```

Recovering original-namespace labels is symmetric:

``` r

fwd <- apply_recipe(df, rec)
back <- unmask(fwd, rec)
identical(as.character(back$gen), as.character(df$gen))
#> [1] TRUE
```

Columns whose action is `keep` pass through all three verbs unchanged.
Numeric columns are passed through
[`apply_recipe()`](https://max578.github.io/masque/reference/apply_recipe.md)
and [`unmask()`](https://max578.github.io/masque/reference/unmask.md)
without an inverse map – the synthetic and original namespaces coincide
for them – so
[`unmask()`](https://max578.github.io/masque/reference/unmask.md) on a
numeric prediction vector is a safe no-op.

## Fail-closed translation

If the data drifts – a new treatment level the recipe has never seen –
[`apply_recipe()`](https://max578.github.io/masque/reference/apply_recipe.md)
errors rather than silently coercing the unknown value to `NA`. Schema
drift should fail loudly, not poison a model matrix.

``` r

drifted <- df
levels(drifted$gen) <- c(levels(df$gen), "BRAND_NEW")
drifted$gen[1] <- "BRAND_NEW"
apply_recipe(drifted, rec)
#> Error in `.fail_unmapped()`:
#> ! Value(s) not in the recipe's level map in column gen: "BRAND_NEW".
#> ℹ Schema drift or new original-namespace level(s). Unknown values are not coerced to NA
#>   (fail-closed).
#> • Rebuild the recipe from a dataset that contains these values, or strip them before retargeting.
```

## Saving the recipe

[`save_recipe()`](https://max578.github.io/masque/reference/save_recipe.md)
writes a single runtime-minimal `.rds` – small, and safe to store next
to the original at the same security class.
[`read_recipe()`](https://max578.github.io/masque/reference/read_recipe.md)
validates the file and notes a version mismatch without raising an
error.

``` r

tmp <- tempfile(fileext = ".rds")
save_recipe(rec, tmp)
rec2 <- read_recipe(tmp)
identical(rec@integrity_fp, rec2@integrity_fp)
#> [1] TRUE
```

## Multi-table bundles

A [`mask_set()`](https://max578.github.io/masque/reference/mask_set.md)
result carries a recipe *bundle* – one recipe per table plus the shared
cross-table link maps. The same
[`apply_recipe()`](https://max578.github.io/masque/reference/apply_recipe.md)
and [`unmask()`](https://max578.github.io/masque/reference/unmask.md)
verbs dispatch on it, operating table by table over a named list:

``` r

set_dir <- system.file("extdata", "met_set", package = "masque")
ms <- mask_set(set_dir, mode = "collaborate", seed = 1, quiet = TRUE)
originals <- read_set(set_dir)
fwd_set <- apply_recipe(originals, recipe(ms))
names(fwd_set)
#> [1] "agronomy" "quality"
```

Because the shared keys were aliased consistently at masking time, the
re-targeted tables join on the same keys the synthetic tables do.
