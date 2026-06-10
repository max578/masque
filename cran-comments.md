# cran-comments.md

## Submission notes

`masque` 0.6.0 is the first submission to CRAN. It supersedes the
locally-tagged 0.4.x / 0.5.0 development line and adds the end-to-end
surface: a two-axis roles model (a `role` and an `action` per column),
a hygiene layer, opt-in column-name aliasing, a multi-table set layer
with cross-table-consistent key aliasing, and a single guided `masque()`
verb. See `NEWS.md` for the full change list.

## R CMD check results

Local `R CMD check --as-cran` on macOS (Apple Silicon), R 4.5.2:

* 0 errors
* 0 warnings
* Up to 3 NOTEs, all environment / release-context:
  1. **New submission** -- expected for a first submission; maintainer
     name and email are correct.
  2. **HTML Tidy** -- the local machine does not have a recent enough
     HTML Tidy binary; the package's HTML help renders correctly under
     R's own renderer.
  3. **Future file timestamps** -- the local environment could not
     verify the current time against a network source.

A GitHub Actions matrix (Linux release / devel / oldrel-1, macOS
release, Windows release) runs on every push and PR.

## Dependencies

* `Imports`: base R plus widely-used CRAN packages -- `cli`,
  `data.table`, `digest`, `Matrix`, `S7`, `tibble`, `withr`.
  `data.table` is used for fast delimited I/O (`fread` / `fwrite`) in
  the set layer; the count slightly exceeds the lean-package ideal but
  each import carries a distinct, load-bearing contract.
* `Suggests` (`readxl`, `writexl`, `fst`, `agridat`, `ggplot2`) are
  every one gated via `requireNamespace()` in code and tests, and the
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
