# Coarsen geographic coordinates by an on-land privacy jitter

Displaces each latitude / longitude pair by a small random distance, in
place, so a synthetic table can carry realistic coordinates without
revealing the true location of a field, farm or site. Two
geographic-masking schemes are offered. The default `"donut"` displaces
every point by a distance drawn uniformly (by area) from an annulus
between `min_km` and `max_km`, in a random direction: this guarantees a
minimum displacement (a privacy floor – no point is left almost where it
started) while bounding the maximum drift. The `"gaussian"` scheme adds
independent normal noise of standard deviation `sd_km` to each axis; it
is simpler but has an unbounded tail, so a handful of points can move
much further than intended.

## Usage

``` r
jitter_coordinates(
  df,
  lat_col,
  lon_col,
  method = c("donut", "gaussian"),
  min_km = 5,
  max_km = 20,
  sd_km = 10,
  on_land = TRUE,
  max_tries = 100L,
  seed = NULL
)
```

## Arguments

- df:

  A data frame containing the coordinate columns.

- lat_col, lon_col:

  Column names of the latitude and longitude (numeric, in decimal
  degrees).

- method:

  `"donut"` (default) or `"gaussian"`.

- min_km, max_km:

  Inner and outer radii of the donut, in kilometres (used when
  `method = "donut"`). Every point moves at least `min_km` and at most
  `max_km`.

- sd_km:

  Per-axis standard deviation in kilometres (used when
  `method = "gaussian"`).

- on_land:

  Controls the land constraint. `TRUE` (default) rejects any
  displacement that lands in the sea, using
  [`maps::map.where()`](https://rdrr.io/pkg/maps/man/map.where.html)
  (requires the `maps` package). A function `function(lon, lat)`
  returning a logical vector supplies your own test (for example an
  `sf`-based high-resolution coastline). `FALSE` applies no constraint.

- max_tries:

  Maximum re-draws per point before giving up and leaving it unchanged
  (with a warning). Default `100`.

- seed:

  Optional integer seed for reproducibility. The caller's RNG state is
  preserved.

## Value

`df`, with `lat_col` and `lon_col` overwritten by the jittered
coordinates (rounded to five decimal places, about one metre).

## Details

The displacement is computed in kilometres and converted to degrees with
a `cos(latitude)` correction on longitude, so the true ground distance
matches the requested magnitude at any latitude. Each candidate is
checked against a land mask and re-drawn until it falls on land, so a
coastal point is never pushed offshore. The original NA pattern is
preserved cell-by-cell and the two axes stay paired (if either
coordinate is missing, both are set to NA).

## Choosing the magnitude

The right displacement is not a universal constant: it is calibrated to
the density of the entities you are protecting, so that the masked point
is spatially k-anonymous (roughly, at least k comparable entities lie
closer to the masked point than the true one). Individual-level urban
health data is typically masked with a standard deviation of about 1 km,
because cities are dense. Agricultural fields and farms are orders of
magnitude sparser, so a comparable level of protection needs a much
larger displacement – a donut of roughly 5 to 20 km (the default) moves
a point across several properties while keeping it in the same
agroclimatic region. For a formal guarantee, calibrate `min_km` /
`max_km` to the local field density to hit a target k-anonymity rather
than relying on the default.

## References

Hampton, K. H., Fitch, M. K., Allshouse, W. B., Doherty, I. A., Gesink,
D. C., Leone, P. A., Serre, M. L., & Miller, W. C. (2010). Mapping
health data: improved privacy protection with donut method geomasking.
*American Journal of Epidemiology, 172*(9), 1062-1069.
[doi:10.1093/aje/kwq248](https://doi.org/10.1093/aje/kwq248)

Zandbergen, P. A. (2014). Ensuring confidentiality of geocoded health
data: assessing geographic masking strategies for individual-level data.
*Advances in Medicine, 2014*, 567049.
[doi:10.1155/2014/567049](https://doi.org/10.1155/2014/567049)

## See also

[`synthesise_geospatial()`](https://max578.github.io/masque/reference/synthesise_geospatial.md)
to instead re-anchor coordinates at user-supplied fake centroids.

## Examples

``` r
df <- data.frame(
  site = c("A", "B", "C"),
  lat  = c(-34.9, -35.2, -33.6),
  lon  = c(138.6, 142.0, 148.2)
)
# Move each site 5-20 km, staying on land (needs the `maps` package):
if (requireNamespace("maps", quietly = TRUE)) {
  jitter_coordinates(df, "lat", "lon", min_km = 5, max_km = 20, seed = 1)
}
#>   site       lat      lon
#> 1    A -34.81596 138.5333
#> 2    B -35.16555 142.1346
#> 3    C -33.48829 148.1005
```
