# cran-comments.md

## Submission notes

This is a first submission of `masque` to CRAN.

## R CMD check results

Local `R CMD check --as-cran` on macOS (Apple Silicon), R 4.4.0:

* 0 errors
* 0 warnings
* 2 NOTEs:
  1. **New submission** — expected for a first submission; the
     maintainer name and email are correct.
  2. **HTML Tidy** — local machine does not have a recent enough HTML
     Tidy binary; the package's HTML help renders correctly under R's
     own renderer.

A GitHub Actions matrix (Linux release / devel / oldrel-1, macOS
release, Windows release) runs on every push and PR; the latest run
on `main` is green.

## Dependencies

* `Imports`: only base, plus widely-used packages already on CRAN
  (`cli`, `digest`, `MASS`, `Matrix`, `S7`, `tibble`, `withr`).
* `Suggests` are gated via `requireNamespace()` in code and tests.
* No revdeps (first submission).

## Reverse-dependency check

Not applicable — first submission.

## Companion distribution

The package is also available via r-universe at the maintainer's
public sub-domain (configured via the standard r-universe GitHub-repo
mechanism).

## Notes on data and licensing

The vignettes use the public CSV fixture
`inst/extdata/john_alpha.csv` (72 rows × 7 columns) derived from
`agridat::john.alpha` (John 1987; primary literature). The
distribution-time walkthrough demonstration uses the GRDC *Barley
Synthesis Project Dataset* (Harris, F. et al., 2024; CC-BY-SA 4.0)
but does not ship any of that data — it lives only on the
maintainer's machine and the rendered walkthrough HTML is a
derivative work redistributed under CC-BY-SA 4.0 separately from the
package.
