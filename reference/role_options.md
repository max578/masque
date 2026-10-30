# List every role and action combination masque accepts

Renders the two-axis vocabulary as a table: every `role` paired with
every `action`, the storage kinds the pair works for, and the reason the
pair is constrained when it is. The table is generated from the same
compatibility rules
[`roles_validate()`](https://max578.github.io/masque/reference/roles_validate.md)
applies at [`mask()`](https://max578.github.io/masque/reference/mask.md)
time, so what it shows is exactly what a roles table is allowed to say.

## Usage

``` r
role_options(kind = NULL)
```

## Arguments

- kind:

  Optional storage kind to filter for: one of `"numeric"`, `"integer"`,
  `"factor"`, `"character"`, `"logical"`, `"date"`, `"datetime"`, or
  `"other"`. When supplied, only the combinations workable for a column
  of that kind are returned. The default `NULL` returns the full grid.

## Value

A data.table with one row per role-action pair and four columns: `role`,
`action`, `kinds` (the storage kinds the pair is valid for: `"all"`,
`"none"`, `"all except other"`, or a comma-separated list), and `notes`
(why the pair is constrained, empty when it is not).

## Details

A column's `kind` is never chosen:
[`propose_roles()`](https://max578.github.io/masque/reference/propose_roles.md)
derives it from the column's class. To move a column to a different
kind, convert the column in the data and re-propose.

## See also

[`propose_roles()`](https://max578.github.io/masque/reference/propose_roles.md),
[`set_role()`](https://max578.github.io/masque/reference/set_role.md),
[`roles_validate()`](https://max578.github.io/masque/reference/roles_validate.md).

## Examples

``` r
role_options()
#>          role   action                                        kinds
#>        <char>   <char>                                       <char>
#>  1:    design     keep                                          all
#>  2:    design scramble                                         none
#>  3:    design    alias                   factor, character, logical
#>  4:    design     drop                                          all
#>  5: treatment     keep                                          all
#>  6: treatment scramble numeric, integer, factor, character, logical
#>  7: treatment    alias numeric, integer, factor, character, logical
#>  8: treatment     drop                                          all
#>  9:   outcome     keep                                          all
#> 10:   outcome scramble                             numeric, integer
#> 11:   outcome    alias                                         none
#> 12:   outcome     drop                                          all
#> 13: covariate     keep                                          all
#> 14: covariate scramble                             all except other
#> 15: covariate    alias                   factor, character, logical
#> 16: covariate     drop                                          all
#> 17:      date     keep                                          all
#> 18:      date scramble                               date, datetime
#> 19:      date    alias                                         none
#> 20:      date     drop                                          all
#> 21:        id     keep                                          all
#> 22:        id scramble                                         none
#> 23:        id    alias          numeric, integer, factor, character
#> 24:        id     drop                                          all
#> 25:      text     keep                                          all
#> 26:      text scramble                             all except other
#> 27:      text    alias                            factor, character
#> 28:      text     drop                                          all
#> 29:     other     keep                                          all
#> 30:     other scramble                                         none
#> 31:     other    alias                                         none
#> 32:     other     drop                                          all
#>          role   action                                        kinds
#>        <char>   <char>                                       <char>
#>                                                                                                                                                                                                                                                   notes
#>                                                                                                                                                                                                                                                  <char>
#>  1:                                                                                                                                                                                                                                                    
#>  2:                                                                                                                    design columns are structure, not content - they cannot be scrambled; use keep, alias (labels hidden, structure intact), or drop
#>  3: design label aliasing requires a factor / character / logical column; numeric design columns can only be kept or dropped. To hide the labels, convert the column to a factor in the data, re-run propose_roles() and set action "alias", or drop it
#>  4:                                                                                                                                                                                                                                                    
#>  5:                                                                                                                                                                                                                                                    
#>  6:                                                                                                                                                                treatment scramble / alias requires a factor / character / logical or numeric column
#>  7:                                                                                                                                                                treatment scramble / alias requires a factor / character / logical or numeric column
#>  8:                                                                                                                                                                                                                                                    
#>  9:                                                                                                                                                                                                                                                    
#> 10:                                                                                                                                           only numeric / integer outcomes can be scrambled; re-role a categorical outcome as treatment or covariate
#> 11:                                                                                                                                                                                           outcomes carry no label vocabulary to alias; use scramble
#> 12:                                                                                                                                                                                                                                                    
#> 13:                                                                                                                                                                                                                                                    
#> 14:                                                                                                                                            columns of an unsupported class can only be kept or dropped; masque does not know how to synthesise them
#> 15:                                                                                                                                                  covariate aliasing requires a factor / character / logical column; numeric covariates use scramble
#> 16:                                                                                                                                                                                                                                                    
#> 17:                                                                                                                                                                                                                                                    
#> 18:                                                                                                                           role "date" with scramble requires a Date / POSIX column; parse the column to a date class first, or use role "covariate"
#> 19:                                                                                                                                                 date/time columns carry no label vocabulary to alias; use scramble (row permutation), keep, or drop
#> 20:                                                                                                                                                                                                                                                    
#> 21:                                                                                                                                                                                                                                                    
#> 22:                                                                                                                                               ids cannot be scrambled - permuting identifiers silently breaks row linkage; use alias, keep, or drop
#> 23:                                                                                                                                                                                         id aliasing requires a character, factor, or integer column
#> 24:                                                                                                                                                                                                                                                    
#> 25:                                                                                                                                                                                                                                                    
#> 26:                                                                                                                                            columns of an unsupported class can only be kept or dropped; masque does not know how to synthesise them
#> 27:                                                                                                                                                                                                 text aliasing requires a character or factor column
#> 28:                                                                                                                                                                                                                                                    
#> 29:                                                                                                                                                                                                                                                    
#> 30:                                                                                                                                             columns of unsupported classes can only be kept or dropped; masque does not know how to synthesise them
#> 31:                                                                                                                                             columns of unsupported classes can only be kept or dropped; masque does not know how to synthesise them
#> 32:                                                                                                                                                                                                                                                    
#>                                                                                                                                                                                                                                                   notes
#>                                                                                                                                                                                                                                                  <char>
role_options(kind = "factor")
#>          role   action                                        kinds
#>        <char>   <char>                                       <char>
#>  1:    design     keep                                          all
#>  2:    design    alias                   factor, character, logical
#>  3:    design     drop                                          all
#>  4: treatment     keep                                          all
#>  5: treatment scramble numeric, integer, factor, character, logical
#>  6: treatment    alias numeric, integer, factor, character, logical
#>  7: treatment     drop                                          all
#>  8:   outcome     keep                                          all
#>  9:   outcome     drop                                          all
#> 10: covariate     keep                                          all
#> 11: covariate scramble                             all except other
#> 12: covariate    alias                   factor, character, logical
#> 13: covariate     drop                                          all
#> 14:      date     keep                                          all
#> 15:      date     drop                                          all
#> 16:        id     keep                                          all
#> 17:        id    alias          numeric, integer, factor, character
#> 18:        id     drop                                          all
#> 19:      text     keep                                          all
#> 20:      text scramble                             all except other
#> 21:      text    alias                            factor, character
#> 22:      text     drop                                          all
#> 23:     other     keep                                          all
#> 24:     other     drop                                          all
#>          role   action                                        kinds
#>        <char>   <char>                                       <char>
#>                                                                                                                                                                                                                                                   notes
#>                                                                                                                                                                                                                                                  <char>
#>  1:                                                                                                                                                                                                                                                    
#>  2: design label aliasing requires a factor / character / logical column; numeric design columns can only be kept or dropped. To hide the labels, convert the column to a factor in the data, re-run propose_roles() and set action "alias", or drop it
#>  3:                                                                                                                                                                                                                                                    
#>  4:                                                                                                                                                                                                                                                    
#>  5:                                                                                                                                                                treatment scramble / alias requires a factor / character / logical or numeric column
#>  6:                                                                                                                                                                treatment scramble / alias requires a factor / character / logical or numeric column
#>  7:                                                                                                                                                                                                                                                    
#>  8:                                                                                                                                                                                                                                                    
#>  9:                                                                                                                                                                                                                                                    
#> 10:                                                                                                                                                                                                                                                    
#> 11:                                                                                                                                            columns of an unsupported class can only be kept or dropped; masque does not know how to synthesise them
#> 12:                                                                                                                                                  covariate aliasing requires a factor / character / logical column; numeric covariates use scramble
#> 13:                                                                                                                                                                                                                                                    
#> 14:                                                                                                                                                                                                                                                    
#> 15:                                                                                                                                                                                                                                                    
#> 16:                                                                                                                                                                                                                                                    
#> 17:                                                                                                                                                                                         id aliasing requires a character, factor, or integer column
#> 18:                                                                                                                                                                                                                                                    
#> 19:                                                                                                                                                                                                                                                    
#> 20:                                                                                                                                            columns of an unsupported class can only be kept or dropped; masque does not know how to synthesise them
#> 21:                                                                                                                                                                                                 text aliasing requires a character or factor column
#> 22:                                                                                                                                                                                                                                                    
#> 23:                                                                                                                                                                                                                                                    
#> 24:                                                                                                                                                                                                                                                    
#>                                                                                                                                                                                                                                                   notes
#>                                                                                                                                                                                                                                                  <char>
subset(role_options(), role == "design")
#>      role   action                      kinds
#>    <char>   <char>                     <char>
#> 1: design     keep                        all
#> 2: design scramble                       none
#> 3: design    alias factor, character, logical
#> 4: design     drop                        all
#>                                                                                                                                                                                                                                                  notes
#>                                                                                                                                                                                                                                                 <char>
#> 1:                                                                                                                                                                                                                                                    
#> 2:                                                                                                                    design columns are structure, not content - they cannot be scrambled; use keep, alias (labels hidden, structure intact), or drop
#> 3: design label aliasing requires a factor / character / logical column; numeric design columns can only be kept or dropped. To hide the labels, convert the column to a factor in the data, re-run propose_roles() and set action "alias", or drop it
#> 4:                                                                                                                                                                                                                                                    
```
