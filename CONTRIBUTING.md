# Contributing to masque

Thank you for considering a contribution. This document describes how to
file useful reports and submit code changes.

By contributing, you agree to abide by the project [Code of
Conduct](https://max578.github.io/masque/CODE_OF_CONDUCT.md).

## Reporting bugs and requesting features

- Open an issue at <https://github.com/max578/masque/issues>.
- For bugs, please include:
  - `masque` version (`packageVersion("masque")`),
  - R version and platform
    ([`sessionInfo()`](https://rdrr.io/r/utils/sessionInfo.html)),
  - a minimal reproducible example (a few rows of synthetic data are
    usually enough — please do not paste real confidential data).
- For feature requests, please describe the workflow you are trying to
  support and, where possible, sketch the desired API.

## Proposing code changes

1.  **Open an issue first** for non-trivial changes so the design can be
    agreed before code is written. Small, well-scoped fixes can go
    straight to a pull request.
2.  Fork the repository and create a feature branch from `main`
    (`feat/<short-name>`, `fix/<short-name>`, or `docs/<short-name>`).
3.  Make your change. Keep commits focused; prefer small, reviewable
    diffs over large omnibus changes.
4.  Add or update tests in `tests/testthat/` so the new behaviour is
    covered. New exported functions require examples in their roxygen
    blocks.
5.  Update `NEWS.md` under the next-version heading.
6.  Run the local checks listed below.
7.  Open a pull request that references the issue.

## Local checks (must pass)

``` r

# from the package root
devtools::document()       # regenerate NAMESPACE + man/
devtools::test()           # unit tests
devtools::check()          # R CMD check
```

For a release-grade check:

``` sh
R CMD build .
R CMD check --as-cran masque_*.tar.gz
```

Aim for 0 errors / 0 warnings. Two notes are expected at this stage: the
“new submission” boilerplate and a local HTML Tidy version note — both
are environmental and documented in `cran-comments.md`.

## Style notes

- Code follows the [tidyverse style
  guide](https://style.tidyverse.org/), enforced loosely.
- Australian / British English in user-facing strings (`colour`,
  `behaviour`, `optimise`). The `Language: en-AU` field in `DESCRIPTION`
  is authoritative; the `inst/WORDLIST` file carries spelling
  exceptions.
- Exported functions use
  [`cli::cli_abort()`](https://cli.r-lib.org/reference/cli_abort.html) /
  [`cli::cli_warn()`](https://cli.r-lib.org/reference/cli_abort.html)
  for user-facing messages, never bare
  [`stop()`](https://rdrr.io/r/base/stop.html) /
  [`warning()`](https://rdrr.io/r/base/warning.html).
- RNG hygiene: any function that draws randomness opens with
  [`withr::local_preserve_seed()`](https://withr.r-lib.org/reference/with_seed.html)
  so the caller’s RNG state is untouched, and uses
  [`withr::with_seed()`](https://withr.r-lib.org/reference/with_seed.html)
  for the inner draw.

## API stability

Read
[API_STABILITY.md](https://max578.github.io/masque/API_STABILITY.md)
before proposing changes to exported signatures. Pre-1.0, the policy is
additive-by-intent; from 1.0, the API is strictly frozen with a
`lifecycle` retirement ladder.

## Recognition

Substantive contributions are acknowledged in `NEWS.md` and, where
appropriate, listed in `DESCRIPTION` under `Authors@R` with role `ctb`.
