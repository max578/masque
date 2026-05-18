# Validate a roles tibble

Fail-closed validation of a `roles` tibble before
[`mask()`](https://max578.github.io/masque/reference/mask.md) consumes
it. Errors are raised for every misuse the v0.2 spec calls out.

## Usage

``` r
roles_validate(roles, df = NULL)
```

## Arguments

- roles:

  A tibble produced by
  [`propose_roles()`](https://max578.github.io/masque/reference/propose_roles.md)
  (possibly edited).

- df:

  Optional data frame. If supplied, `roles` is checked for one-to-one
  column-name correspondence with `df`.

## Value

`roles`, invisibly.

## Details

Hard errors:

- missing required columns (`col`, `role`, `kind`);

- unknown role string (not in
  `c("design","treatment","outcome","covariate","ignore")`);

- any `NA` role;

- zero columns flagged `outcome`;

- more than one column flagged `treatment` (joint-treatment masking is
  not yet supported by
  [`mask()`](https://max578.github.io/masque/reference/mask.md));

- duplicate `col` entries;

- if `df` supplied: any `df` column missing from `roles`, or any `roles`
  column missing from `df`.

Returns the validated `roles` invisibly (mirrors `stopifnot`-style use).

## See also

[`propose_roles()`](https://max578.github.io/masque/reference/propose_roles.md).

## Examples

``` r
r <- propose_roles(iris)
r$role[r$col == "Sepal.Length"] <- "outcome"
roles_validate(r, iris)
```
