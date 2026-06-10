# Recipe anatomy

## What is a recipe?

The `masque_recipe` is the only artefact that *must* remain confidential
alongside the original data. It is what makes the round-trip work:
without the recipe you cannot translate a pipeline trained on the
synthetic back onto the original.

A recipe is an S7 object, but users do not need to know that. The two
exported accessors hide the class details:

``` r

m <- mask(df, roles, mode = "collaborate", seed = 1)
rec <- recipe(m)
class(rec)
#> [1] "masque::masque_recipe" "S7_object"
```

### Anatomy

A recipe holds **runtime-minimal** state by default:

- `masque_version` — the package version that built the recipe.
- `created_at` — wall-clock timestamp at construction.
- `mode` — `"local"` or `"collaborate"`.
- `seed` — the seed passed to
  [`mask()`](https://max578.github.io/masque/reference/mask.md), or
  `NULL` if not given.
- `roles` — the per-column role tibble (`design`, `keep`, `treatment`,
  `outcome`, `covariate`, or `ignore`).
- `column_name_map` — original-to-synthetic column-name map (currently
  `NULL`; reserved for a future opt-in column-aliasing flag — see
  [`vignette("roadmap")`](https://max578.github.io/masque/articles/roadmap.md)).
- `level_maps` — per-column factor / character / logical maps. The
  sensitive bit.
- `storage_classes` — per-column R class of the original.
- `factor_meta` — per-factor levels and `ordered` status.
- `warnings` — text of any warnings raised at construction.
- `integrity_fp` — SHA-256 of `is.na(original)`. An **integrity
  fingerprint**, not a privacy guarantee.

What it deliberately does **not** hold:

- Simulator state (the copula covariance matrix, the raw observed
  margins). Reserved for a future opt-in via
  `save_recipe(..., include_simulator = TRUE)`; currently a no-op.
- Raw observed values.
- Source file paths, machine usernames, or absolute paths.

### `print(recipe)` is redacted

The default print method shows the per-column role table and a marker
indicating whether a level map exists for each column (`*` = mapped, `=`
= no map), but **never** the actual level vocabularies.

``` r

rec
#> 
#> ── masque_recipe ───────────────────────────────────────────────────────────────────────────────────
#> • Created: 2026-06-10 13:13:36 UTC
#> • Mode: collaborate
#> • Seed: present (redacted)
#> • masque version: 0.5.0
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

If you need to inspect the maps — typically the data owner reviewing the
recipe before saving — call
[`reveal_maps()`](https://max578.github.io/masque/reference/reveal_maps.md)
explicitly:

``` r

reveal_maps(rec)
#> ! Revealing sensitive level maps. Proceed at your discretion.
#> 
#> ── gen
#> 
#> ── seed
```

[`reveal_maps()`](https://max578.github.io/masque/reference/reveal_maps.md)
prints a warning banner (“Revealing sensitive level maps. Proceed at
your discretion.”) and then dumps every map and the seed value. Save its
output sparingly.

### Saving and loading

[`save_recipe()`](https://max578.github.io/masque/reference/save_recipe.md)
writes a single `.rds` file. The default is runtime-minimal — small,
safe to store next to the original data with the same security class.

``` r

tmp <- tempfile(fileext = ".rds")
save_recipe(rec, tmp)
file.info(tmp)$size
#> [1] 6832
```

[`read_recipe()`](https://max578.github.io/masque/reference/read_recipe.md)
validates the file and informs (does not error) when the recorded
`masque_version` differs from the currently installed package version.

``` r

rec2 <- read_recipe(tmp)
identical(rec@integrity_fp, rec2@integrity_fp)
#> [1] TRUE
```

### The integrity fingerprint

`integrity_fp` is `digest::digest(is.na(original), algo = "sha256")`. It
lets a downstream consumer check that a recipe corresponds to the
expected missingness pattern, without exposing any other information
about the original data.

``` r

digest::digest(is.na(df), algo = "sha256") == rec@integrity_fp
#> [1] TRUE
```

It is **not** a privacy mechanism. The hash tells you whether two data
frames share the same NA mask; it does not hide the underlying mask or
its risks.

### Round-trip the maps directly

The recipe is the bidirectional translator.
[`apply_recipe()`](https://max578.github.io/masque/reference/apply_recipe.md)
and [`unmask()`](https://max578.github.io/masque/reference/unmask.md)
both operate on it:

``` r

fwd <- apply_recipe(df, rec)
back <- unmask(fwd, rec)
identical(as.character(back$gen), as.character(df$gen))
#> [1] TRUE
```

Columns roled `keep` are intentionally not translated: they pass through
[`mask()`](https://max578.github.io/masque/reference/mask.md),
[`apply_recipe()`](https://max578.github.io/masque/reference/apply_recipe.md),
and [`unmask()`](https://max578.github.io/masque/reference/unmask.md)
unchanged. Date/time covariates are different:
[`mask()`](https://max578.github.io/masque/reference/mask.md)
row-permutes them in the synthetic, while
[`apply_recipe()`](https://max578.github.io/masque/reference/apply_recipe.md)
leaves the original values unchanged because the pipeline is being
retargeted to the original data.

### Future: `include_simulator = TRUE`

`save_recipe(rec, path, include_simulator = TRUE)` is accepted today but
is currently a no-op (no simulator state is stored on the recipe). A
future release will use this flag to persist enough state that
`draw_new_synthetic(rec, n)` can produce fresh synthetic samples without
access to the original. See
[`vignette("roadmap")`](https://max578.github.io/masque/articles/roadmap.md)
for the deferred items.
