# Mask a multi-table set with cross-table-consistent aliasing

The set-level counterpart to
[`mask()`](https://max578.github.io/masque/reference/mask.md). Takes a
folder of tabular files, an Excel workbook, or a named list of data
frames and produces one synthetic table per input table plus a single
private recipe bundle. Columns that are shared across tables - a site
code, a genotype name, a plot id appearing in several tables - are
aliased *identically everywhere they occur*, so a join written against
the synthetic set still resolves on the masked data.

## Usage

``` r
mask_set(
  input,
  roles = NULL,
  links = NULL,
  mode = c("local", "collaborate"),
  seed = NULL,
  clean = c("auto", "report", "off"),
  alias_names = FALSE,
  conditional = FALSE,
  ladder = c("hierarchy", "levels"),
  grain = TRUE,
  allow_kept_outcome = FALSE,
  quiet = FALSE,
  sheets = NULL,
  info = NULL,
  ...
)
```

## Arguments

- input:

  A folder path, an `.xlsx` / `.xls` path, or a named list of data
  frames - anything
  [`read_set()`](https://max578.github.io/masque/reference/read_set.md)
  accepts. A list element may also be a
  [`conform_table()`](https://max578.github.io/masque/reference/conform_table.md)
  result: its cleaning record and conform decisions are used for that
  table and recorded on its recipe.

- roles:

  Optional named list of roles tables, one per input table (names must
  match). When `NULL` (default),
  [`propose_roles()`](https://max578.github.io/masque/reference/propose_roles.md)
  runs on each table for the chosen `mode`. Supply edited tables for
  full control.

- links:

  Optional override for link detection: a character vector of column
  names to treat as cross-table links, or `FALSE` to disable linking
  entirely (each table masked independently). When `NULL` (default),
  links are detected automatically.

- mode:

  Either `"local"` or `"collaborate"`. When omitted and `roles` are
  supplied, inherit their common mode. Tables prepared for different
  modes must be reconciled explicitly. Otherwise default to `"local"`.

- seed:

  Optional integer for reproducibility.

- clean:

  Hygiene mode passed to
  [`clean_table()`](https://max578.github.io/masque/reference/clean_table.md)
  for every table (`"auto"`, `"report"`, or `"off"`).

- alias_names:

  Hide column names. `FALSE` (default) keeps them; `TRUE` aliases every
  non-link column (linked join keys keep their names so the synthetic
  set stays joinable).

- conditional:

  Logical scalar (default `FALSE`). Passed through to each per-table
  [`mask()`](https://max578.github.io/masque/reference/mask.md) call:
  when `TRUE`, every table's numeric block is re-simulated within its
  own treatment-by-design strata so the treatment-to-outcome
  relationship survives the clone. See
  [`mask()`](https://max578.github.io/masque/reference/mask.md) for the
  full account.

- ladder:

  Drop order of the conditioning ladder, `"hierarchy"` (default) or
  `"levels"`; passed through to each
  [`mask()`](https://max578.github.io/masque/reference/mask.md) call.

- grain:

  Single logical (default `TRUE`); passed through to each
  [`mask()`](https://max578.github.io/masque/reference/mask.md) call,
  which synthesises a unit-constant column once per unit.

- allow_kept_outcome:

  Single logical, passed to each
  [`mask()`](https://max578.github.io/masque/reference/mask.md) call:
  `TRUE` allows a kept outcome in a collaborate clone and records it.

- quiet:

  Logical; suppress the link / hygiene report, including the hint that a
  table looks like documentation.

- sheets:

  For an Excel workbook, the sheets to read (default: all); passed to
  [`read_set()`](https://max578.github.io/masque/reference/read_set.md).

- info:

  Optional character vector of table names (sheet names, or file names
  without extension) to set aside as documentation, for example a data
  dictionary. They are set aside before masking: not masked, not in the
  synthetic set, not written by
  [`write_set()`](https://max578.github.io/masque/reference/write_set.md),
  and their content is not kept. Their names are recorded on the recipe
  bundle. A table that looks like documentation and is not named here
  raises a hint (a message of class `masque_info_hint`); the hint
  decides nothing.

- ...:

  Must be empty: any argument here is refused with
  `masque_unused_arg_refusal`.

## Value

A `masque_set` S7 object. Use
[`synthetic()`](https://max578.github.io/masque/reference/synthetic.md)
for the named list of synthetic tables and
[`recipe()`](https://max578.github.io/masque/reference/recipe.md) for
the private recipe bundle.

## Links

A *link* is a column name that appears in two or more tables with a
compatible kind and overlapping values - the join keys of the set.
`mask_set()` proposes links automatically and prints them; pass `links`
to override. Linked columns are aliased in place with a shared map
(built over the union of values across all tables), so identical
original values map to identical aliases in every table. The aliases
read `<col>_K001`, `<col>_K002`, ..., assigned at random and, when
`seed` is set, the same for the same seed. Set a linked column's action
to `keep` in its roles table to pass it through unmasked instead.

## See also

[`mask()`](https://max578.github.io/masque/reference/mask.md),
[`read_set()`](https://max578.github.io/masque/reference/read_set.md),
[`write_set()`](https://max578.github.io/masque/reference/write_set.md),
[`audit_mask()`](https://max578.github.io/masque/reference/audit_mask.md),
[`data_card()`](https://max578.github.io/masque/reference/data_card.md),
[`reveal_maps()`](https://max578.github.io/masque/reference/reveal_maps.md).

## Examples

``` r
tables <- list(
  plots = data.frame(
    site = rep(c("A", "B", "C", "D", "E"), each = 2),
    gen = rep(c("x", "y"), 5),
    yield = c(3.1, 2.9, 4.0, 3.7, 3.3, 3.5, 2.8, 3.0, 3.9, 3.6)
  ),
  sites = data.frame(
    site = c("A", "B", "C", "D", "E"),
    rainfall = c(420, 560, 390, 610, 480)
  )
)
roles <- lapply(tables, propose_roles, mode = "collaborate")
roles <- lapply(roles, set_role, "site", action = "alias")
m <- mask_set(tables, roles = roles, seed = 1, quiet = TRUE)
synthetic(m)$plots$site
#>  [1] "site_K002" "site_K002" "site_K001" "site_K001" "site_K005" "site_K005"
#>  [7] "site_K004" "site_K004" "site_K003" "site_K003"
synthetic(m)$sites$site # same aliases -> the join still works
#> [1] "site_K002" "site_K001" "site_K005" "site_K004" "site_K003"
```
