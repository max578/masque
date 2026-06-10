# Set the role and action of one or more columns in a roles table

Ergonomic editor for the two-axis roles table returned by
[`propose_roles()`](https://max578.github.io/masque/reference/propose_roles.md).
Setting a `role` without an explicit `action` re-resolves the action to
the default for the new role, the column's kind, and the mode the table
was proposed for — so a re-roled column never silently carries a stale
action from its previous role.

## Usage

``` r
set_role(roles, cols, role = NULL, action = NULL)
```

## Arguments

- roles:

  A roles table from
  [`propose_roles()`](https://max578.github.io/masque/reference/propose_roles.md)
  (possibly edited).

- cols:

  Character vector of column names to edit. Every entry must be present
  in `roles$col`.

- role:

  Optional single role to assign to all of `cols`. One of `"design"`,
  `"treatment"`, `"outcome"`, `"covariate"`, `"date"`, `"id"`, `"text"`,
  `"other"`.

- action:

  Optional single action to assign to all of `cols`. One of `"keep"`,
  `"scramble"`, `"alias"`, `"drop"`. When `NULL` (the default) and
  `role` was supplied, the action is re-resolved to the default for the
  new role.

## Value

The edited roles table.

## Details

Direct edits (`roles$role[roles$col == "x"] <- "outcome"`) remain fully
supported; this helper exists because a direct role edit leaves
`roles$action` untouched, which is occasionally what you want and
frequently not.

## See also

[`propose_roles()`](https://max578.github.io/masque/reference/propose_roles.md),
[`roles_validate()`](https://max578.github.io/masque/reference/roles_validate.md).

## Examples

``` r
r <- propose_roles(iris)
r <- set_role(r, "Sepal.Length", role = "outcome")
r <- set_role(r, "Species", action = "keep")
r[, c("col", "role", "action")]
#> # A tibble: 5 × 3
#>   col          role      action  
#>   <chr>        <chr>     <chr>   
#> 1 Sepal.Length outcome   scramble
#> 2 Sepal.Width  covariate scramble
#> 3 Petal.Length covariate scramble
#> 4 Petal.Width  covariate scramble
#> 5 Species      treatment keep    
```
