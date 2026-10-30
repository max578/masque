# Write a data card for a masked clone

Describes a clone in a data card (card version 0.1): its size, its
design columns and, for each column, a role, a kind and counts. An
analysis planner can read the card in place of the data. No value of any
column is written: a factor's levels are counted, never listed.

## Usage

``` r
data_card(
  m,
  file = NULL,
  name = NULL,
  env = NULL,
  spatial = NULL,
  unit = NULL,
  primary_event = 1L
)
```

## Arguments

- m:

  A `masque` object from
  [`mask()`](https://max578.github.io/masque/reference/mask.md), or a
  `masque_set` from
  [`mask_set()`](https://max578.github.io/masque/reference/mask_set.md).

- file:

  Where to write the card in YAML, or `NULL` (the default) to write
  nothing. For a set, a directory, which receives one file per table
  named `<table>.data_card.yaml`.

- name:

  The table name on the card. Defaults to `"clone"` for a single table,
  and to the table names for a set (where `name` may give one name per
  table, in order). A name must start with a letter and hold only
  letters, digits, `_` and `.`. Any other name is refused with
  `masque_bad_card_name_refusal`, never cleaned.

- env, spatial, unit:

  Optional names of clone columns: the environment columns (trials,
  sites, years), the columns giving a spatial or temporal position, and
  the one column identifying the unit of repeated measurement.
  Environment columns must have the role `design`. For a set, a named
  list giving the columns per table. A name that is not a column of the
  clone is refused with `masque_bad_card_column_refusal`.

- primary_event:

  Which event pair of the first `events` spec is the card's event time
  and status, counted in the order the events occur. Ignored when the
  clone has no `events` spec.

## Value

The card as a list, invisibly when `file` is given. For a set, a named
list of cards, one per table.

## Details

The card is computed from the clone alone:
[`synthetic()`](https://max578.github.io/masque/reference/synthetic.md),
the role table from
[`roles()`](https://max578.github.io/masque/reference/roles.md), the
mode, the package version and the column names of any `events` spec
given to [`mask()`](https://max578.github.io/masque/reference/mask.md).
No other part of the private recipe is read, so the card can travel with
the clone. On a clone whose column names were aliased, the card uses the
aliases throughout.

## Design block

The design block is copied from the role table, never re-detected. The
treatment columns are those with the role `treatment`, and the block
columns those with the role `design`, less any named in `env`, `spatial`
or `unit`. Environment, spatial and unit columns are named by the
caller, since the role table does not tell them apart from blocks. No
design class is written. For a linked-event spec, the event pair chosen
by `primary_event` gives the event time and status columns, the other
status columns of that spec are listed as competing, and the card
records the number of rows with the primary status equal to 1 and the
share of rows with neither the primary nor a competing event (censored).

## Provenance

Every statistic carries a provenance class.

- `structure`: exact in the clone, so equal to the same statistic on the
  original table. Row and column counts, missing counts and shares, the
  level counts and zero shares of kept and aliased columns and of event
  status columns, the treatment, block and event columns, the
  environment count and the event count.

- `clone_estimate`: re-simulated, so approximate. The level counts and
  zero shares of scrambled columns, including event times, and the
  censored share.

- `analyst`: named in this call: the environment, spatial and unit
  columns.

## The YAML file

The card is written by a small deterministic writer: keys in the order
of the contract, every string double-quoted and escaped, counts as
integers, shares with six decimals, UTF-8 with `\n` line ends. The same
clone gives the same bytes.

## See also

[`roles()`](https://max578.github.io/masque/reference/roles.md),
[`synthetic()`](https://max578.github.io/masque/reference/synthetic.md),
[`mask()`](https://max578.github.io/masque/reference/mask.md),
[`mask_set()`](https://max578.github.io/masque/reference/mask_set.md).

## Examples

``` r
r <- propose_roles(iris)
r <- set_role(r, "Species", role = "treatment", action = "alias")
r <- set_role(r, "Sepal.Length", role = "outcome")
m <- mask(iris, r, seed = 1)
card <- data_card(m)
card$table
#> $name
#> [1] "clone"
#> 
#> $source
#> [1] "clone"
#> 
#> $n_rows
#> [1] 150
#> 
#> $n_cols
#> [1] 5
#> 
#> $provenance
#> $provenance$n_rows
#> [1] "structure"
#> 
#> $provenance$n_cols
#> [1] "structure"
#> 
#> 
card$design
#> $treatment_cols
#> [1] "Species"
#> 
#> $provenance
#> $provenance$treatment_cols
#> [1] "structure"
#> 
#> 

path <- tempfile(fileext = ".yaml")
data_card(m, file = path)
head(readLines(path), 12)
#>  [1] "card_version: \"0.1\""     "produced_by:"             
#>  [3] "  package: \"masque\""     "  version: \"0.16.0\""    
#>  [5] "  mode: \"local\""         "table:"                   
#>  [7] "  name: \"clone\""         "  source: \"clone\""      
#>  [9] "  n_rows: 150"             "  n_cols: 5"              
#> [11] "  provenance:"             "    n_rows: \"structure\""
```
