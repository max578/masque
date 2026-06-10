# Validate a roles table

Fail-closed validation of a two-axis `roles` table before
[`mask()`](https://max578.github.io/masque/reference/mask.md) consumes
it. Returns the validated table - with any `NA` actions resolved to
their (role, kind, mode) defaults - so callers can use the return value
directly.

## Usage

``` r
roles_validate(roles, df = NULL, mode = NULL)
```

## Arguments

- roles:

  A roles table from
  [`propose_roles()`](https://max578.github.io/masque/reference/propose_roles.md)
  (possibly edited), or a v1 roles tibble (deprecated, upgraded with a
  warning).

- df:

  Optional data frame. If supplied, `roles` is checked for one-to-one
  column-name correspondence with `df`.

- mode:

  Optional mode (`"local"` or `"collaborate"`) used to resolve `NA`
  actions and to upgrade v1 tables. Defaults to `attr(roles, "mode")`,
  falling back to `"local"`.

## Value

The validated (and possibly upgraded / resolved) roles table, invisibly.

## Details

Tables produced by masque 0.5.0 and earlier (no `action` column; v1
vocabulary with `keep` / `ignore` roles and the optional `mask_levels`
column) are upgraded in place with a deprecation warning. The upgrade
preserves the v1 semantics exactly: v1 `keep` becomes action `keep`; v1
`ignore` becomes role `id` / `text` / `other` with action `keep` in
local mode and `drop` in collaborate mode; v1 treatment
`mask_levels = "permute"` becomes action `scramble`.

Hard errors:

- missing required columns (`col`, `role`, `action`, `kind`);

- unknown role (not in `design`, `treatment`, `outcome`, `covariate`,
  `date`, `id`, `text`, `other`) or unknown action (not in `keep`,
  `scramble`, `alias`, `drop`);

- any `NA` role (an `NA` *action* is allowed - it resolves to the
  default for the row's role and kind);

- an incompatible (role, action, kind) combination, e.g. `design` +
  `scramble`, numeric + `alias`, `id` + `scramble`, `other` + anything
  but keep / drop;

- duplicate `col` entries;

- if `df` supplied: any `df` column missing from `roles`, or any `roles`
  column missing from `df`.

Loud advisories (warnings, not errors):

- every action is `keep` - the "synthetic" would equal the original
  byte-for-byte;

- the table was proposed for one mode but is being validated for another
  (actions are taken as-is; defaults are not re-resolved).

## See also

[`propose_roles()`](https://max578.github.io/masque/reference/propose_roles.md),
[`set_role()`](https://max578.github.io/masque/reference/set_role.md).

## Examples

``` r
r <- propose_roles(iris)
r <- set_role(r, "Sepal.Length", role = "outcome")
roles_validate(r, iris)
```
