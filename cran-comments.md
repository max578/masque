## Resubmission

This is a resubmission of a new package, now version 0.16.0. The review of
0.15.0 asked for two changes:

* **Console output that cannot be suppressed.** The interactive review in
  `R/masque.R` wrote the plan table and its menus with `print()` and
  `cat()`. It now captures that text and writes it with
  `cli::cli_verbatim()`, which signals a message, so `suppressMessages()`
  silences it. The `print()` and `cat()` calls left in
  the package are inside `print()`, `format()`, `str()` and `knit_print()`
  methods, and in `reveal_maps()`, whose only purpose is to print the
  label maps a user asks to see.
* **Vignettes that change `options()`.** Each of the four vignettes saves
  the user's options with `old_options <- options(width = 100)` in its
  setup chunk and restores them with `options(old_options)` in its last
  chunk. Rendering every vignette leaves `options()` unchanged.

Since 0.15.0 the package has also gained `data_card()` and `roles()`,
synthesis of unit-constant columns once per design unit, linked
time-to-event outcomes, and fixes to the leakage audit and the
multi-table round trip. `NEWS.md` lists them.

## Test environments

* Local: macOS (Apple Silicon), R 4.6.1.
* GitHub Actions: Ubuntu (R-devel, R-release, R-oldrel-1), Windows
  (R-release), macOS (R-release).

## R CMD check results

0 errors | 0 warnings | 1 note

* New submission.

  win-builder also lists "anonymisation" as possibly misspelled. It is the
  Australian spelling; the package declares `Language: en-AU`.

## Reverse dependencies

None (first submission).

## Data shipped with the package

The examples and vignettes use two small public fixtures derived from the
agridat package (MIT), with values unchanged:

* `inst/extdata/john_alpha.csv`, from `agridat::john.alpha` (John and
  Williams 1995, *Cyclic and Computer Generated Designs*, p. 146).
* `inst/extdata/met_set/`, from `agridat::australia.soybean`.

No confidential or licence-restricted data ships with the package.
