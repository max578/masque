# Hand a clone to an analyst

Writes what the analyst works from into one folder: the clone
(`clone.csv`), the plan in clone vocabulary (`plan.yaml`), the data card
(`card.yaml`) and a plain note (`README.txt`). The recipe is never
written. The release gate runs first, as for
[`write_set()`](https://max578.github.io/masque/reference/write_set.md):
an unresolved HIGH finding blocks the write unless `allow_high = TRUE`.
A local-mode clone has not been audited and is meant to stay with the
owner, so it is refused unless `allow_local = TRUE`.

## Usage

``` r
handover(
  m,
  dir,
  name = NULL,
  overwrite = FALSE,
  allow_high = FALSE,
  allow_local = FALSE
)
```

## Arguments

- m:

  A `masque` object from
  [`mask()`](https://max578.github.io/masque/reference/mask.md).

- dir:

  The folder to write. An existing folder that holds files is refused
  unless `overwrite = TRUE`.

- name:

  Dataset name for the data card; `NULL` uses `"clone"`. It is written
  as given, so it should say nothing the clone hides.

- overwrite:

  Replace the four files if they exist.

- allow_high:

  Write despite HIGH findings, with a warning.

- allow_local:

  Write a local-mode clone, for a folder the owner keeps.

## Value

The paths written, invisibly.

## Details

`clone.csv` loses column classes. Read label columns as text where a
label looks like a number, or
[`controls()`](https://max578.github.io/masque/reference/controls.md)
will not find its levels.

## See also

[`clone_plan()`](https://max578.github.io/masque/reference/clone_plan.md),
[`data_card()`](https://max578.github.io/masque/reference/data_card.md),
[`controls()`](https://max578.github.io/masque/reference/controls.md).

## Examples

``` r
if (requireNamespace("yaml", quietly = TRUE)) {
  r <- propose_roles(iris, mode = "collaborate", detect = FALSE)
  m <- mask(iris, r, mode = "collaborate", seed = 1L)
  d <- tempfile()
  handover(m, d)
  list.files(d)
}
#> [1] "README.txt" "card.yaml"  "clone.csv"  "plan.yaml" 
```
