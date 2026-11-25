# Derive null, negative and positive controls from a table

Builds the control datasets a
[`control_spec()`](https://max578.github.io/masque/reference/control_spec.md)
declares, from any table with a role table: a synthetic clone, a
comparator's clone, or, on the owner's side, the original. Nothing is
re-simulated. Three kinds of control exist, each with a known truth:

## Usage

``` r
controls(df, roles, spec = NULL, events = NULL, seed = NULL, recipe = NULL)
```

## Arguments

- df:

  The table to derive controls from: a data frame or data.table.

- roles:

  Its role table, as returned by
  [`roles()`](https://max578.github.io/masque/reference/roles.md) for a
  clone or by
  [`propose_roles()`](https://max578.github.io/masque/reference/propose_roles.md)
  and
  [`set_role()`](https://max578.github.io/masque/reference/set_role.md)
  for any table. Or a plan: the analyst passes
  [`clone_plan()`](https://max578.github.io/masque/reference/clone_plan.md)
  with the clone, the owner passes the plan and the `recipe` with the
  real table.

- spec:

  A
  [`control_spec()`](https://max578.github.io/masque/reference/control_spec.md).
  With a plan in `roles`, the name of one of its specs, or `NULL` when
  it holds exactly one.

- events:

  Linked time/status pairs among the outcome columns, in the form
  [`mask()`](https://max578.github.io/masque/reference/mask.md) takes.
  The null permutes each pair as one block. `NULL` when there are none.

- seed:

  A private integer seed for the permutations that overrides the spec's
  seed, for the owner's side; `NULL` uses the spec's seed, or with a
  `recipe` the recipe's key. A value equal to the spec's seed is refused
  there. See "Two sides, two seeds" for what an integer can and cannot
  hide.

- recipe:

  With a plan in `roles`, the recipe of the clone. `df` is then the real
  table: its cleaning and conformance are replayed as in
  [`apply_recipe()`](https://max578.github.io/masque/reference/apply_recipe.md),
  a table with a different schema, NA mask or values is refused, and a
  spec that differs from the one fixed at
  [`mask()`](https://max578.github.io/masque/reference/mask.md) is
  refused.

## Value

A `masque_controls` object: the resolved spec (`@spec`), the manifest
(`@manifest`, one row per dataset), the truth table (`@truth`, one row
per target and level of `on`) and the notes (`@notes`). Datasets are
produced by
[`control_table()`](https://max578.github.io/masque/reference/control_table.md).

## Details

- `null`: every analysed column (outcome, covariate and date columns
  with action `scramble` or `alias`) is permuted independently over its
  non-missing rows; a column declared unit-grained is permuted across
  its units and stays constant within each. Design, treatment and kept
  columns, the NA mask and every column's multiset of values are kept.
  No association among analysed columns, or with the treatment, remains.
  Use it as a smoke test: a pipeline that finds signal here builds that
  signal itself. A leak already in the table, such as a covariate that
  copies the outcome, is shuffled away with the rest and passes.

- `negative`: the declared column `on` alone is permuted within the
  declared design strata, at its unit, while the design structure and
  all other associations are kept. The outcome is not changed, so any
  real effect of `on` stays in it as unexplained variation. Choose
  strata that every level of `on` can reach. Complete replicates
  qualify. Within incomplete blocks each block keeps its set of levels,
  so part of the real effect of `on` survives. With `n` replicates it
  gives a permutation null for a whole pipeline: a false-positive rate,
  a permutation p-value.

- `positive`: the same permutation as the negative replicate, plus the
  declared shift per level of `on` on each target, in units of the
  target's standard deviation in the table at hand. Positive minus
  negative is the planted truth, exactly.

## Declaration before data

The spec is resolved against the table here: `on` defaults to the single
treatment column; strata and unit are checked for nesting; an `effect`
given as `list(sd = )` is drawn under the spec's seed, once, so the same
spec plants the same vector on every table it meets. The resolved spec
and the truth table are on the returned object and in its print.

## Two sides, two seeds

An analyst who holds only the clone runs this on the clone. The owner
runs it on the original, offline, on a private draw (the planted vector
still comes from the spec's seed). A public seed would let anyone who
knows the design, which the clone shares, rebuild every permutation and
read the original outcome out of per-replicate statistics.

With a plan and its `recipe`, the permutations come from SHA-256 of a
256-bit key the recipe holds, so there is no seed to search. A private
integer `seed` is the weaker route: it has at most 31 bits, and anyone
given a per-replicate statistic can try each value, because the true
seed fits the statistic exactly and a wrong one does not.

Control tables built from an original never leave the owner. What may
leave goes through the owner's usual output checking, classed by what it
estimates. The false-positive rate says little about the real outcome.
The rate at which the positives find the shift depends on the residual
variance. The permutation p-value is the result of the analyst's test on
the real table. A vector of per-replicate means or contrasts is not an
aggregate, under either route, and every further pipeline run on the
original is another set of queries.

## Limits

A kept column is structure and is never permuted, so leakage through
kept columns, ids or row order passes the null. No control can detect
confounding. A planted effect is clean: uniform within a level, with no
confounding and no interaction. Nothing is clipped, so a shift can take
a non-negative outcome below zero;
[`control_table()`](https://max578.github.io/masque/reference/control_table.md)
warns when it does. The null collapses the design means of row-grained
outcomes, so false-positive calibration comes from the negative control,
not the null.

A negative control is a test of the stated size for a comparison that
uses only contrasts within the strata, so the analysis needs the strata
in its model. Permuting within replicates and fitting no replicate term
puts the replicate variance in the residual and rejects far less often
than the nominal level. A shared rate on the clone and the original
shows that the two agree, and a rate of zero on both says nothing about
calibration. A warning (class `masque_control_unit_small`) marks units
and strata with too few arrangements for a 5 percent level, and another
(class `masque_control_strata_weak`) marks strata that hold one level of
`on`.

## See also

[`control_spec()`](https://max578.github.io/masque/reference/control_spec.md),
[`control_table()`](https://max578.github.io/masque/reference/control_table.md),
[`mask()`](https://max578.github.io/masque/reference/mask.md),
[`roles()`](https://max578.github.io/masque/reference/roles.md).

## Examples

``` r
trial <- read.csv(system.file("extdata", "john_alpha.csv", package = "masque"))
r <- propose_roles(trial, detect = FALSE)
r <- set_role(r, c("rep", "block"), role = "design", action = "keep")
r <- set_role(r, "gen", role = "treatment", action = "keep")
r <- set_role(r, "yield", role = "outcome", action = "scramble")
r <- set_role(r, c("plot", "row", "col"), role = "id", action = "keep")
spec <- control_spec(
  on = "gen", target = "yield", effect = list(sd = 0.5),
  strata = "rep", n = 5L, seed = 2026L
)
ctl <- controls(trial, r, spec)
ctl
#> 
#> ── masque_controls ─────────────────────────────────────────────────────────────
#> • Table: 72 rows, 7 columns; 1 analysed column
#> • Permuted column (on): gen
#> • Strata: rep (3 strata; on constant in 0% of them)
#> • Unit of on: row
#> • Datasets: 1 null, 5 negative, 5 positive
#> • Seeds: present
#> 
#> ── Planted truth (positive minus negative, per level of on) ──
#> 
#>     target  level   effect_sd      sd_y sd_within_strata shift_realised
#>     <char> <char>       <num>     <num>            <num>          <num>
#>  1:  yield    G01 -0.03745223 0.6098138        0.5342823   -0.022838885
#>  2:  yield    G02  0.56766062 0.6098138        0.5342823    0.346167271
#>  3:  yield    G03 -0.21139985 0.6098138        0.5342823   -0.128914539
#>  4:  yield    G04  0.89984969 0.6098138        0.5342823    0.548740740
#>  5:  yield    G05 -0.83607365 0.6098138        0.5342823   -0.509849235
#>  6:  yield    G06 -0.42709968 0.6098138        0.5342823   -0.260451271
#>  7:  yield    G07 -0.71390819 0.6098138        0.5342823   -0.435351051
#>  8:  yield    G08  0.05738311 0.6098138        0.5342823    0.034993014
#>  9:  yield    G09 -0.17170680 0.6098138        0.5342823   -0.104709173
#> 10:  yield    G10 -0.09379528 0.6098138        0.5342823   -0.057197657
#> 11:  yield    G11  0.58356951 0.6098138        0.5342823    0.355868733
#> 12:  yield    G12  0.01544342 0.6098138        0.5342823    0.009417613
#> 13:  yield    G13 -0.82322128 0.6098138        0.5342823   -0.502011682
#> 14:  yield    G14  0.79197658 0.6098138        0.5342823    0.482958232
#> 15:  yield    G15 -0.89720309 0.6098138        0.5342823   -0.547126811
#> 16:  yield    G16 -0.39186317 0.6098138        0.5342823   -0.238963563
#> 17:  yield    G17 -0.08066037 0.6098138        0.5342823   -0.049187806
#> 18:  yield    G18  0.04951500 0.6098138        0.5342823    0.030194930
#> 19:  yield    G19  0.18612377 0.6098138        0.5342823    0.113500839
#> 20:  yield    G20 -0.11157845 0.6098138        0.5342823   -0.068042078
#> 21:  yield    G21 -0.20408017 0.6098138        0.5342823   -0.124450900
#> 22:  yield    G22  0.11109054 0.6098138        0.5342823    0.067744544
#> 23:  yield    G23  0.31921234 0.6098138        0.5342823    0.194660083
#> 24:  yield    G24 -0.24466831 0.6098138        0.5342823   -0.149202110
#>     target  level   effect_sd      sd_y sd_within_strata shift_realised
#>     <char> <char>       <num>     <num>            <num>          <num>
head(control_table(ctl, "positive", 1L))
#>     plot    rep  block    gen    yield   row   col
#>    <int> <char> <char> <char>    <num> <int> <int>
#> 1:     1     R1     B1    G15 3.570073     1     1
#> 2:     2     R1     B1    G04 4.994841     2     1
#> 3:     3     R1     B1    G16 5.636736     3     1
#> 4:     4     R1     B1    G18 4.608595     4     1
#> 5:     5     R1     B2    G08 4.688993     5     1
#> 6:     6     R1     B2    G21 4.049149     6     1
```
