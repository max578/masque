# Confidentiality and the threat model

## What masque protects, and what it does not

`masque` is **not** a privacy-preserving or differential-privacy tool.
It is a structurally faithful development surrogate. Read this vignette
before sharing any `masque` output beyond your own machine.

The recipe returned by
[`mask()`](https://max578.github.io/masque/reference/mask.md) is at
least as sensitive as the original data. The whole design assumes that
only the *synthetic* crosses the trust boundary and the recipe stays
with the custodian.

| Actor holds | Wants to learn | What `masque` protects |
|----|----|----|
| Synthetic only | Original raw values | Aliased treatment and categorical vocabularies, jittered numerics, dropped ids and free text, and optionally the column names |
| Synthetic + recipe | Original raw values | Nothing – the combination is as sensitive as the original |
| Recipe only | Original raw values | Nothing useful – the recipe is meaningless without the synthetic |
| Synthetic + external side information | Identity of treatments / sites | Only the label vocabulary. A preserved design footprint or a `keep` column is recognisable, and side information wins |

What `masque` does: it preserves enough structure for pipelines to run
unchanged, exposes the privacy-versus-fidelity trade-off through two
explicit modes, records every translation in a private recipe that
round-trips, and audits its own output before you share it.

What `masque` does not do: it gives no differential-privacy guarantee,
it does not make output safe for public release, it does not hide rare
strata, small designs, or operational metadata such as small
site-by-year combinations or contact names, and it does not rewrite
pipeline source code.

## Two axes of control: roles and actions

Since version 0.6.0, every column carries a `role` (what it is) and an
`action` (how deeply it is masked). The mode sets the default action per
role. You override any column you like. The four actions are the privacy
dial:

| Action | Effect | Vocabulary visible? |
|----|----|----|
| `keep` | byte-identical pass-through | yes – real values published |
| `scramble` | re-simulate numerics and row-permute categoricals / dates | yes – labels stay, assignment moves |
| `alias` | scramble, then replace labels with opaque codes | no |
| `drop` | column omitted from the synthetic | n/a |

The mode chooses sensible defaults so the common case is safe without
per-column work:

| Knob | `mode = "local"` | `mode = "collaborate"` |
|----|----|----|
| Treatment labels | kept | aliased (`trt_001`) |
| Categorical covariate labels | kept | aliased (`<col>_L001`) |
| Date / time columns | row-permuted with class preserved | row-permuted with class preserved |
| Identifiers (`id`) | kept | dropped |
| Free text (`text`) | kept | dropped |
| Numeric synthesis | empirical-quantile (may emit observed values) | empirical-quantile plus within-resolution jitter, with integers stochastically rounded |
| NA mask | preserved cell-by-cell | preserved cell-by-cell |
| [`audit_mask()`](https://max578.github.io/masque/reference/audit_mask.md) | on demand | automatic at [`mask()`](https://max578.github.io/masque/reference/mask.md) time |
| `print(recipe)` | redacted | redacted, with explicit [`reveal_maps()`](https://max578.github.io/masque/reference/reveal_maps.md) to inspect |

## Depth controls

Two further controls sharpen the depth where the defaults are not
enough.

**Hiding column names.** Names themselves can identify a column
(`roseworthy_yield`). `mask(..., alias_names = TRUE)` replaces every
retained column name with an opaque code, which the recipe inverts on
the round-trip. Pass a character vector to hide only some names.

**Hiding design structure.** Design columns are byte-identical by
default, which preserves the experimental layout exactly – and a
publicly registered trial layout is a fingerprint. To keep the structure
but hide the site or block *labels*, set a design column’s action to
`alias`:

``` r

df <- data.frame(
  site = factor(rep(c("Roseworthy", "Minnipa", "Turretfield"), each = 6)),
  rep = rep(1:3, 6),
  yield = rnorm(18)
)
roles <- propose_roles(df, detect = FALSE)
roles <- set_role(roles, "site", role = "design", action = "alias")
s <- synthetic(mask(df, roles, mode = "collaborate", seed = 1))
unique(as.character(s$site))   # real site names gone
#> [1] "site_D002" "site_D001" "site_D003"
table(s$site)                  # ... but the three-site structure intact
#> 
#> site_D001 site_D002 site_D003 
#>         6         6         6
```

This knowingly breaks byte-identity, so it is never a default – you ask
for it explicitly.

## The conditional clone: preserving the treatment effect

The default numeric synthesis re-simulates every scrambled numeric
column from a single global Gaussian copula. That preserves each
column’s marginal distribution and the global covariance, which is
enough to develop most pipelines – but it severs the relationship
between treatment and outcome. The synthetic outcomes are drawn from the
pooled distribution and the treatment labels are relabelled
independently, so a causal model fitted on the clone sees no association
between an arm and its response. A pipeline whose whole purpose is to
estimate a treatment effect would silently give the wrong answer on such
a clone.

The `conditional = TRUE` argument fixes this. It fits and samples the
copula *within each treatment-by-design stratum* rather than pooling, so
a row’s synthetic outcome inherits the location of the treatment that
row carries. The treatment-to-outcome map – the quantity a causal model
reads – survives the clone, within sampling tolerance. This is the
data-side analogue of preserving a conditional mean embedding rather
than a pooled marginal.

The contrast is easiest to see on a two-arm trial with a known effect:

``` r

set.seed(42)
n <- 600
arm <- factor(rep(c("ctrl", "treat"), each = n / 2))
# A real +5-unit effect of the treated arm on yield.
yield <- 10 + 5 * (arm == "treat") + rnorm(n, sd = 2)
trial <- data.frame(genotype = arm, yield = yield)

roles <- propose_roles(trial, detect = FALSE)
roles <- set_role(roles, "genotype", role = "treatment", action = "scramble")
roles <- set_role(roles, "yield", role = "outcome")

true_effect <- coef(lm(yield ~ genotype, trial))[["genotypetreat"]]
true_effect
#> [1] 4.988538
```

Cloning both ways from the same seed, then re-estimating the effect on
each clone:

``` r

marg <- suppressWarnings(
  mask(trial, roles, mode = "local", seed = 1, conditional = FALSE)
)
cond <- suppressWarnings(
  mask(trial, roles, mode = "local", seed = 1, conditional = TRUE)
)

effect_of <- function(m) {
  coef(lm(yield ~ genotype, synthetic(m)))[["genotypetreat"]]
}

data.frame(
  clone = c("marginal (default)", "conditional"),
  estimated_effect = c(effect_of(marg), effect_of(cond)),
  true_effect = true_effect
)
#>                clone estimated_effect true_effect
#> 1 marginal (default)        0.2486581    4.988538
#> 2        conditional        5.1382869    4.988538
```

The marginal clone collapses the effect toward zero. The conditional
clone recovers it. Both clones still match the pooled marginal of the
outcome:

``` r

data.frame(
  source = c("original", "marginal clone", "conditional clone"),
  mean_yield = c(
    mean(trial$yield), mean(synthetic(marg)$yield),
    mean(synthetic(cond)$yield)
  ),
  sd_yield = c(
    sd(trial$yield), sd(synthetic(marg)$yield),
    sd(synthetic(cond)$yield)
  )
)
#>              source mean_yield sd_yield
#> 1          original   12.45071 3.182635
#> 2    marginal clone   12.49563 3.082971
#> 3 conditional clone   12.49687 3.199323
```

The conditioning columns – the treatment plus any retained design
columns – are recorded on the recipe, so the choice is auditable:

``` r

recipe(cond)@conditional
#> [1] TRUE
recipe(cond)@conditioning_cols
#> [1] "genotype"
```

Conditional cloning composes with both modes and with
[`mask_set()`](https://max578.github.io/masque/reference/mask_set.md)
(each table is stratified by its own treatment and design columns). It
needs enough rows per stratum to fit a stratum-local copula. Cells
smaller than a handful of rows are pooled into a graceful global
fallback rather than failing, and with no treatment or design column to
condition on the path degrades cleanly to the global copula with a note.
Reach for it whenever the development pipeline estimates an effect, not
just a distribution.

## What the copula carries: monotone, not non-monotone, association

Numeric columns that are kept and re-simulated together share one
Gaussian copula, fitted on the normal scores of their ranks. A Gaussian
copula holds a single correlation per pair, so it reproduces a
*monotone* association – linear, or any order-preserving curve – but not
a dependence that a correlation cannot express. A non-monotone
relationship, such as a U-shaped dependence of an outcome on a
covariate, reads as near-zero rank correlation and is reproduced as
near-independence.

``` r

set.seed(7)
n <- 2000
x_lin <- rnorm(n)
y_lin <- 2 * x_lin + rnorm(n, sd = 0.5)     # monotone (linear)
x_u <- runif(n, -3, 3)
y_u <- x_u^2 + rnorm(n, sd = 0.5)           # non-monotone (U-shaped)
d <- data.frame(x_lin, y_lin, x_u, y_u)

s <- synthetic(mask(d, propose_roles(d, detect = FALSE), seed = 1))

# R-squared of a quadratic fit captures association of any curvature.
fit_r2 <- function(x, y) summary(lm(y ~ poly(x, 2)))$r.squared
data.frame(
  pair = c("monotone (y = 2x)", "non-monotone (y = x^2)"),
  original = c(fit_r2(x_lin, y_lin), fit_r2(x_u, y_u)),
  clone = c(fit_r2(s$x_lin, s$y_lin), fit_r2(s$x_u, s$y_u))
)
#>                     pair  original        clone
#> 1      monotone (y = 2x) 0.9418049 0.9412768375
#> 2 non-monotone (y = x^2) 0.9661641 0.0002984912
```

The monotone pair keeps its association almost exactly. The non-monotone
pair loses it entirely, so on the clone the covariate carries no
information about the outcome. `conditional = TRUE` does not repair
this. It preserves the outcome’s location within each
treatment-by-design stratum, not the curvature of the outcome’s
dependence on a continuous covariate. A development pipeline whose
modelling step is non-linear – a smoothing spline, a generalised
additive model, a tree, an interaction term – will therefore see on the
synthetic only the monotone part of any relationship present in the
original, and a good fit there is not evidence the step behaves
correctly on the real data. Validate such a step by round-tripping it
onto the original through the recipe, not by trusting its result on the
clone.

## The leakage audit

[`audit_mask()`](https://max578.github.io/masque/reference/audit_mask.md)
inspects the synthetic against the original and grades the leakage of
each column. In collaborate mode it runs automatically and warns at
[`mask()`](https://max578.github.io/masque/reference/mask.md) time. Here
is a fixture built to trip it: a PII-suspected column the user retains
against the default, and a categorical covariate with a frequency-one
level.

``` r

df <- data.frame(
  rep = rep(1:3, each = 20),
  variety = factor(rep(paste0("V", 1:6), 10)),
  contact_email = factor(rep(c("a@x", "b@y"), 30)),
  rare_treatment = factor(c(
    "only_one",
    sample(c("alpha", "beta", "gamma"), 59, replace = TRUE)
  )),
  yield = rnorm(60, 5, 1),
  stringsAsFactors = FALSE
)

roles <- propose_roles(df, mode = "collaborate")
roles[, c("col", "role", "action", "pii_suspected")]
#> # A tibble: 5 × 4
#>   col            role      action   pii_suspected
#>   <chr>          <chr>     <chr>    <lgl>        
#> 1 rep            design    keep     FALSE        
#> 2 variety        treatment alias    FALSE        
#> 3 contact_email  text      drop     TRUE         
#> 4 rare_treatment treatment alias    FALSE        
#> 5 yield          covariate scramble FALSE
```

`contact_email` was auto-flagged `pii_suspected` and set to `drop`. We
override it – pretending the custodian insists on keeping it – and make
the rare column a covariate, then mask:

``` r

roles <- set_role(roles, "yield", role = "outcome")
roles <- set_role(roles, "contact_email", role = "covariate", action = "keep")
roles <- set_role(roles, "rare_treatment", role = "covariate")
m <- mask(df, roles, mode = "collaborate", seed = 1)
#> Warning: audit_mask() flagged HIGH leakage on column(s): contact_email, rare_treatment
audit_mask(m)
#> 
#> ── masque audit (mode = collaborate) ───────────────────────────────────────────────────────────────
#> • 2 HIGH, 0 medium, 3 low across 5 columns
#> • Rows with a globally unique NA pattern: 0.0%
#> 
#> ── HIGH (2) ──
#> 
#> ✖   covariate contact_email                     PII-pattern column name; kept as-is - visible to collaborators
#> ✖   covariate rare_treatment                    levels aliased; rare level (freq = 1)
#> 
#> ── LOW (3) ──
#> 
#> ℹ   design    rep                               exact-match 100.0%
#> ℹ   treatment variety                           levels aliased
#> ℹ   outcome   yield                             ok
```

`contact_email` (real values kept across the trust boundary) and
`rare_treatment` (a frequency-one level) are flagged. `masque` responds
on two channels. At construction time,
[`mask()`](https://max578.github.io/masque/reference/mask.md) raises a
classed warning (`masque_high_leakage`) and records the findings in
`recipe@warnings` and on the object’s audit – the guided
[`masque()`](https://max578.github.io/masque/reference/masque.md) flow
never silences it. At write time, the package-managed writers
([`masque()`](https://max578.github.io/masque/reference/masque.md)’s
`out` and
[`write_set()`](https://max578.github.io/masque/reference/write_set.md))
refuse to write while a HIGH finding stands: nothing is written, and the
flagged columns are listed with the remedy (re-role, alias, or drop,
then mask again). A custodian who has reviewed the findings can pass
`allow_high = TRUE` to write anyway. The override is raised as a
`masque_high_override` warning and recorded in the recipe’s warnings, so
the exception stays auditable.

Beyond that gate the release decision stays with the custodian – whether
a synthetic table is appropriate for a given collaborator, environment,
or jurisdiction depends on context the package cannot see. `masque`
informs that decision. It does not make it.

## Multi-table sets

When several tables share a key,
[`mask_set()`](https://max578.github.io/masque/reference/mask_set.md)
aliases that key *identically across all of them* so the synthetic
tables still join. A linked key is the join surface. It is aliased
consistently rather than permuted (permuting a key would break the join
regardless of masking).

``` r

set_dir <- system.file("extdata", "met_set", package = "masque")
ms <- mask_set(set_dir, mode = "collaborate", seed = 1, quiet = TRUE)
#> Warning: Numeric environment column(s) year remain "keep" in collaborate mode.
#> ℹ This preserves environment structure but may disclose year or other numeric labels; review before
#>   release.
ag <- synthetic(ms)$agronomy
qa <- synthetic(ms)$quality
setequal(unique(ag$gen), unique(qa$gen))   # same genotype codes in both
#> [1] TRUE
```

The recipe bundle is private exactly as a single recipe is.
[`write_set()`](https://max578.github.io/masque/reference/write_set.md)
never writes it.

## Geographic coordinates

Latitude and longitude are treated as sensitive:
[`propose_roles()`](https://max578.github.io/masque/reference/propose_roles.md)
flags a column whose name looks like a coordinate (`gps`,
`lat`/`latitude`, `lon`/`longitude`) as `pii_suspected` and proposes
`drop`. Dropping is the safest choice when the synthetic does not need
locations.

When the synthetic does need plausible coordinates – to exercise a
spatial pipeline, say – a plain scramble is the wrong tool: the copula
re-simulates each axis and smears a latitude/longitude pair into a
continuous cloud that can land in the sea. masque offers two
purpose-built alternatives.

[`jitter_coordinates()`](https://max578.github.io/masque/reference/jitter_coordinates.md)
coarsens coordinates in place by a geographic-masking jitter. The
default donut scheme displaces every point by a random distance drawn
uniformly by area from an annulus, in a random direction, and re-draws
until the point falls on land, so a coastal site is never pushed
offshore. The longitude step is corrected by `cos(latitude)` so the
ground distance matches the requested kilometres at any latitude, and
the NA pattern and the latitude/longitude pairing are preserved.

``` r

sites <- data.frame(
  site = c("A", "B", "C"),
  lat  = c(-34.9, -35.2, -33.6),
  lon  = c(138.6, 142.0, 148.2)
)
jitter_coordinates(sites, "lat", "lon", min_km = 5, max_km = 20, seed = 1)
#>   site       lat      lon
#> 1    A -34.81596 138.5333
#> 2    B -35.16555 142.1346
#> 3    C -33.48829 148.1005
```

Declaring the pair to
[`mask()`](https://max578.github.io/masque/reference/mask.md) applies
the same coarsening as part of masking, so the coordinates never pass
through the copula:

``` r

m <- mask(df, roles, mode = "collaborate",
          coords = list(c(lat = "GPS_S", lon = "GPS_E")), seed = 1)
```

[`synthesise_geospatial()`](https://max578.github.io/masque/reference/synthesise_geospatial.md)
is the alternative when you would rather re-anchor points around fake
centroids you supply for each region.

**How far to displace.** The right magnitude is not a constant. It is
calibrated to the density of the entities being protected, so that the
masked point is spatially k-anonymous – roughly, at least *k* comparable
entities lie closer to the masked point than the true one (Hampton et
al., 2010). Individual-level urban health data is typically masked with
a standard deviation of about one kilometre, because cities are dense.
Fields and farms are far sparser, so comparable protection needs a much
larger displacement; a donut of roughly 5 to 20 km (the default) moves a
point across several properties while keeping it in the same
agroclimatic region (Zandbergen, 2014). For a formal guarantee,
calibrate the radii to the local field density rather than relying on
the default.

## Operational guidance

Default to collaborate mode when in doubt. Local mode is for owner-only
development. Treat the recipe as you treat the original data – same
security class, same access controls. Re-run
[`audit_mask()`](https://max578.github.io/masque/reference/audit_mask.md)
before any sharing even though collaborate mode runs it for you. Never
override a `pii_suspected` flag without deciding deliberately. Remember
that date/time columns and a preserved design footprint both carry real
operational signal. Alias or roll them up when that signal is sensitive.
Small designs leak – a categorical cell count of one is high leakage, so
aggregate or drop before masking.

For what the recipe stores and how the round-trip works, see *Recipe
anatomy and the round-trip*.

## References

Hampton, K. H., Fitch, M. K., Allshouse, W. B., Doherty, I. A., Gesink,
D. C., Leone, P. A., Serre, M. L., & Miller, W. C. (2010). Mapping
health data: improved privacy protection with donut method geomasking.
*American Journal of Epidemiology, 172*(9), 1062–1069.
<https://doi.org/10.1093/aje/kwq248>

Zandbergen, P. A. (2014). Ensuring confidentiality of geocoded health
data: assessing geographic masking strategies for individual-level data.
*Advances in Medicine, 2014*, 567049.
<https://doi.org/10.1155/2014/567049>
