# cran-comments.md

## Submission notes

`masque` 0.10.0 is the first submission to CRAN. It carries the full
end-to-end surface built over the 0.2-0.7 development line - a two-axis
roles model (a `role` and an `action` per column), a hygiene layer,
opt-in column-name aliasing, a multi-table set layer with
cross-table-consistent key aliasing, a conditional clone mode, and a
single guided `masque()` verb - plus the 0.8.0 safety correction: HIGH
leakage findings are raised as classed warnings that the guided flow
never silences, and package-managed writers refuse to write while a
HIGH finding stands. Versions 0.9.1 and 0.9.2 add conservative
multi-environment scope detection with environment-safe role defaults,
connectivity diagnostics, bounded print and plot methods, a
mode-provenance guard, and on-land geographic-coordinate coarsening
(`jitter_coordinates()` plus a `coords` argument to `mask()`). Version
0.10.0 corrects that coarsening: one displacement is now drawn per site
rather than per row, because per-row displacement of a repeated
coordinate both fabricates within-site variation and lets the true site
be recovered by averaging, and a point that cannot be placed on land now
fails closed to `NA` rather than retaining its true value. See `NEWS.md`
for the full change list.

## R CMD check results

Local `R CMD check --as-cran` on macOS (Apple Silicon), R 4.5.2:

* 0 errors
* 0 warnings
* 2 NOTEs, both release-context:
  1. **New submission** -- expected for a first submission; maintainer
     name and email are correct.
  2. **Future file timestamps** -- the local environment could not
     verify the current time against a network source.

With remote incoming and system-clock probes disabled, the same final
tarball returns `Status: OK` (0 errors, 0 warnings, 0 NOTEs). HTML help
validation runs with HTML Tidy 5.8.0 and passes.

A GitHub Actions matrix (Linux release / devel / oldrel-1, macOS
release, Windows release) runs on every push and PR.

## Dependencies

* `Imports`: base R plus widely-used CRAN packages -- `cli`,
  `data.table`, `digest`, `Matrix`, `S7`, `stats`, `tibble`, `utils`,
  `withr`.
  `data.table` is used for fast delimited I/O (`fread` / `fwrite`) in
  the set layer; the count slightly exceeds the lean-package ideal but
  each import carries a distinct, load-bearing contract.
* Suggested packages are gated via `requireNamespace()` in code and tests,
  and the
  package degrades with a clear message when a Suggested package is
  absent.
* No revdeps (first submission).

## Reverse-dependency check

Not applicable -- first submission.

## Notes on data and licensing

The vignettes and examples use two public fixtures, both derived from
the MIT-licensed `agridat` package and re-distributed under masque's MIT
licence without altering values:

* `inst/extdata/john_alpha.csv` (72 x 7) from `agridat::john.alpha`,
  documented by agridat as John & Williams (1995), *Cyclic and Computer
  Generated Designs* (Chapman and Hall, p. 146).
* `inst/extdata/met_set/` (two related tables) from
  `agridat::australia.soybean`, a public multi-environment soybean
  trial.

No confidential or licence-restricted data ships with the package.
