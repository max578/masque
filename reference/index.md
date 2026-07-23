# Package index

## Guided masking

The one-call front door for a table, a folder, or a workbook.

- [`masque()`](https://max578.github.io/masque/reference/masque.md) :
  Mask a dataset end to end with one guided call

## Role discovery

Inspect a data frame and decide what each column is and how to mask it.

- [`propose_roles()`](https://max578.github.io/masque/reference/propose_roles.md)
  : Propose role and action classifications for the columns of a data
  frame
- [`set_role()`](https://max578.github.io/masque/reference/set_role.md)
  : Set the role and action of one or more columns in a roles table
- [`role_options()`](https://max578.github.io/masque/reference/role_options.md)
  : List every role and action combination masque accepts
- [`roles_validate()`](https://max578.github.io/masque/reference/roles_validate.md)
  : Validate a roles table
- [`clean_table()`](https://max578.github.io/masque/reference/clean_table.md)
  : Tidy a dirty table's column names and category labels before masking

## Design detection

Identify environment scope and experimental design, then visualise both
for sanity.

- [`detect_design()`](https://max578.github.io/masque/reference/detect_design.md)
  : Detect environment scope and experimental-design structure
- [`plot_design_summary()`](https://max578.github.io/masque/reference/plot_design_summary.md)
  : Sanity-check visualisation for detected scope and design

## Masking

Produce a structurally faithful synthetic clone of one or many tables.

- [`mask()`](https://max578.github.io/masque/reference/mask.md) : Mask a
  tabular dataset into a structurally faithful development surrogate
- [`mask_set()`](https://max578.github.io/masque/reference/mask_set.md)
  : Mask a multi-table set with cross-table-consistent aliasing
- [`read_set()`](https://max578.github.io/masque/reference/read_set.md)
  : Read a set of tables from a folder, an Excel workbook, or a list
- [`write_set()`](https://max578.github.io/masque/reference/write_set.md)
  : Write a masked set to disk, mirroring the input format
- [`synthetic()`](https://max578.github.io/masque/reference/synthetic.md)
  : Extract the synthetic data from a masque object
- [`recipe()`](https://max578.github.io/masque/reference/recipe.md) :
  Extract the recipe from a masque object

## Recipe round-trip

Persist a recipe and re-target a pipeline between original and
synthetic.

- [`save_recipe()`](https://max578.github.io/masque/reference/save_recipe.md)
  : Save a masque recipe to disk
- [`read_recipe()`](https://max578.github.io/masque/reference/read_recipe.md)
  : Read a masque recipe from disk
- [`apply_recipe()`](https://max578.github.io/masque/reference/apply_recipe.md)
  : Translate a data frame into the synthetic namespace
- [`unmask()`](https://max578.github.io/masque/reference/unmask.md) :
  Translate data from the synthetic namespace back to the original
- [`reveal_maps()`](https://max578.github.io/masque/reference/reveal_maps.md)
  : Reveal the level maps held inside a recipe

## Leakage audit

Check a synthetic for residual structural leakage.

- [`audit_mask()`](https://max578.github.io/masque/reference/audit_mask.md)
  : Audit a masque object for leakage and shareability risks

## Geospatial post-processing

Coarsen or re-anchor synthetic coordinates while keeping them on land
and plausible.

- [`jitter_coordinates()`](https://max578.github.io/masque/reference/jitter_coordinates.md)
  : Coarsen geographic coordinates by an on-land privacy jitter
- [`synthesise_geospatial()`](https://max578.github.io/masque/reference/synthesise_geospatial.md)
  : Re-anchor synthetic geospatial coordinates at plausible-but-fake
  locations

## Package

- [`masque-package`](https://max578.github.io/masque/reference/masque-package.md)
  : masque: Structurally Faithful Development Surrogates for Tabular
  Data
