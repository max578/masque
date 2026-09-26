# Getting started with masque

``` r

library(masque)
```

## Why

A field agronomist has a confidential 72-plot trial and wants an outside
statistician to build a spatial yield model on it, without the
statistician seeing the real plot layout or genotype identities. This
vignette shows the agronomist’s side of that handoff on the John and
Williams (1995) alpha-design trial shipped with the package.

The synthetic table `masque` produces is a development surrogate for one
named collaborator. It is not an anonymised dataset and is not safe for
public release. *Confidentiality and the threat model* sets out what is
and is not protected; read it before sharing any output.

## What

[`masque()`](https://max578.github.io/masque/reference/masque.md) is the
front door: point it at a table (or a folder or workbook of related
tables) and it reads the data, proposes a masking plan, masks, and – in
an interactive session – pauses to let the custodian review the plan
first.

The output of
[`masque()`](https://max578.github.io/masque/reference/masque.md) is
always a pair: the *synthetic* clone, the only part that crosses the
trust boundary, and a private `masque_recipe` (see
[`recipe()`](https://max578.github.io/masque/reference/recipe.md)) that
never leaves the custodian’s machine. The recipe is what lets a pipeline
written against the synthetic re-target to the original later with no
code change; its internals and the round-trip verbs are the subject of
*Recipe anatomy and the round-trip*.

Every column in the masking plan has a `role` and an `action`, proposed
by
[`propose_roles()`](https://max578.github.io/masque/reference/propose_roles.md)
and changed with
[`set_role()`](https://max578.github.io/masque/reference/set_role.md).
The role says what the column is: `design`, `treatment`, `outcome`,
`covariate`, `date`, `id`, `text` or `other`. The action says what
happens to it:

- `keep` passes it through unchanged;
- `scramble` re-simulates numerics through a Gaussian copula, or
  shuffles categories and dates between rows;
- `alias` replaces the labels with opaque codes (a categorical covariate
  is shuffled between rows first);
- `drop` leaves it out.

[`role_options()`](https://max578.github.io/masque/reference/role_options.md)
lists every role and action pair the package accepts.

The `mode` argument sets the defaults for both axes at once:

- `local` is for the custodian’s own development and keeps labels
  intact.
- `collaborate` is for handing the synthetic to someone else. It aliases
  treatment and categorical labels, jitters numerics, drops identifiers
  and free text, and runs the leakage audit.

A per-column `action` always overrides the mode’s default.

## Do

### The one-call path

``` r

f <- system.file("extdata", "john_alpha.csv", package = "masque")
df <- read.csv(f, stringsAsFactors = TRUE)
knitr::kable(
  head(df),
  caption = "The first six plots of the alpha-design trial."
)
```

| plot | rep | block | gen |  yield | row | col |
|-----:|:----|:------|:----|-------:|----:|----:|
|    1 | R1  | B1    | G11 | 4.1172 |   1 |   1 |
|    2 | R1  | B1    | G04 | 4.4461 |   2 |   1 |
|    3 | R1  | B1    | G05 | 5.8757 |   3 |   1 |
|    4 | R1  | B1    | G22 | 4.5784 |   4 |   1 |
|    5 | R1  | B2    | G21 | 4.6540 |   5 |   1 |
|    6 | R1  | B2    | G10 | 4.1736 |   6 |   1 |

The first six plots of the alpha-design trial. {.table}

``` r


m <- masque(df, mode = "collaborate", seed = 1L, ask = FALSE)
#> ℹ Using the proposed masking plan (pass `roles` or set `ask = TRUE` to review).
#> ✔ Masked 7 columns in "collaborate" mode - audit: 0 HIGH, 0 medium, 7 low.
#> ℹ Recipe is private - keep it. Review `audit_mask(m)` before any release decision; masque informs that decision, it does not make it.
```

`ask = FALSE` skips the interactive review, which is what a vignette
needs; in an interactive console, `masque(df)` shows the proposed plan
and a prompt to proceed, edit, or stop. The message above is the summary
[`masque()`](https://max578.github.io/masque/reference/masque.md) prints
for every guided run: how many columns were masked, in which mode, and
the leakage-audit tally.

The result carries the synthetic data and the private recipe:

``` r

synth <- synthetic(m)
knitr::kable(
  head(synth),
  caption = paste0(
    "The first six plots of the synthetic clone: `gen` is aliased, ",
    "`yield` is re-simulated."
  )
)
```

| plot | rep | block | gen     |    yield | row | col |
|-----:|:----|:------|:--------|---------:|----:|----:|
|    1 | R1  | B1    | trt_006 | 4.150347 |   1 |   1 |
|    2 | R1  | B1    | trt_001 | 4.248434 |   2 |   1 |
|    3 | R1  | B1    | trt_019 | 4.578376 |   3 |   1 |
|    4 | R1  | B1    | trt_023 | 5.302792 |   4 |   1 |
|    5 | R1  | B2    | trt_002 | 3.992964 |   5 |   1 |
|    6 | R1  | B2    | trt_014 | 5.255890 |   6 |   1 |

The first six plots of the synthetic clone: `gen` is aliased, `yield` is
re-simulated. {.table}

### The masking plan: roles and actions

Under the one-call path,
[`masque()`](https://max578.github.io/masque/reference/masque.md) built
the roles table without asking. Building and reviewing it directly gives
full control:

``` r

roles <- propose_roles(df, mode = "collaborate")
knitr::kable(
  roles[, c("col", "role", "action", "kind")],
  caption = paste0(
    "The proposed masking plan for the alpha-design trial ",
    "(collaborate mode)."
  )
)
```

| col   | role      | action   | kind    |
|:------|:----------|:---------|:--------|
| plot  | design    | keep     | integer |
| rep   | design    | keep     | factor  |
| block | design    | keep     | factor  |
| gen   | treatment | alias    | factor  |
| yield | covariate | scramble | numeric |
| row   | design    | keep     | integer |
| col   | design    | keep     | integer |

The proposed masking plan for the alpha-design trial (collaborate mode).
{.table}

[`propose_roles()`](https://max578.github.io/masque/reference/propose_roles.md)
fills in a sensible action for each column given the mode, so the table
reviewed here is the plan that will run. `yield` was proposed as a
`covariate`; naming it the trial’s `outcome` changes nothing about how
it is masked, but it documents intent and is what a downstream consumer
such as the *conditional* clone (see *Confidentiality and the threat
model*) reads to find the response:

``` r

roles <- set_role(roles, "yield", role = "outcome")
knitr::kable(
  roles[, c("col", "role", "action")],
  caption = "The plan after naming `yield` as the trial outcome."
)
```

| col   | role      | action   |
|:------|:----------|:---------|
| plot  | design    | keep     |
| rep   | design    | keep     |
| block | design    | keep     |
| gen   | treatment | alias    |
| yield | outcome   | scramble |
| row   | design    | keep     |
| col   | design    | keep     |

The plan after naming `yield` as the trial outcome. {.table}

Re-assigning a role re-resolves the default action; passing an explicit
`action` pins the column instead. There is no requirement to name an
outcome: with none marked, every scrambled numeric is re-simulated
jointly.

### Editing the plan as code

The printed table – and the spreadsheet the guided prompt opens when the
custodian chooses `e` – is an ordinary data frame, so anything the
editor can do, a script can do reproducibly.
[`set_role()`](https://max578.github.io/masque/reference/set_role.md) is
vectorised over columns:

``` r

r2 <- set_role(roles, c("row", "col"), action = "drop")
```

Direct edits work too. A direct `role` edit leaves `action` untouched,
so setting the action back to `NA` tells
[`mask()`](https://max578.github.io/masque/reference/mask.md) to
re-resolve the default for the new role:

``` r

r2$role[r2$col == "rep"] <- "covariate"
r2$action[r2$col == "rep"] <- NA
knitr::kable(
  r2[, c("col", "role", "action")],
  caption = paste0(
    "A hand-edited plan: `row`/`col` dropped, `rep` re-roled to a ",
    "covariate."
  )
)
```

| col   | role      | action   |
|:------|:----------|:---------|
| plot  | design    | keep     |
| rep   | covariate | NA       |
| block | design    | keep     |
| gen   | treatment | alias    |
| yield | outcome   | scramble |
| row   | design    | drop     |
| col   | design    | drop     |

A hand-edited plan: `row`/`col` dropped, `rep` re-roled to a covariate.
{.table}

The `kind` column comes from the column’s class and cannot be edited. If
it is wrong, convert the column in the data and run
[`propose_roles()`](https://max578.github.io/masque/reference/propose_roles.md)
again.

[`role_options()`](https://max578.github.io/masque/reference/role_options.md)
lists the pairs the package accepts, here for a factor column:

``` r

knitr::kable(
  role_options(kind = "factor"),
  caption = paste0(
    "Every (role, action) pair the validator accepts for a factor ",
    "column."
  )
)
```

| role | action | kinds | notes |
|:---|:---|:---|:---|
| design | keep | all |  |
| design | alias | factor, character, logical | design label aliasing requires a factor / character / logical column; numeric design columns can only be kept or dropped |
| design | drop | all |  |
| treatment | keep | all |  |
| treatment | scramble | factor, character, logical | treatment scramble / alias requires a factor / character / logical column; a numeric treatment (e.g. a dose) can only be kept or dropped |
| treatment | alias | factor, character, logical | treatment scramble / alias requires a factor / character / logical column; a numeric treatment (e.g. a dose) can only be kept or dropped |
| treatment | drop | all |  |
| outcome | keep | all |  |
| outcome | drop | all |  |
| covariate | keep | all |  |
| covariate | scramble | all except other | columns of an unsupported class can only be kept or dropped; masque does not know how to synthesise them |
| covariate | alias | factor, character, logical | covariate aliasing requires a factor / character / logical column; numeric covariates use scramble |
| covariate | drop | all |  |
| date | keep | all |  |
| date | drop | all |  |
| id | keep | all |  |
| id | alias | numeric, integer, factor, character | id aliasing requires a character, factor, or integer column |
| id | drop | all |  |
| text | keep | all |  |
| text | scramble | all except other | columns of an unsupported class can only be kept or dropped; masque does not know how to synthesise them |
| text | alias | factor, character | text aliasing requires a character or factor column |
| text | drop | all |  |
| other | keep | all |  |
| other | drop | all |  |

Every (role, action) pair the validator accepts for a factor column.
{.table}

Finally, `pii_suspected`.
[`propose_roles()`](https://max578.github.io/masque/reference/propose_roles.md)
sets it from the column *name* (`email`, `phone`, `owner`, …), and the
leakage audit treats a flagged column that survives into the synthetic
as a HIGH finding. The scan reads names, not content, so when a
harmlessly named column holds sensitive values, flagging it by hand is
the correct fix:

``` r

roles$pii_suspected[roles$col == "comments"] <- TRUE
```

Passing the edited table back to
[`mask()`](https://max578.github.io/masque/reference/mask.md) (or to
`masque(df, roles = roles)`) runs the plan:

``` r

m <- mask(df, roles, mode = "collaborate", seed = 1L)
synth <- synthetic(m)
byte_identical_plot <- identical(synth$plot, df$plot)
gen_levels_changed <- !setequal(levels(synth$gen), levels(df$gen))
byte_identical_plot
#> [1] TRUE
gen_levels_changed
#> [1] TRUE
head(levels(synth$gen))
#> [1] "trt_001" "trt_002" "trt_003" "trt_004" "trt_005" "trt_006"
```

### A plan the package refuses

`plot` is a `design` column. Scrambling it would break the trial’s
layout, and
[`mask()`](https://max578.github.io/masque/reference/mask.md) refuses:

``` r

bad_roles <- set_role(roles, "plot", role = "design", action = "scramble")
mask(df, bad_roles, mode = "collaborate", seed = 1L)
#> Error in `roles_validate()`:
#> ! Incompatible role, action and kind combination:
#> ✖ plot (design + scramble): design columns are structure, not content - they cannot be scrambled;
#>   use keep, alias (labels hidden, structure intact), or drop
```

The call stops before any masking, names the column and the combination
at fault, and lists the three actions that do work for a design column
(`keep`, `alias`, `drop`). The same check runs whether the plan came
from
[`propose_roles()`](https://max578.github.io/masque/reference/propose_roles.md),
a hand edit or the guided spreadsheet.

### More than one table

A confidential dataset often arrives as several related files or a
multi-sheet workbook.
[`masque()`](https://max578.github.io/masque/reference/masque.md)
handles those too – point it at a folder, an `.xlsx` file, or a named
list of data frames and it masks every table at once, aliasing any
shared key (a site code, a genotype name) *identically across tables* so
a join of the synthetic tables still resolves.

``` r

set_dir <- system.file("extdata", "met_set", package = "masque")
ms <- masque(set_dir, mode = "collaborate", seed = 1L, ask = FALSE)
#> Warning: Numeric environment column year remains "keep" in collaborate mode.
#> ℹ This preserves environment structure but may disclose year or other numeric labels; review before
#>   release.
#> ℹ Using the proposed masking plan for agronomy (pass `roles` or set `ask = TRUE` to review).
#> ℹ Using the proposed masking plan for quality (pass `roles` or set `ask = TRUE` to review).
#> 
#> ── Cross-table links (2) ──
#> 
#> • "env" shared across "agronomy, quality" - aliased consistently
#> • "gen" shared across "agronomy, quality" - aliased consistently
#> ✔ Masked 2 tables in "collaborate" mode - audit: 0 HIGH, 0 medium, 12 low.
#> ℹ Recipe is private - keep it. Review `audit_mask(m)` before any release decision; masque informs that decision, it does not make it.
ms
#> 
#> ── masque_set ──────────────────────────────────────────────────────────────────────────────────────
#> • Mode: collaborate
#> • Tables: 2
#> • agronomy: 464 rows x 7 columns
#> • quality: 464 rows x 5 columns
#> 
#> ── Cross-table links (2) ──
#> 
#> • "env" shared across "agronomy, quality"
#> • "gen" shared across "agronomy, quality"
#> Use `synthetic(m)` for the tables; `recipe(m)` for the bundle.
#> 
#> ✖ The recipe bundle is PRIVATE - never share it with the synthetic set.
```

The genotype column `gen` appears in both tables and is masked to the
same codes in each, so the field and laboratory tables still join. See
*Confidentiality and the threat model* for the set-level controls.

### Multi-environment structure

A multi-environment trial has at least three distinct structural
questions: which rows belong to each environment, whether treatments
connect the environments, and what randomisation structure can be
recovered within each environment.
[`detect_design()`](https://max578.github.io/masque/reference/detect_design.md)
reports these separately. Connectivity says whether environments can be
compared; it does not decide whether the trial is multi-environment. A
block or field layout seen in the data suggests the original
randomisation but does not confirm it.

A small synthetic toy with two environments and three genotypes makes
the three questions concrete:

``` r

met <- expand.grid(
  env = factor(c("E1", "E2")),
  rep = factor(seq_len(2L)),
  gen = factor(c("G1", "G2", "G3"))
)
met$yield <- seq_len(nrow(met)) + rep(c(0, 2), each = 6L)

ds <- detect_design(met)
ds@scope_label
#> [1] "multi_environment"
ds@env_cols
#> [1] "env"
ds@connectivity$status
#> [1] "connected"
ds@within_design_label
#> [1] "RCBD"
```

Automatic detection is conservative. A column named `env` or
`environment`, or a common site-year pattern, is taken as the
environment only when no other column explains the structure as well; a
site-only column is taken only when treatments are replicated across
sites, so a nested block is not mistaken for an environment. When you
know the environment columns, name them:

``` r

ds_explicit <- detect_design(met, env = "env")
```

### Figure: the multi-environment coverage plot

`plot.design_summary()` draws a compact environment overview by default,
in base graphics or, with `engine = "ggplot2"`, as a `ggplot2` object
you can save with
[`ggplot2::ggsave()`](https://ggplot2.tidyverse.org/reference/ggsave.html);
printed, it is the figure below. It shows whether coverage is even
across environments, which the connectivity flag alone does not.

``` r

plot(ds_explicit, df = met, engine = "ggplot2")
```

![Genotypes observed per environment (E1, E2) for the toy
multi-environment trial; the subtitle carries connectivity status,
component count, and the recovered within-environment
design.](getting_started_files/figure-html/met-plot-1.png)

Genotypes observed per environment (E1, E2) for the toy
multi-environment trial; the subtitle carries connectivity status,
component count, and the recovered within-environment design.

Both bars are at three treatments, since every genotype in this toy
trial appears in both environments. A shorter bar, or a subtitle
reporting more than one component, marks environments that cannot go
into one connected analysis until you have checked whether the missing
coverage is real or an artefact of how the table was put together.

High-confidence environment recommendations feed the masking plan
directly. Local mode keeps environment values byte-identical;
collaborate mode aliases categorical environment labels in place,
keeping each row in its environment and the missing values where they
were, and the recipe can turn the aliases back into the real labels. A
numeric environment such as year remains `keep` and raises a disclosure
warning because its values are still visible:

``` r

met_roles <- propose_roles(met, mode = "collaborate")
knitr::kable(
  met_roles[met_roles$col == "env", c("col", "role", "action")],
  caption = "How the masking plan treats the `env` column."
)
```

| col | role   | action |
|:----|:-------|:-------|
| env | design | alias  |

How the masking plan treats the `env` column. {.table}

This safeguard protects the allocation a pipeline reads. It does not
imply that the synthesised outcomes preserve genotype-by-environment
effects: sparse treatment-by-environment cells may fall back to pooled
synthesis, and the clone must not be used as a substitute for the
original trial in scientific inference.

## Read

The audit found nothing to flag on this trial, so the synthetic could be
handed over as it is. A design column left at `keep` comes back
unchanged and an aliased treatment comes back as `trt_001` to `trt_024`;
a plan that asks for something the package cannot do is refused before
it runs. Related tables are masked together and still join.

The agronomist can therefore hand over a clone that keeps the plot
layout and the links between tables, with the genotype labels aliased,
and the statistician can build a full pipeline on it without seeing the
real genotype names. How the finished pipeline runs on the real data is
covered in *Recipe anatomy and the round-trip*.

## Limits

This vignette shows the custodian’s side of the handoff, on one small
public trial with a clean, complete design; it does not exercise the
leakage audit’s failure modes, the geographic-coordinate controls, or
the conditional clone that preserves a treatment effect rather than only
a marginal distribution, all of which live in *Confidentiality and the
threat model*. A sensitive column with an ordinary name is caught only
if someone flags it by hand. Multi-environment detection can miss a real
environment when the names and replication are ambiguous; prefer an
explicit `env` whenever you know better. Only one numeric column is
re-simulated here, so the vignette does not show what the Gaussian
copula keeps of the relationships between columns; that is also in
*Confidentiality and the threat model*.

## What to read next

*Confidentiality and the threat model* sets out exactly what a synthetic
clone protects and what it does not, the depth controls beyond role and
action, the leakage audit, and the conditional clone that preserves a
treatment-to-outcome relationship. *Recipe anatomy and the round-trip*
is the analyst’s side of this handoff: what the recipe carries, and how
a pipeline built on the synthetic re-targets to the original.

## Reproduce

`set.seed(1)` is set once for the document, and every
[`masque()`](https://max578.github.io/masque/reference/masque.md) or
[`mask()`](https://max578.github.io/masque/reference/mask.md) call
passes `seed = 1L`, so each is reproducible on its own. Package versions
follow.

``` r

sessionInfo()
#> R version 4.6.1 (2026-06-24)
#> Platform: x86_64-pc-linux-gnu
#> Running under: Ubuntu 24.04.5 LTS
#> 
#> Matrix products: default
#> BLAS:   /usr/lib/x86_64-linux-gnu/openblas-pthread/libblas.so.3 
#> LAPACK: /usr/lib/x86_64-linux-gnu/openblas-pthread/libopenblasp-r0.3.26.so;  LAPACK version 3.12.0
#> 
#> locale:
#>  [1] LC_CTYPE=C.UTF-8       LC_NUMERIC=C           LC_TIME=C.UTF-8        LC_COLLATE=C.UTF-8    
#>  [5] LC_MONETARY=C.UTF-8    LC_MESSAGES=C.UTF-8    LC_PAPER=C.UTF-8       LC_NAME=C             
#>  [9] LC_ADDRESS=C           LC_TELEPHONE=C         LC_MEASUREMENT=C.UTF-8 LC_IDENTIFICATION=C   
#> 
#> time zone: UTC
#> tzcode source: system (glibc)
#> 
#> attached base packages:
#> [1] stats     graphics  grDevices utils     datasets  methods   base     
#> 
#> other attached packages:
#> [1] masque_0.14.0
#> 
#> loaded via a namespace (and not attached):
#>  [1] vctrs_0.7.3         cli_3.6.6           knitr_1.52          rlang_1.3.0        
#>  [5] xfun_0.61           otel_0.2.0          textshaping_1.0.5   S7_0.2.2           
#>  [9] data.table_1.18.6.1 jsonlite_2.0.0      labeling_0.4.3      glue_1.8.1         
#> [13] htmltools_0.5.9     ragg_1.5.2          sass_0.4.10         scales_1.4.0       
#> [17] rmarkdown_2.32      grid_4.6.1          tibble_3.3.1        evaluate_1.0.5     
#> [21] jquerylib_0.1.4     fastmap_1.2.0       yaml_2.3.12         lifecycle_1.0.5    
#> [25] compiler_4.6.1      fs_2.1.0            RColorBrewer_1.1-3  pkgconfig_2.0.3    
#> [29] systemfonts_1.3.2   farver_2.1.2        digest_0.6.39       R6_2.6.1           
#> [33] pillar_1.11.1       magrittr_2.0.5      bslib_0.12.0        withr_3.0.3        
#> [37] tools_4.6.1         gtable_0.3.6        pkgdown_2.2.1       ggplot2_4.0.3      
#> [41] cachem_1.1.0        desc_1.4.3
```
