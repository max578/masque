# Write a masked set to disk, mirroring the input format

Writes the synthetic tables of a
[`mask_set()`](https://max578.github.io/masque/reference/mask_set.md)
result to disk. The output format mirrors the request: a `.xlsx` path
produces one workbook with one sheet per table; a folder path produces
one `.csv` per table. The private recipe bundle is **never** written by
this function - persist it separately with
[`save_recipe()`](https://max578.github.io/masque/reference/save_recipe.md)
and protect it at the same security class as the original data.

## Usage

``` r
write_set(m, path, overwrite = FALSE, allow_high = FALSE)
```

## Arguments

- m:

  A `masque_set` object from
  [`mask_set()`](https://max578.github.io/masque/reference/mask_set.md).

- path:

  Output location. A path ending in `.xlsx` writes a workbook (needs the
  Suggested `writexl` package); any other path is treated as a folder,
  created if necessary, and receives one `<table>.csv` per table.

- overwrite:

  Logical. When `FALSE` (default), writing over an existing file or a
  non-empty folder errors.

- allow_high:

  Logical (default `FALSE`). Override the HIGH-leakage write refusal
  after your own review; the override is raised as a
  `masque_high_override` warning.

## Value

`path`, invisibly.

## Details

In collaborate mode the mask-time audit gates the write: unresolved HIGH
leakage findings refuse the write (nothing is written) until the flagged
columns are re-roled, aliased, or dropped - or the refusal is explicitly
overridden with `allow_high = TRUE`, which raises a
`masque_high_override` warning so the exception stays visible.

## See also

[`mask_set()`](https://max578.github.io/masque/reference/mask_set.md),
[`read_set()`](https://max578.github.io/masque/reference/read_set.md),
[`save_recipe()`](https://max578.github.io/masque/reference/save_recipe.md).

## Examples

``` r
tables <- list(
  plots = data.frame(site = c("A", "B"), yield = c(3.1, 4.2)),
  sites = data.frame(site = c("A", "B"), rain = c(420, 560))
)
m <- mask_set(tables, seed = 1, quiet = TRUE)
dir <- file.path(tempdir(), "masked_set")
write_set(m, dir)
list.files(dir)
#> [1] "plots.csv" "sites.csv"
```
