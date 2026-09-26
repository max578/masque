# Tidy a dirty table's column names and category labels before masking

Real custodian tables arrive with column names that are not valid R
names (`"Yield (t/ha)"`, `"Site Name"`), leading or trailing whitespace
in names and factor / character values, and the occasional
near-duplicate label (`"north"` vs `"North"` vs `" north"`).
`clean_table()` legalises names and trims whitespace, and reports each
fix. Near-duplicate labels are only reported, since merging labels that
look alike is a judgement call;
[`conform_table()`](https://max578.github.io/masque/reference/conform_table.md)
makes it.

## Usage

``` r
clean_table(df, clean = c("auto", "report", "off"), quiet = FALSE)
```

## Arguments

- df:

  A data frame.

- clean:

  One of `"auto"` (default - legalise names, trim whitespace, report
  near-duplicates), `"report"` (legalise names, report what whitespace /
  near-duplicate changes *would* be made but apply none), or `"off"`
  (legalise names only, skip all other hygiene). Column-name
  legalisation is applied in **every** mode – an invalid name silently
  rewritten downstream corrupts the clone – and is surfaced as a
  `masque_name_repaired` warning; only the whitespace and near-duplicate
  handling is governed by the mode.

- quiet:

  Logical. When `FALSE` (default) a `cli` summary of the fixes and
  advisories is printed. Set `TRUE` to suppress it (the report object is
  returned either way).

## Value

An object of class `masque_cleaning`: a list with

- `data` - the cleaned (or, under `report` / `off`, unchanged) data
  frame;

- `name_map` - named character `original -> clean` for every column
  whose name changed (empty if none);

- `level_fixes` - named list, one entry per column whose values were
  trimmed, each a named character `original -> clean`;

- `near_duplicates` - a data frame of report-only label pairs (`col`,
  `a`, `b`, `kind`) that look like typos but were left untouched;

- `mode` - the `clean` mode applied.

## Details

The corrections are returned alongside the cleaned data, so
[`mask()`](https://max578.github.io/masque/reference/mask.md) records
them in the recipe and
[`apply_recipe()`](https://max578.github.io/masque/reference/apply_recipe.md)
re-applies the same cleaning to the original.

## See also

[`mask()`](https://max578.github.io/masque/reference/mask.md),
[`propose_roles()`](https://max578.github.io/masque/reference/propose_roles.md).

## Examples

``` r
df <- data.frame(
  `Site Name` = c("north ", "north", "South"),
  `Yield (t/ha)` = c(3.1, 2.9, 5.0),
  check.names = FALSE
)
cl <- clean_table(df, quiet = TRUE)
#> Warning: Renamed 2 column names that R does not accept: `Site Name` -> `Site.Name`, `Yield (t/ha)` -> `Yield..t.ha.`. The map is recorded in the recipe and reversed on the round-trip.
names(cl$data)
#> [1] "Site.Name"    "Yield..t.ha."
cl$near_duplicates
#> [1] col  a    b    kind
#> <0 rows> (or 0-length row.names)
```
