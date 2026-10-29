## Resubmission

This is a resubmission of a new package. In response to the review of
0.15.0:

* The text that `R/masque.R` wrote to the console with `print()` and
  `cat()` during the interactive review now goes through `message()`
  (via cli), so it can be suppressed. The output that remains on the
  console comes from `print()` and `summary()` methods.
* Each vignette saves the user's `options()` before changing `width` and
  restores them in its last chunk.

## Test environments

* Local: macOS (Apple Silicon), R 4.6.1.
* GitHub Actions: Ubuntu R-devel, R-release and R-oldrel-1; macOS
  R-release; Windows R-release.
* R-hub: Linux R-devel, Ubuntu R-patched, Windows R-devel, macOS arm64
  R-devel.
* win-builder: Windows R-devel.

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
