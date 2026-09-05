# Bring a cleaned table to an analysable format, reporting every assumption

[`clean_table()`](https://max578.github.io/masque/reference/clean_table.md)
makes the fixes that are unambiguously safe: it legalises column names
and trims whitespace, and it *reports* near-duplicate labels without
merging them. `conform_table()` is the next step, and it handles the two
jobs that are judgement calls rather than hygiene: deciding that `"NSW"`
and `"Nsw"` are one category, and deciding that a character column
holding six labels is a factor.

## Usage

``` r
conform_table(
  df,
  merge_labels = c("report", "auto", "off"),
  types = c("report", "auto", "off"),
  max_levels = 20L,
  clean = c("auto", "report", "off"),
  quiet = FALSE
)
```

## Arguments

- df:

  A data frame.

- merge_labels:

  One of `"report"` (default), `"auto"` or `"off"`. Governs
  near-duplicate category labels, and treats the two kinds differently.
  A pair differing **only by capitalisation** is one category whatever
  happens, so it is merged onto the more frequent spelling, and on a tie
  onto whichever appeared first, which is deterministic and recorded. A
  pair differing **by one edit** might be two real categories, so it is
  merged only when one spelling is clearly the more common; on a tie it
  is refused and reported.

- types:

  One of `"report"` (default), `"auto"` or `"off"`. Governs storage
  format: a low-cardinality character column becomes a factor, a fully
  numeric character column becomes numeric, and a fully ISO-8601
  character column becomes a `Date`.

- max_levels:

  Cardinality at or below which a character column is treated as
  categorical. Default `20`.

- clean:

  Passed to
  [`clean_table()`](https://max578.github.io/masque/reference/clean_table.md),
  which always runs first. Default `"auto"`.

- quiet:

  Logical. When `FALSE` (default) a `cli` summary is printed.

## Value

An object of class `masque_conformance`: a list with

- `data` - the conformed data frame;

- `cleaning` - the `masque_cleaning` record from
  [`clean_table()`](https://max578.github.io/masque/reference/clean_table.md);

- `merges` - one row per near-duplicate pair considered (`col`, `from`,
  `to`, `n_from`, `n_to`, `applied`, `reason`);

- `types` - one row per column whose storage was considered (`col`,
  `from`, `to`, `applied`, `reason`);

- `assumptions` - every decision as a plain sentence (`col`,
  `assumption`, `applied`), which is the thing to read;

- `modes` - the modes applied.

## Details

Both are **off by default**. The default `"report"` mode names every
change it would make, in plain words, and applies none of them, because
a merged category and a coerced type are decisions about what the data
*means* and masque does not make those silently. Set a mode to `"auto"`
to apply them, and the assumption behind each one is recorded in the
returned object.

Storage is decided **before** categories, deliberately. A column of
numbers or dates held as text is not a set of categories, and proposing
to merge `"4.2"` into `"4.4"` because they differ by one character is
how an automatic cleaner destroys data. Only columns that remain
categorical are considered for merging, and a one-character edit between
labels shorter than four characters is ignored, because `"a"` and `"b"`
are one edit apart and are plainly different things.

What it deliberately does not do: merge two labels that differ by an
edit when neither spelling is the more common, coerce a column whose
values do not all parse, or touch a numeric column's storage. Each is
reported as a `not applied` row with the reason, so the gap is visible
rather than silent.

## See also

[`clean_table()`](https://max578.github.io/masque/reference/clean_table.md)
for the safe fixes,
[`propose_roles()`](https://max578.github.io/masque/reference/propose_roles.md)
for what a column is,
[`mask()`](https://max578.github.io/masque/reference/mask.md) for the
round-trip.

## Examples

``` r
df <- data.frame(
  state = c("NSW", "Nsw", "NSW", "VIC", "VIC"),
  yield = c("3.1", "2.9", "5.0", "4.2", "3.8"),
  sown  = c("2024-05-01", "2024-05-03", "2024-05-01", "2024-05-08", "2024-05-08"),
  stringsAsFactors = FALSE
)
# report only: nothing is changed
cf <- conform_table(df, quiet = TRUE)
cf$assumptions
#>     col
#> 1 state
#> 2 state
#> 3 yield
#> 4  sown
#>                                                                                           assumption
#> 1 "Nsw" and "NSW" are the same category, recorded as "NSW" (differs from NSW by capitalisation only)
#> 2                    stored as factor rather than character, because 3 distinct labels over 5 values
#> 3                    stored as numeric rather than character, because every value parses as a number
#> 4               stored as Date rather than character, because every value parses as an ISO-8601 date
#>   applied
#> 1   FALSE
#> 2   FALSE
#> 3   FALSE
#> 4   FALSE

# apply the decisions
cf2 <- conform_table(df, merge_labels = "auto", types = "auto", quiet = TRUE)
str(cf2$data)
#> 'data.frame':    5 obs. of  3 variables:
#>  $ state: Factor w/ 2 levels "NSW","VIC": 1 1 1 2 2
#>  $ yield: num  3.1 2.9 5 4.2 3.8
#>  $ sown : Date, format: "2024-05-01" "2024-05-03" ...
```
