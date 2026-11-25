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
#>  5:    design    noise                                         none
#>  6: treatment     keep                                          all
#>  7: treatment scramble numeric, integer, factor, character, logical
#>  8: treatment    alias numeric, integer, factor, character, logical
#>  9: treatment     drop                                          all
#> 10: treatment    noise                                         none
#> 11:   outcome     keep                                          all
#> 12:   outcome scramble                             numeric, integer
#> 13:   outcome    alias                                         none
#> 14:   outcome     drop                                          all
#> 15:   outcome    noise                             all except other
#> 16: covariate     keep                                          all
#> 17: covariate scramble                             all except other
#> 18: covariate    alias                   factor, character, logical
#> 19: covariate     drop                                          all
#> 20: covariate    noise                             all except other
#> 21:      date     keep                                          all
#> 22:      date scramble                               date, datetime
#> 23:      date    alias                                         none
#> 24:      date     drop                                          all
#> 25:      date    noise                               date, datetime
#> 26:        id     keep                                          all
#> 27:        id scramble                                         none
#> 28:        id    alias          numeric, integer, factor, character
#> 29:        id     drop                                          all
#> 30:        id    noise                                         none
#> 31:      text     keep                                          all
#> 32:      text scramble                             all except other
#> 33:      text    alias                            factor, character
#> 34:      text     drop                                          all
#> 35:      text    noise                                         none
#> 36:     other     keep                                          all
#> 37:     other scramble                                         none
#> 38:     other    alias                                         none
#> 39:     other     drop                                          all
#> 40:     other    noise                                         none
#>          role   action                                        kinds
#>        <char>   <char>                                       <char>
#>                                                                                                                                                                                                                                                   notes
#>                                                                                                                                                                                                                                                  <char>
#>  1:                                                                                                                                                                                                                                                    
#>  2:                                                                                                                    design columns are structure, not content - they cannot be scrambled; use keep, alias (labels hidden, structure intact), or drop
#>  3: design label aliasing requires a factor / character / logical column; numeric design columns can only be kept or dropped. To hide the labels, convert the column to a factor in the data, re-run propose_roles() and set action "alias", or drop it
#>  4:                                                                                                                                                                                                                                                    
#>  5:                                                                                                                       noise replaces values with independent draws and applies to outcome, covariate and date columns only; use keep, alias or drop
#>  6:                                                                                                                                                                                                                                                    
#>  7:                                                                                                                                                                treatment scramble / alias requires a factor / character / logical or numeric column
#>  8:                                                                                                                                                                treatment scramble / alias requires a factor / character / logical or numeric column
#>  9:                                                                                                                                                                                                                                                    
#> 10:                                                                                                                       noise replaces values with independent draws and applies to outcome, covariate and date columns only; use keep, alias or drop
#> 11:                                                                                                                                                                                                                                                    
#> 12:                                                                                                                                           only numeric / integer outcomes can be scrambled; re-role a categorical outcome as treatment or covariate
#> 13:                                                                                                                                                                                           outcomes carry no label vocabulary to alias; use scramble
#> 14:                                                                                                                                                                                                                                                    
#> 15:                                                                                                                                            columns of an unsupported class can only be kept or dropped; masque does not know how to synthesise them
#> 16:                                                                                                                                                                                                                                                    
#> 17:                                                                                                                                            columns of an unsupported class can only be kept or dropped; masque does not know how to synthesise them
#> 18:                                                                                                                                                  covariate aliasing requires a factor / character / logical column; numeric covariates use scramble
#> 19:                                                                                                                                                                                                                                                    
#> 20:                                                                                                                                            columns of an unsupported class can only be kept or dropped; masque does not know how to synthesise them
#> 21:                                                                                                                                                                                                                                                    
#> 22:                                                                                                                           role "date" with scramble requires a Date / POSIX column; parse the column to a date class first, or use role "covariate"
#> 23:                                                                                                                                                 date/time columns carry no label vocabulary to alias; use scramble (row permutation), keep, or drop
#> 24:                                                                                                                                                                                                                                                    
#> 25:                                                                                                                              role "date" with noise requires a Date / POSIX column; parse the column to a date class first, or use role "covariate"
#> 26:                                                                                                                                                                                                                                                    
#> 27:                                                                                                                                               ids cannot be scrambled - permuting identifiers silently breaks row linkage; use alias, keep, or drop
#> 28:                                                                                                                                                                                         id aliasing requires a character, factor, or integer column
#> 29:                                                                                                                                                                                                                                                    
#> 30:                                                                                                                       noise replaces values with independent draws and applies to outcome, covariate and date columns only; use keep, alias or drop
#> 31:                                                                                                                                                                                                                                                    
#> 32:                                                                                                                                            columns of an unsupported class can only be kept or dropped; masque does not know how to synthesise them
#> 33:                                                                                                                                                                                                 text aliasing requires a character or factor column
#> 34:                                                                                                                                                                                                                                                    
#> 35:                                                                                                                       noise replaces values with independent draws and applies to outcome, covariate and date columns only; use keep, alias or drop
#> 36:                                                                                                                                                                                                                                                    
#> 37:                                                                                                                                             columns of unsupported classes can only be kept or dropped; masque does not know how to synthesise them
#> 38:                                                                                                                                             columns of unsupported classes can only be kept or dropped; masque does not know how to synthesise them
#> 39:                                                                                                                                                                                                                                                    
#> 40:                                                                                                                       noise replaces values with independent draws and applies to outcome, covariate and date columns only; use keep, alias or drop
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
#> 10:   outcome    noise                             all except other
#> 11: covariate     keep                                          all
#> 12: covariate scramble                             all except other
#> 13: covariate    alias                   factor, character, logical
#> 14: covariate     drop                                          all
#> 15: covariate    noise                             all except other
#> 16:      date     keep                                          all
#> 17:      date     drop                                          all
#> 18:        id     keep                                          all
#> 19:        id    alias          numeric, integer, factor, character
#> 20:        id     drop                                          all
#> 21:      text     keep                                          all
#> 22:      text scramble                             all except other
#> 23:      text    alias                            factor, character
#> 24:      text     drop                                          all
#> 25:     other     keep                                          all
#> 26:     other     drop                                          all
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
#> 10:                                                                                                                                            columns of an unsupported class can only be kept or dropped; masque does not know how to synthesise them
#> 11:                                                                                                                                                                                                                                                    
#> 12:                                                                                                                                            columns of an unsupported class can only be kept or dropped; masque does not know how to synthesise them
#> 13:                                                                                                                                                  covariate aliasing requires a factor / character / logical column; numeric covariates use scramble
#> 14:                                                                                                                                                                                                                                                    
#> 15:                                                                                                                                            columns of an unsupported class can only be kept or dropped; masque does not know how to synthesise them
#> 16:                                                                                                                                                                                                                                                    
#> 17:                                                                                                                                                                                                                                                    
#> 18:                                                                                                                                                                                                                                                    
#> 19:                                                                                                                                                                                         id aliasing requires a character, factor, or integer column
#> 20:                                                                                                                                                                                                                                                    
#> 21:                                                                                                                                                                                                                                                    
#> 22:                                                                                                                                            columns of an unsupported class can only be kept or dropped; masque does not know how to synthesise them
#> 23:                                                                                                                                                                                                 text aliasing requires a character or factor column
#> 24:                                                                                                                                                                                                                                                    
#> 25:                                                                                                                                                                                                                                                    
#> 26:                                                                                                                                                                                                                                                    
#>                                                                                                                                                                                                                                                   notes
#>                                                                                                                                                                                                                                                  <char>
subset(role_options(), role == "design")
#>      role   action                      kinds
#>    <char>   <char>                     <char>
#> 1: design     keep                        all
#> 2: design scramble                       none
#> 3: design    alias factor, character, logical
#> 4: design     drop                        all
#> 5: design    noise                       none
#>                                                                                                                                                                                                                                                  notes
#>                                                                                                                                                                                                                                                 <char>
#> 1:                                                                                                                                                                                                                                                    
#> 2:                                                                                                                    design columns are structure, not content - they cannot be scrambled; use keep, alias (labels hidden, structure intact), or drop
#> 3: design label aliasing requires a factor / character / logical column; numeric design columns can only be kept or dropped. To hide the labels, convert the column to a factor in the data, re-run propose_roles() and set action "alias", or drop it
#> 4:                                                                                                                                                                                                                                                    
#> 5:                                                                                                                       noise replaces values with independent draws and applies to outcome, covariate and date columns only; use keep, alias or drop
```
