# Read a set of tables from a folder, an Excel workbook, or a list

Ingests a multi-table dataset into a named list of data frames, ready
for
[`mask_set()`](https://max578.github.io/masque/reference/mask_set.md).
Three input shapes are accepted:

## Usage

``` r
read_set(input, sheets = NULL, pattern = NULL)
```

## Arguments

- input:

  A folder path, an `.xlsx` / `.xls` path, or a named list of data
  frames.

- sheets:

  For an Excel workbook, an optional character vector of sheet names to
  read (default: all sheets).

- pattern:

  For a folder, an optional regular expression to select files (default:
  all `.csv` / `.tsv` / `.fst`).

## Value

A named list of data frames.

## Details

- a folder path:

  Every `.csv`, `.tsv`, and `.fst` file in the folder becomes one table,
  named by its file name (without extension). CSV / TSV are read with
  [`data.table::fread()`](https://rdrr.io/pkg/data.table/man/fread.html);
  `.fst` needs the Suggested `fst` package.

- an Excel workbook (`.xlsx` / `.xls`):

  Every sheet becomes one table, named by its sheet name. Needs the
  Suggested `readxl` package.

- a named list of data frames:

  Returned as-is after validation.

Only clean rectangular tables are supported. A sheet or file that does
not read as a rectangle - missing header row (auto-named `...1`
columns), zero rows, or zero columns - fails with an explanatory error
naming the offending table. `masque` does not attempt to recover merged
cells, multi-row headers, or junk rows; tidy the source first.

## See also

[`mask_set()`](https://max578.github.io/masque/reference/mask_set.md),
[`write_set()`](https://max578.github.io/masque/reference/write_set.md).

## Examples

``` r
tables <- list(
  plots = data.frame(site = c("A", "B"), yield = c(3.1, 4.2)),
  sites = data.frame(site = c("A", "B"), rainfall = c(400, 550))
)
read_set(tables)
#> $plots
#>   site yield
#> 1    A   3.1
#> 2    B   4.2
#> 
#> $sites
#>   site rainfall
#> 1    A      400
#> 2    B      550
#> 
```
