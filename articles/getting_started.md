# Getting started with masque

## What masque is for

`masque` exists to bridge an expertise gap. A data custodian holds a
confidential dataset and the legal responsibility for it, but often only
basic R fluency. An analyst has the modelling expertise but cannot
lawfully see the raw data. `masque` lets the custodian hand the analyst
a structurally faithful *synthetic* clone – close enough that a pipeline
developed against it runs unchanged on the real data – while the
information that must stay private never crosses the boundary.

It turns one tabular dataset (or a folder or workbook of related tables)
into a synthetic clone whose experimental design, missing-value pattern,
and global covariance are preserved, alongside a private `recipe` that
round-trips: a pipeline written against the synthetic re-targets to the
original with no code changes.

It is **not** an anonymiser. The synthetic is a development surrogate,
not a public-release-safe artefact. The companion vignette
*Confidentiality and the threat model* sets out exactly what is and is
not protected; read it before sharing any output.

## The one-call path

[`masque()`](https://max578.github.io/masque/reference/masque.md) is the
front door. Point it at your data and it reads the table, proposes a
masking plan, masks, and – in an interactive session – pauses to let you
review the plan first. We use the classical John & Williams (1995)
alpha-design field trial, shipped with the package.

``` r

library(masque)

f <- system.file("extdata", "john_alpha.csv", package = "masque")
df <- read.csv(f, stringsAsFactors = TRUE)
head(df)
#>   plot rep block gen  yield row col
#> 1    1  R1    B1 G11 4.1172   1   1
#> 2    2  R1    B1 G04 4.4461   2   1
#> 3    3  R1    B1 G05 5.8757   3   1
#> 4    4  R1    B1 G22 4.5784   4   1
#> 5    5  R1    B2 G21 4.6540   5   1
#> 6    6  R1    B2 G10 4.1736   6   1

m <- masque(df, mode = "collaborate", seed = 1, ask = FALSE)
#> ℹ Using the proposed masking plan (pass `roles` or set `ask = TRUE` to review).
#> ✔ Masked 7 columns in "collaborate" mode.
#> ℹ Recipe is private - keep it; share only the synthetic output.
```

`ask = FALSE` skips the interactive review, which is what we want inside
a vignette. In your own console, call `masque(df)` and you will see the
proposed plan and a prompt to proceed, edit, or stop.

The result carries the synthetic data and the private recipe:

``` r

synth <- synthetic(m)
head(synth)
#> # A tibble: 6 × 7
#>    plot rep   block gen     yield   row   col
#>   <int> <fct> <fct> <fct>   <dbl> <int> <int>
#> 1     1 R1    B1    trt_011  4.15     1     1
#> 2     2 R1    B1    trt_004  4.25     2     1
#> 3     3 R1    B1    trt_005  4.58     3     1
#> 4     4 R1    B1    trt_022  5.30     4     1
#> 5     5 R1    B2    trt_021  3.99     5     1
#> 6     6 R1    B2    trt_010  5.26     6     1
```

## The masking plan: roles and actions

Under the one-call path,
[`masque()`](https://max578.github.io/masque/reference/masque.md) builds
the *roles table* for you. You can build and edit it yourself for full
control. Every column gets two decisions: a `role` (what the column is)
and an `action` (what masque does to it).

``` r

roles <- propose_roles(df, mode = "collaborate")
roles[, c("col", "role", "action", "kind")]
#> # A tibble: 7 × 4
#>   col   role      action   kind   
#>   <chr> <chr>     <chr>    <chr>  
#> 1 plot  design    keep     integer
#> 2 rep   design    keep     factor 
#> 3 block design    keep     factor 
#> 4 gen   treatment alias    factor 
#> 5 yield covariate scramble numeric
#> 6 row   design    keep     integer
#> 7 col   design    keep     integer
```

The eight roles – `design`, `treatment`, `outcome`, `covariate`, `date`,
`id`, `text`, `other` – describe the column. The four actions set the
depth:

- `keep` – pass the column through byte-for-byte;
- `scramble` – re-simulate numerics through a Gaussian copula, or
  row-permute categoricals, dates, and text (the vocabulary stays
  visible);
- `alias` – scramble and replace the labels with opaque codes;
- `drop` – leave the column out of the synthetic entirely.

[`propose_roles()`](https://max578.github.io/masque/reference/propose_roles.md)
fills in a sensible action for each column given the mode, so the table
you review is the plan that will run. Edit it with
[`set_role()`](https://max578.github.io/masque/reference/set_role.md):

``` r

roles <- set_role(roles, "yield", role = "outcome")
roles[, c("col", "role", "action")]
#> # A tibble: 7 × 3
#>   col   role      action  
#>   <chr> <chr>     <chr>   
#> 1 plot  design    keep    
#> 2 rep   design    keep    
#> 3 block design    keep    
#> 4 gen   treatment alias   
#> 5 yield outcome   scramble
#> 6 row   design    keep    
#> 7 col   design    keep
```

Re-assigning a role re-resolves the default action; passing an explicit
`action` pins the column. There is no requirement to name an `outcome`:
with none marked, every scrambled numeric is re-simulated jointly.

Pass the edited table back to
[`mask()`](https://max578.github.io/masque/reference/mask.md) (or to
`masque(df, roles = roles)`):

``` r

m <- mask(df, roles, mode = "collaborate", seed = 1)
synth <- synthetic(m)
identical(synth$plot, df$plot)               # design column: byte-identical
#> [1] TRUE
setequal(levels(synth$gen), levels(df$gen))  # treatment: aliased away
#> [1] FALSE
head(levels(synth$gen))
#> [1] "trt_001" "trt_002" "trt_003" "trt_004" "trt_005" "trt_006"
```

## Local and collaborate modes

The mode sets the safe defaults.

| Mode | Use case | Defaults |
|----|----|----|
| `local` | Owner develops on a realistic surrogate locally | Vocabulary preserved; numeric values may match observed |
| `collaborate` | Owner shares the synthetic while keeping the recipe private | Treatment and categorical labels aliased; numerics jittered; ids and free text dropped; the leakage audit runs automatically |

Per-column `action` choices override the mode wherever you need them.

## Tidy, dates, and depth

Real custodian tables are rarely clean.
[`masque()`](https://max578.github.io/masque/reference/masque.md)
legalises column names and trims stray whitespace before masking,
reports near-duplicate labels (likely typos) without merging them, and
records every fix so the round-trip still lines up. Set
`clean = "report"` to preview the fixes, or `clean = "off"` to skip
them.

Date and time columns get the first-class `date` role: they are
row-permuted, keep their class, and preserve the NA pattern. When even
the column *names* are sensitive, `alias_names = TRUE` hides them behind
opaque codes that the recipe inverts.

## More than one table

A confidential dataset often arrives as several related files or a
multi-sheet workbook.
[`masque()`](https://max578.github.io/masque/reference/masque.md)
handles those too – point it at a folder, an `.xlsx` file, or a named
list of data frames and it masks every table at once, aliasing any
shared key (a site code, a genotype name) *identically across tables* so
a join of the synthetic tables still resolves.

``` r

set_dir <- system.file("extdata", "met_set", package = "masque")
ms <- masque(set_dir, mode = "collaborate", seed = 1, ask = FALSE)
#> ℹ Using the proposed masking plan for agronomy (pass `roles` or set `ask = TRUE` to review).
#> ℹ Using the proposed masking plan for quality (pass `roles` or set `ask = TRUE` to review).
#> 
#> ── Cross-table links (1) ──
#> 
#> • "gen" shared across "agronomy, quality" - aliased consistently
#> ✔ Masked 2 tables in "collaborate" mode.
#> ℹ Recipe is private - keep it; share only the synthetic output.
ms
#> 
#> ── masque_set ──────────────────────────────────────────────────────────────────────────────────────
#> • Mode: collaborate
#> • Tables: 2
#> • agronomy: 464 row(s) x 7 column(s)
#> • quality: 464 row(s) x 5 column(s)
#> 
#> ── Cross-table links (1) ──
#> 
#> • "gen" shared across "agronomy, quality"
#> Use `synthetic(m)` for the tables; `recipe(m)` for the bundle.
#> 
#> ✖ The recipe bundle is PRIVATE - never share it with the synthetic set.
```

The genotype column `gen` appears in both tables and is masked to the
same codes in each, so the field and laboratory tables still join. See
*Confidentiality and the threat model* for the set-level controls.

## Where to go next

- *Confidentiality and the threat model* – what is and is not protected,
  the two modes, the depth controls, and the leakage audit.
- *Recipe anatomy and the round-trip* – the analyst’s side: how a
  pipeline built on the synthetic re-targets to the original.
