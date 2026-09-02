# Recipe anatomy and the round-trip

## Why

An analyst has only the synthetic table and their own code – the
custodian kept the original and the recipe. Their question is the one
every downstream user of a `masque` clone eventually asks: *what do I
actually get back from the custodian, and what happens the day the real
data does not quite match what I built against?* This vignette is
written for that analyst’s side of the workflow: what the recipe
carries, how the round-trip works, and what it does when the two sides
of the trust boundary disagree.

## What

The `masque_recipe` object returned by
[`mask()`](https://max578.github.io/masque/reference/mask.md) is the
only artefact that *must* stay confidential alongside the original – it
is an S7 object, accessed through
[`recipe()`](https://max578.github.io/masque/reference/recipe.md), never
touched directly. Two verbs carry the round-trip:
[`apply_recipe()`](https://max578.github.io/masque/reference/apply_recipe.md)
translates a data frame from the original namespace into the synthetic
namespace (the direction a custodian uses to re-target an analyst’s
finished pipeline), and
[`unmask()`](https://max578.github.io/masque/reference/unmask.md)
translates the other way (the direction that recovers original-namespace
labels from a synthetic-namespace result).
[`save_recipe()`](https://max578.github.io/masque/reference/save_recipe.md)/[`read_recipe()`](https://max578.github.io/masque/reference/read_recipe.md)
persist a recipe to a single `.rds` file, and
[`reveal_maps()`](https://max578.github.io/masque/reference/reveal_maps.md)
is the one explicit, warning-gated call that shows the level maps a
redacted [`print()`](https://rdrr.io/r/base/print.html) withholds.

## Do

### What a recipe holds

``` r

m <- mask(df, roles, mode = "collaborate", seed = 1L)
rec <- recipe(m)
class(rec)
#> [1] "masque::masque_recipe" "S7_object"
```

A recipe is runtime-minimal by default. It carries:

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
- `coords` – one entry per coordinate pair declared to
  [`mask()`](https://max578.github.io/masque/reference/mask.md)’s
  `coords` argument: the jitter method and radius, the site grouping it
  was masked under, and how many sites the grouping produced. Empty for
  a recipe written before 0.10.0, which had no such record.
- `allow_unmasked_coords` – `TRUE` only when the caller deliberately
  wrote a real coordinate through unmasked. `FALSE`, and absent, on a
  recipe written before 0.11.0.
- `integrity_fp` – a SHA-256 of `is.na(original)`: an integrity
  fingerprint, not a privacy guarantee.

It deliberately does not hold the copula covariance, the raw observed
values, or any file paths or usernames.

A recipe built with `coords` carries its own coordinate account, so an
audit of the recipe does not need the original data back:

``` r

df_geo <- df
df_geo$lat <- -34.9 + stats::runif(nrow(df_geo), -0.05, 0.05)
df_geo$lon <- 138.6 + stats::runif(nrow(df_geo), -0.05, 0.05)
roles_geo <- propose_roles(df_geo, mode = "collaborate")
roles_geo <- set_role(roles_geo, "yield", role = "outcome")
roles_geo <- set_role(roles_geo, c("lat", "lon"), action = "keep")

m_geo <- mask(df_geo, roles_geo, mode = "collaborate", seed = 1L,
              coords = list(list(lat = "lat", lon = "lon")))
n_sites_recorded <- recipe(m_geo)@coords[[1]]$n_sites
recipe(m_geo)@coords[[1]][c("method", "min_km", "max_km", "n_sites")]
#> $method
#> [1] "donut"
#> 
#> $min_km
#> [1] 5
#> 
#> $max_km
#> [1] 20
#> 
#> $n_sites
#> [1] 72
recipe(m_geo)@allow_unmasked_coords
#> [1] FALSE
```

Every row here shared one true coordinate, so `n_sites` equals the row
count – the recipe records that the whole table was jittered as one
group, not each row independently, which is the confidentiality property
`jitter_coordinates(by = )` is for.

### Printing is redacted

The print method shows the role and action table with a marker for which
columns hold a level map (`*` mapped, `=` not), but never the
vocabularies themselves:

``` r

rec
#> 
#> ── masque_recipe ───────────────────────────────────────────────────────────────────────────────────
#> • Created: 2026-09-02 07:48:25 UTC
#> • Mode: collaborate
#> • Clone fidelity: marginal / structural (global copula)
#> • Seed: present (redacted)
#> • masque version: 0.11.0
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

### The round-trip

The recipe is a bidirectional translator.
[`apply_recipe()`](https://max578.github.io/masque/reference/apply_recipe.md)
carries the original *into* the synthetic namespace.
[`unmask()`](https://max578.github.io/masque/reference/unmask.md)
carries results *back*. The usual pattern is to fit on the synthetic,
then score the original:

``` r

# Analyst trains on the synthetic clone.
fit <- lm(yield ~ gen, data = synthetic(m))

# Custodian re-targets the same pipeline onto the real data.
orig_in_synth_space <- apply_recipe(df, rec)
preds <- predict(fit, newdata = orig_in_synth_space)
preds_match_nrow <- length(preds) == nrow(df)
preds_match_nrow
#> [1] TRUE
```

Recovering original-namespace labels is symmetric:

``` r

fwd <- apply_recipe(df, rec)
back <- unmask(fwd, rec)
labels_recovered <- identical(as.character(back$gen), as.character(df$gen))
labels_recovered
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

### Fail-closed translation, and reading the refusal

If the data drifts – a new treatment level the recipe has never seen –
[`apply_recipe()`](https://max578.github.io/masque/reference/apply_recipe.md)
errors rather than silently coercing the unknown value to `NA`:

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

Reading the message: it names the exact column (`gen`) and the exact
unrecognised value (`"BRAND_NEW"`), states plainly that unknown values
are not silently coerced to `NA`, and gives the remedy – rebuild the
recipe from a dataset that contains the new value, or strip the drifted
rows before re-targeting. This is deliberate: a model matrix built from
a silently-introduced `NA` would fail somewhere downstream with a far
less legible error, or worse, would not fail at all and would simply
drop the drifted rows. Schema drift is exactly the kind of change that
should stop a pipeline at the point it happens, not several steps later.

### Saving the recipe

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
fingerprint_survives_roundtrip <- identical(rec@integrity_fp, rec2@integrity_fp)
fingerprint_survives_roundtrip
#> [1] TRUE
```

### Multi-table bundles

A [`mask_set()`](https://max578.github.io/masque/reference/mask_set.md)
result carries a recipe *bundle* – one recipe per table plus the shared
cross-table link maps. The same
[`apply_recipe()`](https://max578.github.io/masque/reference/apply_recipe.md)
and [`unmask()`](https://max578.github.io/masque/reference/unmask.md)
verbs dispatch on it, operating table by table over a named list:

``` r

set_dir <- system.file("extdata", "met_set", package = "masque")
ms <- mask_set(set_dir, mode = "collaborate", seed = 1L, quiet = TRUE)
#> Warning: Numeric environment column(s) year remain "keep" in collaborate mode.
#> ℹ This preserves environment structure but may disclose year or other numeric labels; review before
#>   release.
originals <- read_set(set_dir)
fwd_set <- suppressWarnings(apply_recipe(originals, recipe(ms)))
names(fwd_set)
#> [1] "agronomy" "quality"
```

Because the shared keys were aliased consistently at masking time, the
re-targeted tables join on the same keys the synthetic tables do.

### Figure: the clone the analyst actually develops against

Everything above works with the *labels*. The figure below shows what
the analyst’s numeric column actually looks like – the original yield
against the synthetic yield the analyst’s pipeline is fitted to – which
the round-trip checks above, all of them logical values, cannot show.

``` r

synth_tbl <- synthetic(m)
overlay_df <- rbind(
  data.frame(value = df$yield, table = "original"),
  data.frame(value = synth_tbl$yield, table = "synthetic")
)
ggplot2::ggplot(overlay_df, ggplot2::aes(x = value, fill = table)) +
  ggplot2::geom_density(alpha = 0.5) +
  ggplot2::scale_fill_viridis_d(name = "table") +
  ggplot2::labs(
    x = "yield (t/ha)", y = "density",
    title = "Original versus synthetic marginal distribution of yield"
  ) +
  ggplot2::theme_minimal()
```

![Density of yield, original trial against the synthetic clone the
analyst develops against. The two distributions overlap closely because
the default numeric synthesis preserves each column's marginal
distribution.](recipe_anatomy_files/figure-html/fig-overlay-1.png)

Density of yield, original trial against the synthetic clone the analyst
develops against. The two distributions overlap closely because the
default numeric synthesis preserves each column’s marginal distribution.

## Read

The round-trip holds on every check run above: the re-targeted
prediction vector has one entry per original row (TRUE), the recovered
genotype labels are identical to the original after a forward-then-back
trip through the recipe (TRUE), and a recipe written to disk and read
back carries an unchanged integrity fingerprint (TRUE). The coordinate
account records 72 sites for a fixture where every plot shared one true
coordinate, which is the row count of the trial – confirming the whole
table was jittered as one group rather than plot by plot. The
fail-closed section shows the other side of the same reliability
property: a value the recipe has never seen is refused, not guessed at,
so a pipeline re-targeted through
[`apply_recipe()`](https://max578.github.io/masque/reference/apply_recipe.md)
fails at the point the data actually drifted rather than downstream with
a harder-to-diagnose error.

The figure shows why the round-trip’s logical checks are not the whole
story: the two densities overlap closely, which is what “the marginal
distribution is preserved” looks like on real data, but overlap in the
marginal says nothing about whether a treatment effect or a non-linear
covariate relationship survived – for that, see *Confidentiality and the
threat model*.

Answering the opening question: the recipe an analyst is handed back
after their pipeline is finished lets a custodian re-target that exact
pipeline, unmodified, onto the real data, and the moment the real data
carries something the recipe was never built from, the translation stops
rather than guessing.

## Limits

Everything in this vignette exercises one recipe built from one clean
public trial with no missing structure and no schema drift beyond the
one planted for the fail-closed demonstration; a recipe built from a
table with genuinely inconsistent historical vocabularies will refuse
more often, by design, and the remedy each time is the same – rebuild
from data that contains the missing values, or strip the drifted rows.
The round-trip verbs invert exactly what the recipe recorded: a numeric
column has no inverse map and passes through unchanged, so
[`unmask()`](https://max578.github.io/masque/reference/unmask.md) cannot
recover anything about a numeric transformation a pipeline applied on
its own, and a recipe cannot repair a join that was broken outside
`masque` before masking ever ran. This vignette does not exercise the
leakage audit, the conditional clone, or the geographic-coordinate
masking controls in depth; those, and what the recipe alone cannot
protect against a determined reader of the synthetic, are
*Confidentiality and the threat model*’s subject.

## What to read next

*Getting started with masque* is the custodian’s side of this same
handoff: building and reviewing the masking plan that produces the
recipe this vignette reads. *Confidentiality and the threat model* sets
out what the recipe and the synthetic together do and do not protect,
including the leakage audit and the conditional clone that preserves a
treatment effect this vignette’s round-trip checks do not touch.

## Reproduce

`set.seed(1)` is set once for the whole document, and every
[`mask()`](https://max578.github.io/masque/reference/mask.md)/
[`mask_set()`](https://max578.github.io/masque/reference/mask_set.md)
call also passes `seed = 1L` explicitly, so each is independently
reproducible regardless of what ran before it in this vignette. Package
versions follow.

``` r

sessionInfo()
#> R version 4.6.1 (2026-06-24)
#> Platform: x86_64-pc-linux-gnu
#> Running under: Ubuntu 24.04.4 LTS
#> 
#> Matrix products: default
#> BLAS:   /usr/lib/x86_64-linux-gnu/openblas-pthread/libblas.so.3 
#> LAPACK: /usr/lib/x86_64-linux-gnu/openblas-pthread/libopenblasp-r0.3.26.so;  LAPACK version 3.12.0
#> 
#> locale:
#>  [1] LC_CTYPE=C.UTF-8       LC_NUMERIC=C           LC_TIME=C.UTF-8        LC_COLLATE=C.UTF-8    
#>  [5] LC_MONETARY=C.UTF-8    LC_MESSAGES=C.UTF-8    LC_PAPER=C.UTF-8       LC_NAME=C             
#>  [9] LC_ADDRESS=C           LC_TELEPHONE=C         LC_MEASUREMENT=C.UTF-8 LC_IDENTIFICATION=C   
#> 
#> time zone: UTC
#> tzcode source: system (glibc)
#> 
#> attached base packages:
#> [1] stats     graphics  grDevices utils     datasets  methods   base     
#> 
#> other attached packages:
#> [1] masque_0.11.0
#> 
#> loaded via a namespace (and not attached):
#>  [1] gtable_0.3.6        jsonlite_2.0.0      compiler_4.6.1      maps_3.4.3         
#>  [5] jquerylib_0.1.4     systemfonts_1.3.2   scales_1.4.0        textshaping_1.0.5  
#>  [9] yaml_2.3.12         fastmap_1.2.0       ggplot2_4.0.3       R6_2.6.1           
#> [13] labeling_0.4.3      knitr_1.51          tibble_3.3.1        desc_1.4.3         
#> [17] bslib_0.12.0        pillar_1.11.1       RColorBrewer_1.1-3  rlang_1.3.0        
#> [21] cachem_1.1.0        xfun_0.60           fs_2.1.0            sass_0.4.10        
#> [25] S7_0.2.2            otel_0.2.0          viridisLite_0.4.3   cli_3.6.6          
#> [29] pkgdown_2.2.1       withr_3.0.3         magrittr_2.0.5      digest_0.6.39      
#> [33] grid_4.6.1          lifecycle_1.0.5     vctrs_0.7.3         evaluate_1.0.5     
#> [37] glue_1.8.1          data.table_1.18.6.1 farver_2.1.2        ragg_1.5.2         
#> [41] rmarkdown_2.32      tools_4.6.1         pkgconfig_2.0.3     htmltools_0.5.9
```
