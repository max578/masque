## Submission

This is masque 0.17.1. It corrects the test failures shown on the CRAN check
page for 0.16.0, which the CRAN Team asked on 2026-11-20 to have corrected
before 2026-12-11.

* **Cause.** Three tests read the attribute in which S7 kept an object's
  class. S7 1.0.0, released on 2026-11-19, renamed that attribute, and the
  tests failed on every platform that had the new S7. The package's own code
  never used the attribute.
* **Correction.** The tests now use S7's exported functions only. The package
  requires S7 (>= 1.0.0), because a recipe file saved under S7 1.0.0 cannot be
  read under an earlier S7.

The version moves from 0.16.0 to 0.17.1 because 0.17.0 was finished while
0.16.0 was in review and was never submitted. Its changes come with this
correction so that a second update does not follow within weeks. `NEWS.md`
lists them: known-truth control datasets, a plan object that holds the roles
and the control specifications, and corrections to the coordinate displacement
and to the leakage audit.

`Authors@R` now names the funder and copyright holder, the Grains Research and
Development Corporation, which 0.16.0 omitted. `LICENSE` reads "masque
authors" to match. The maintainer and the licence are unchanged.

## Test environments

* Local: macOS (Apple Silicon), R 4.6.1, S7 1.0.0.

## R CMD check results

0 errors | 0 warnings | 1 note

* The incoming check may list the ROR ID `02xwr1996` as possibly invalid, with
  ror.org answering 429 (Too Many Requests). The ID is that of the Grains
  Research and Development Corporation and is active in the ROR registry.
* Days since last update: this update corrects the check failures the CRAN
  Team asked to have corrected.

## Reverse dependencies

None.

## Data shipped with the package

The examples and vignettes use two small public fixtures derived from the
agridat package (MIT), with values unchanged:

* `inst/extdata/john_alpha.csv`, from `agridat::john.alpha` (John and
  Williams 1995, *Cyclic and Computer Generated Designs*, p. 146).
* `inst/extdata/met_set/`, from `agridat::australia.soybean`.

No confidential or licence-restricted data ships with the package.
