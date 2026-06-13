# Mask a dataset end to end with one guided call

The front door. `masque()` walks the whole procedure - read the data,
propose column roles, (in an interactive session) pause for you to
review the plan, mask, audit, and optionally write the result - from a
single call. It dispatches on the input: a single file or data frame
goes through
[`mask()`](https://max578.github.io/masque/reference/mask.md); a folder,
an Excel workbook, or a named list of tables goes through
[`mask_set()`](https://max578.github.io/masque/reference/mask_set.md).

## Usage

``` r
masque(
  input,
  roles = NULL,
  out = NULL,
  mode = c("local", "collaborate"),
  seed = NULL,
  clean = c("auto", "report", "off"),
  alias_names = FALSE,
  conditional = FALSE,
  ask = interactive(),
  overwrite = FALSE,
  quiet = FALSE
)
```

## Arguments

- input:

  A data frame, a single tabular file (`.csv` / `.tsv` / `.fst`), a
  folder of such files, an Excel workbook, or a named list of data
  frames.

- roles:

  Optional. A roles table (single-table input) or named list of roles
  tables (set input). When supplied, the interactive review is skipped.

- out:

  Optional output path. For a single table, a `.csv` file (or `.xlsx`
  with `writexl`). For a set, a folder (one CSV per table) or an `.xlsx`
  workbook. When `NULL` (default) nothing is written.

- mode:

  Either `"local"` (default) or `"collaborate"`.

- seed:

  Optional integer for reproducibility.

- clean:

  Hygiene mode passed to
  [`clean_table()`](https://max578.github.io/masque/reference/clean_table.md)
  (`"auto"`, `"report"`, `"off"`).

- alias_names:

  Hide column names; see
  [`mask()`](https://max578.github.io/masque/reference/mask.md) /
  [`mask_set()`](https://max578.github.io/masque/reference/mask_set.md).

- conditional:

  Logical scalar (default `FALSE`). The conditional clone mode passed
  through to
  [`mask()`](https://max578.github.io/masque/reference/mask.md) /
  [`mask_set()`](https://max578.github.io/masque/reference/mask_set.md):
  when `TRUE`, numeric columns are re-simulated within each
  treatment-by-design stratum so the treatment-to-outcome relationship
  survives the clone. See
  [`mask()`](https://max578.github.io/masque/reference/mask.md) for the
  full account.

- ask:

  Whether to pause for interactive review when `roles` is not supplied.
  Defaults to
  [`interactive()`](https://rdrr.io/r/base/interactive.html). Set
  `FALSE` to proceed with the proposed plan without prompting.

- overwrite:

  Passed to the writer when `out` is set.

- quiet:

  Suppress progress messages.

## Value

A `masque` object (single-table input) or a `masque_set` object (set
input), invisibly. Use
[`synthetic()`](https://max578.github.io/masque/reference/synthetic.md)
and [`recipe()`](https://max578.github.io/masque/reference/recipe.md).

## Details

It is also fully scriptable. Pass an edited `roles` table (or named list
of them) to skip the interactive review, and an `out` path to write the
masked result in one go. The returned object is the same `masque` /
`masque_set` you would get from the lower-level verbs, so anything you
can do with those you can do with the result here.

## The guided flow

1.  **Read** the input into one or more clean rectangular tables.

2.  **Propose roles** for every column (skipped if you pass `roles`).

3.  **Review** - in an interactive session with no `roles` supplied, the
    proposed plan is printed and you are asked to proceed, edit, or
    stop. Editing opens the roles table in
    [`utils::edit()`](https://rdrr.io/r/utils/edit.html). With
    `ask = FALSE` (the default in non-interactive use) the proposed plan
    is used as-is, with a note.

4.  **Mask** the data in the chosen `mode`.

5.  **Audit** - in `collaborate` mode the leakage audit runs and its
    headline is printed.

6.  **Write** - if `out` is set, the masked data is written there
    (mirroring the input format). The private recipe is never written
    automatically; persist it yourself with
    [`save_recipe()`](https://max578.github.io/masque/reference/save_recipe.md).

## See also

[`mask()`](https://max578.github.io/masque/reference/mask.md),
[`mask_set()`](https://max578.github.io/masque/reference/mask_set.md),
[`propose_roles()`](https://max578.github.io/masque/reference/propose_roles.md),
[`set_role()`](https://max578.github.io/masque/reference/set_role.md),
[`write_set()`](https://max578.github.io/masque/reference/write_set.md),
[`save_recipe()`](https://max578.github.io/masque/reference/save_recipe.md).

## Examples

``` r
# Scripted single-table use (no prompt because roles are supplied):
r <- propose_roles(iris)
r <- set_role(r, "Sepal.Length", role = "outcome")
m <- masque(iris, roles = r, seed = 1, ask = FALSE, quiet = TRUE)
head(synthetic(m))
#> # A tibble: 6 × 5
#>   Sepal.Length Sepal.Width Petal.Length Petal.Width Species
#>          <dbl>       <dbl>        <dbl>       <dbl> <fct>  
#> 1          5.1         3.2          4           1.5 setosa 
#> 2          6           3            3.7         0.4 setosa 
#> 3          5           3            4.6         1.1 setosa 
#> 4          7.2         2.6          5.8         1.7 setosa 
#> 5          6.1         2.4          5.8         1.5 setosa 
#> 6          5           2.7          4.5         1.4 setosa 
```
