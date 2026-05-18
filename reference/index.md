# Package index

## Role discovery

Inspect a data frame and decide what each column is.

- [`propose_roles()`](https://max578.github.io/masque/reference/propose_roles.md)
  : Propose role classifications for the columns of a data frame
- [`roles_validate()`](https://max578.github.io/masque/reference/roles_validate.md)
  : Validate a roles tibble

## Design detection

Identify the experimental design and visualise it for sanity.

- [`detect_design()`](https://max578.github.io/masque/reference/detect_design.md)
  : Detect the experimental-design structure of a data frame
- [`plot_design_summary()`](https://max578.github.io/masque/reference/plot_design_summary.md)
  : Sanity-check visualisation for a detected design

## Masking

Produce a structurally faithful synthetic clone of one tabular dataset.

- [`mask()`](https://max578.github.io/masque/reference/mask.md) : Mask a
  tabular dataset into a structurally faithful development surrogate
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

Re-anchor synthetic coordinates at plausible-but-fake locations while
preserving site-count clustering.

- [`synthesise_geospatial()`](https://max578.github.io/masque/reference/synthesise_geospatial.md)
  : Re-anchor synthetic geospatial coordinates at plausible-but-fake
  locations

## Package

- [`masque`](https://max578.github.io/masque/reference/masque-package.md)
  [`masque-package`](https://max578.github.io/masque/reference/masque-package.md)
  : masque: Structurally Faithful Development Surrogates for Tabular
  Data
