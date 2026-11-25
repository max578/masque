# Recipe anatomy and the round-trip

## Why

An analyst has the synthetic table and their own code. The data owner
keeps the original and the recipe. This vignette covers what the recipe
carries, how the analyst’s finished pipeline is run on the original, and
what happens when the original holds a value the recipe has never seen.

The examples use `mode = "collaborate"`, because the default mode
(`"null"`) keeps no structure beyond the design. The recipe works the
same way in every mode.

## What

The recipe, taken from a
[`mask()`](https://max578.github.io/masque/reference/mask.md) result
with [`recipe()`](https://max578.github.io/masque/reference/recipe.md),
holds the real labels, the original column names and the seed. Together
with the synthetic it undoes every alias, so keep it with the original
data and never send it with the synthetic.

Two functions make the round-trip.
[`apply_recipe()`](https://max578.github.io/masque/reference/apply_recipe.md)
recodes the original data into the clone’s labels and column names,
which is how a data owner runs an analyst’s finished pipeline on it.
[`unmask()`](https://max578.github.io/masque/reference/unmask.md) goes
the other way and turns a result in the clone’s labels back into the
original ones.
[`save_recipe()`](https://max578.github.io/masque/reference/save_recipe.md)
and
[`read_recipe()`](https://max578.github.io/masque/reference/read_recipe.md)
write and read a recipe as a single `.rds` file, and
[`reveal_maps()`](https://max578.github.io/masque/reference/reveal_maps.md)
prints the level maps that a redacted
[`print()`](https://rdrr.io/r/base/print.html) withholds.

## Example

### What a recipe holds

``` r

m <- mask(df, plan, mode = "collaborate", seed = 1L)
rec <- recipe(m)
class(rec)
#> [1] "masque::masque_recipe" "S7_object"
```

A recipe holds:

- `masque_version`, `created_at`, `mode`: provenance.
- `seed`: the seed of the call. With it the same call reproduces the
  same alias maps, so keep it as private as the maps.
- `roles`: each column’s role and action, with the original column
  names.
- `conditional`, `ladder`, `conditioning_cols`, `conditioning_used`,
  `conditioning_dropped`, `conditioning_shifted`, `fallback_frac`: what
  a conditional clone asked for, the stratum it got, the columns it
  dropped or carried as shifts, and the share of rows pooled.
- `level_maps`: the per-column original-to-alias maps. This is the
  sensitive part. Aliases follow one scheme: `trt_001`, `trt_002`, … for
  a single aliased treatment, factor or numeric (`<col>_trt_001` when
  several treatments are aliased), `<col>_L001` for a categorical
  covariate, `<col>_D001` for a design column, `<col>_I001` for an
  identifier, `<col>_T001` for free text, and `<col>_K001` for a key
  shared across the tables of a set. The numbers have at least three
  digits, more when a column has over 999 levels.
- `column_name_map`: the column-name aliases, when `alias_names` was
  used (otherwise `NULL`).
- `storage_classes`, `factor_meta`: the original column classes, factor
  levels and ordering, for faithful reconstruction.
- `cleaning`: the tidying done before masking (column names made valid R
  names, whitespace trimmed), so
  [`apply_recipe()`](https://max578.github.io/masque/reference/apply_recipe.md)
  re-applies the same tidying.
- `conform`: the label merges and type changes
  [`conform_table()`](https://max578.github.io/masque/reference/conform_table.md)
  made, so
  [`apply_recipe()`](https://max578.github.io/masque/reference/apply_recipe.md)
  replays them on the original.
- `grain`: for each design unit whose columns were synthesised once per
  unit, the columns, the number of units, and whether the clone kept the
  unit or fell back to rows.
- `events`: the linked time-to-event specs and how many final times were
  capped.
- `coords`: one entry per coordinate pair declared to
  [`mask()`](https://max578.github.io/masque/reference/mask.md)’s
  `coords` argument: the jitter method and radius, the site grouping it
  was masked under, and how many sites the grouping produced.
- `allow_unmasked_coords`: `TRUE` only when the caller deliberately
  wrote a real coordinate through unmasked.
- `allow_kept_outcome`: `TRUE` only when the caller allowed a kept
  outcome in a default or collaborate clone.
- `noise`: the draw behind the `noise` action, `"summary"` or
  `"standard"`.
- `plan` and `owner_key`: the plan the clone was made from, resolved on
  the original, and a private key for the data owner’s known-truth
  controls. Both are empty when
  [`mask()`](https://max578.github.io/masque/reference/mask.md) was not
  given a plan.
- `warnings`: the warnings raised while masking, including any HIGH
  audit finding.
- `content_fp` and `integrity_fp`: fingerprints of the original’s values
  (two weighted sums per numeric column and a digest of the rest) and of
  its missing-value pattern (a SHA-256 of `is.na(original)`).
  [`apply_recipe()`](https://max578.github.io/masque/reference/apply_recipe.md)
  uses them to check it was given the same table. They are integrity
  checks, not privacy guarantees.

A recipe written by an older version has no record for the slots added
since, for example `coords` before 0.10.0 and `allow_unmasked_coords`
before 0.11.0. It still prints, applies and unmasks. The changelog lists
when each slot was added.

It does not hold the copula covariance, the values of any re-simulated
or noise column, or any file paths or usernames.

A recipe built with `coords` records how its coordinates were masked, so
an audit of the recipe does not need the original data back:

``` r

df_geo <- df
df_geo$lat <- -34.9 + stats::runif(nrow(df_geo), -0.05, 0.05)
df_geo$lon <- 138.6 + stats::runif(nrow(df_geo), -0.05, 0.05)
plan_geo <- propose_roles(df_geo, mode = "collaborate")
plan_geo <- set_role(plan_geo, c("lat", "lon"), action = "keep")

m_geo <- mask(df_geo, plan_geo, mode = "collaborate", seed = 1L,
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

Each plot here has its own coordinate, so each plot is a site and
`n_sites` equals the number of plots. Rows that share a coordinate would
share one displacement (see
[`jitter_coordinates()`](https://max578.github.io/masque/reference/jitter_coordinates.md)).

### Printing is redacted

The print method shows the role and action table with a marker for which
columns hold a level map (`*` mapped, `=` not), but never the
vocabularies themselves:

``` r

rec
```


    ── masque_recipe ───────────────────────────────────────────────────────────────────────────────────
    • Created: 2026-11-25 05:56:10 UTC
    • Mode: collaborate
    • Clone fidelity: marginal / structural (global copula)
    • Seed: present (redacted)
    • masque version: 0.18.0
    • Integrity fingerprint: 0cec319ba9e2...

    ── Columns (7 total; 1 level map; 0 column-name maps) ──

      = design    keep      plot                          (integer)
      = design    keep      rep                           (factor)
      = design    keep      block                         (factor)
      * treatment alias     gen                           (factor)
      = outcome   scramble  yield                         (numeric)
      = design    keep      row                           (integer)
      = design    keep      col                           (integer)

    ✖ PRIVATE - never share this recipe alongside the synthetic.
    Use `reveal_maps(rec)` to inspect level maps explicitly.

The same holds for [`format()`](https://rdrr.io/r/base/format.html),
[`str()`](https://rdrr.io/r/utils/str.html) and knitr output of a recipe
and of a `masque` object, so the seed and the maps do not end up in a
log or a rendered report by accident. Anyone holding the recipe can
print the maps with an explicit call, which shows a warning first. Its
output, 24 genotype labels, is left out here:

``` r

reveal_maps(rec)
```

### The round-trip

The usual pattern is to fit on the synthetic, recode the original with
[`apply_recipe()`](https://max578.github.io/masque/reference/apply_recipe.md),
and predict on it:

``` r

# Analyst trains on the synthetic clone.
fit <- lm(yield ~ gen, data = synthetic(m))

# The data owner runs the same pipeline on the real data.
orig_in_synth_space <- apply_recipe(df, rec)
preds <- predict(fit, newdata = orig_in_synth_space)
preds_match_nrow <- length(preds) == nrow(df)
preds_match_nrow
#> [1] TRUE
```

[`unmask()`](https://max578.github.io/masque/reference/unmask.md)
recovers the original labels:

``` r

fwd <- apply_recipe(df, rec)
back <- unmask(fwd, rec)
labels_recovered <- identical(as.character(back$gen), as.character(df$gen))
labels_recovered
#> [1] TRUE
```

Columns whose action is `keep`, re-simulated numeric columns and numeric
predictions pass through both functions unchanged. A numeric treatment
that was aliased is mapped both ways, and
[`unmask()`](https://max578.github.io/masque/reference/unmask.md)
returns its exact original values.
[`apply_recipe()`](https://max578.github.io/masque/reference/apply_recipe.md)
returns an aliased factor with the clone’s levels in the clone’s order,
so a model fitted on the translated original has the same reference
level as on the clone.

### Fail-closed translation

If the data drifts, for example a new treatment level the recipe has
never seen,
[`apply_recipe()`](https://max578.github.io/masque/reference/apply_recipe.md)
stops with an error. Any change to the values also fails the integrity
check, which runs first, so the example turns that check off to reach
the label check:

``` r

drifted <- df
levels(drifted$gen) <- c(levels(df$gen), "BRAND_NEW")
drifted$gen[1] <- "BRAND_NEW"
apply_recipe(drifted, rec, check_integrity = FALSE)
#> Error in `.fail_unmapped()`:
#> ! Value not in the recipe's level map in column gen: "BRAND_NEW".
#> ℹ Schema drift, or original levels the recipe has never seen. Unknown values are not coerced to NA
#>   (fail-closed).
#> • Rebuild the recipe from a dataset that contains these values, or strip them before retargeting.
```

The message names the column (`gen`) and the value (`"BRAND_NEW"`).
Either remove the drifted rows before running the pipeline, or mask the
data that contains the new value again. Masking again makes a new recipe
and a new synthetic, and the analyst needs the new synthetic in place of
the old one.

### Saving the recipe

[`save_recipe()`](https://max578.github.io/masque/reference/save_recipe.md)
writes a single small `.rds`, to be stored next to the original at the
same security class. The path must end in `.rds`.
[`read_recipe()`](https://max578.github.io/masque/reference/read_recipe.md)
validates the file and notes a version mismatch without raising an
error.

``` r

tmp <- tempfile(fileext = ".rds")
save_recipe(rec, tmp)
rec2 <- read_recipe(tmp)
fingerprint_survives_roundtrip <- identical(
  rec@integrity_fp, rec2@integrity_fp
)
fingerprint_survives_roundtrip
#> [1] TRUE
```

### Multi-table bundles

A [`mask_set()`](https://max578.github.io/masque/reference/mask_set.md)
result carries a recipe *bundle*: one recipe per table plus the shared
cross-table link maps. The same
[`apply_recipe()`](https://max578.github.io/masque/reference/apply_recipe.md)
and [`unmask()`](https://max578.github.io/masque/reference/unmask.md)
verbs dispatch on it, operating table by table over a named list. `year`
is made a factor before masking so that collaborate mode can alias it
(see *Getting started with masque*):

``` r

set_dir <- system.file("extdata", "met_set", package = "masque")
originals <- read_set(set_dir)
originals$agronomy[, year := factor(year)]
ms <- mask_set(originals, mode = "collaborate", seed = 1L, quiet = TRUE)
fwd_set <- apply_recipe(originals, recipe(ms))
names(fwd_set)
#> [1] "agronomy" "quality"
```

[`save_recipe()`](https://max578.github.io/masque/reference/save_recipe.md)
and
[`read_recipe()`](https://max578.github.io/masque/reference/read_recipe.md)
keep a bundle as one file, and
`reveal_maps(recipe(ms), table = "quality")` reveals the maps of the
named table only.

Because the shared keys were aliased consistently at masking time, the
recoded tables join on the same keys the synthetic tables do.

### Figure: original against synthetic yield

The checks above are about labels. The figure shows the numeric column
the analyst works with: the original yield against the synthetic yield.

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
    x = "yield (t/ha)", y = "density"
  ) +
  ggplot2::theme_minimal()
```

![Two overlapping density curves of yield, original and synthetic, with
nearly the same
shape.](recipe_anatomy_files/figure-html/fig-overlay-1.png)

Density of yield, original trial against the synthetic clone. The two
distributions overlap closely because collaborate mode draws each
re-simulated numeric column from its own marginal distribution.

## Results

All three round-trip checks pass: one prediction per original row, the
original genotype labels recovered, and the same integrity fingerprint
after the recipe is saved and read back. A value the recipe has never
seen stops the translation where the data drifted.

The two yield densities overlap closely, so the marginal distribution is
kept. That says nothing about whether a treatment effect or a non-linear
relationship between columns is kept. *Confidentiality and the threat
model* covers both.

With the recipe, the data owner can run the analyst’s finished pipeline
on the real data without changing it.

## Limits

This vignette uses one recipe built from one clean public trial, with
one planted drift. By default
[`apply_recipe()`](https://max578.github.io/masque/reference/apply_recipe.md)
accepts only the table the recipe was built from. With
`check_integrity = FALSE` it runs on updated data, and labels added
since masking are still refused. The round-trip functions invert only
what the recipe recorded. Numeric columns pass through unchanged, so
[`unmask()`](https://max578.github.io/masque/reference/unmask.md) cannot
undo a numeric transformation a pipeline made, and a recipe cannot
repair a join that was broken before masking. The leakage audit, the
conditional clone and the coordinate controls are covered in
*Confidentiality and the threat model*.

## What to read next

*Getting started with masque* is the data owner’s side of this same
handover: building and reviewing the masking plan that produces the
recipe this vignette reads. *Confidentiality and the threat model* sets
out what the recipe and the synthetic together do and do not protect,
including the leakage audit and the conditional clone that mimics a
treatment effect.

## Reproduce

`set.seed(1)` is set once for the document, and every
[`mask()`](https://max578.github.io/masque/reference/mask.md) or
[`mask_set()`](https://max578.github.io/masque/reference/mask_set.md)
call passes `seed = 1L`, so each is reproducible on its own. Package
versions follow.

``` r

sessionInfo()
#> R version 4.6.2 (2026-10-29)
#> Platform: x86_64-pc-linux-gnu
#> Running under: Ubuntu 26.04.1 LTS
#> 
#> Matrix products: default
#> BLAS:   /usr/lib/x86_64-linux-gnu/openblas-pthread/libblas.so.3 
#> LAPACK: /usr/lib/x86_64-linux-gnu/openblas-pthread/libopenblasp-r0.3.32.so;  LAPACK version 3.12.0
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
#> [1] masque_0.18.0
#> 
#> loaded via a namespace (and not attached):
#>  [1] vctrs_0.7.3         cli_3.6.6           knitr_1.52          rlang_1.3.0        
#>  [5] xfun_0.62           otel_0.3.0          textshaping_1.1.0   S7_1.0.0           
#>  [9] data.table_1.18.6.1 jsonlite_2.0.0      labeling_0.4.3      glue_1.8.1         
#> [13] htmltools_0.5.9     ragg_1.5.2          sass_0.5.0          scales_1.4.0       
#> [17] rmarkdown_2.32      grid_4.6.2          evaluate_1.0.5      jquerylib_0.1.4    
#> [21] fastmap_1.2.0       yaml_2.3.12         lifecycle_1.0.5     compiler_4.6.2     
#> [25] RColorBrewer_1.1-3  fs_2.1.0            maps_3.4.4          systemfonts_1.3.4  
#> [29] farver_2.1.2        digest_0.6.39       viridisLite_0.4.3   R6_2.6.1           
#> [33] pillar_1.11.1       bslib_0.12.0        withr_3.0.3         tools_4.6.2        
#> [37] gtable_0.3.6        pkgdown_2.2.1       ggplot2_4.0.4       cachem_1.1.0       
#> [41] desc_1.4.3
```
