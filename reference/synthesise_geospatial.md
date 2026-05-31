# Re-anchor synthetic geospatial coordinates at plausible-but-fake locations

Replaces the latitude / longitude values in a masqued data frame with
coordinates anchored at user-supplied centroids and clustered to
preserve the original's site-count-per-anchor structure. The function
never reads the real coordinates beyond counting how many distinct sites
the original holds per anchor level — so it leaks the
replication-per-site distribution and the count of distinct sites,
nothing more.

## Usage

``` r
synthesise_geospatial(
  synth,
  original,
  anchor_col,
  lat_col,
  lon_col,
  anchor_centroids,
  site_spread_deg = 0.6,
  jitter_deg = 0.05,
  seed = NULL
)
```

## Arguments

- synth:

  A synthetic data frame (typically `synthetic(mask(...))`).

- original:

  The original data frame from which `synth` was derived (needed only to
  count distinct sites per anchor).

- anchor_col:

  Name of the column whose levels anchor each cluster (e.g.,
  `"M_STATE"`). Must exist in both `synth` and `original`.

- lat_col, lon_col:

  Column names of the latitude and longitude fields to overwrite in
  `synth`.

- anchor_centroids:

  Named list keyed by anchor levels; each element is a length-2 numeric
  named `c(lat, lon)`. The user supplies plausible centroids (e.g.,
  state centroids); the function never infers them from the original to
  avoid leaking position information.

- site_spread_deg:

  Half-width of the box (in decimal degrees) around each anchor centroid
  within which fake site centroids are uniformly placed. Default `0.6`.

- jitter_deg:

  Within-site uniform jitter (in decimal degrees) added to each row's
  assigned site centroid. Default `0.05`.

- seed:

  Optional integer seed for reproducibility. The function uses
  [`withr::local_preserve_seed()`](https://withr.r-lib.org/reference/with_seed.html)
  so the caller's RNG state is left untouched.

## Value

`synth`, with `lat_col` and `lon_col` overwritten by the re-anchored
coordinates.

## Details

Typical use: after
[`mask()`](https://max578.github.io/masque/reference/mask.md) produces a
synthetic with copula-drawn or missing coordinates, call
`synthesise_geospatial()` to substitute plausible points. The synthetic
ends up with:

- the same number of distinct sites per anchor level:

  (e.g., if the original has five distinct trial sites in NSW, the
  synthetic will have five fake sites in NSW);

- the original's per-site replication distribution:

  (each fake site receives a share of the synthetic rows proportional to
  its real counterpart's count);

- within-site tight clustering and between-site spread:

  (small jitter within site; larger spread between sites within each
  anchor centroid's neighbourhood).

What the function does **not** preserve:

- the real positions of the sites (they are random within a user-defined
  neighbourhood of each anchor centroid);

- the relative spacing or bearings between real sites;

- any spatial autocorrelation in the outcome.

Coordinates that are `NA` in the original remain `NA` in the synthetic —
the NA pattern is preserved cell-by-cell.

## Examples

``` r
# \donttest{
# Toy example: 50 rows split across two states.
set.seed(1)
n <- 50
df <- data.frame(
  state = sample(c("NSW", "VIC"), n, replace = TRUE),
  lat   = stats::rnorm(n, -33, 0.3),
  lon   = stats::rnorm(n, 145, 0.3),
  y     = stats::rnorm(n)
)
roles <- propose_roles(df, detect = FALSE)
roles$role[roles$col == "y"] <- "outcome"
roles$role[roles$col %in% c("lat", "lon")] <- "covariate"
roles$role[roles$col == "state"] <- "design"
m <- mask(df, roles, mode = "collaborate", seed = 1L)
#> Warning: audit_mask() flagged HIGH leakage on column(s): lat, lon
centroids <- list(
  NSW = c(lat = -32.5, lon = 147),
  VIC = c(lat = -36.5, lon = 144)
)
synth_geo <- synthesise_geospatial(
  synthetic(m), df,
  anchor_col = "state", lat_col = "lat", lon_col = "lon",
  anchor_centroids = centroids, seed = 2L
)
head(synth_geo[, c("state", "lat", "lon")])
#> # A tibble: 6 × 3
#>   state   lat   lon
#>   <chr> <dbl> <dbl>
#> 1 NSW   -33.0  147.
#> 2 VIC   -36.8  144.
#> 3 NSW   -32.2  147.
#> 4 NSW   -32.9  147.
#> 5 VIC   -36.7  144.
#> 6 NSW   -32.9  146.
# }
```
