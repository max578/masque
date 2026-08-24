# Coarsen geographic coordinates by an on-land privacy jitter

Displaces latitude / longitude pairs by a small random distance, in
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
  by = NULL,
  method = c("donut", "gaussian"),
  min_km = 5,
  max_km = 20,
  sd_km = 10,
  on_land = TRUE,
  max_tries = 100L,
  seed = NULL,
  .group = NULL
)
```

## Arguments

- df:

  A data frame containing the coordinate columns.

- lat_col, lon_col:

  Column names of the latitude and longitude (numeric, in decimal
  degrees).

- by:

  How rows are grouped into sites. `NULL` (default) groups rows that
  share an identical input coordinate pair. A character vector names one
  or more columns of `df` whose values identify a site. `FALSE`
  displaces every row independently (the pre-0.10.0 behaviour). See the
  section above.

- method:

  `"donut"` (default) or `"gaussian"`.

- min_km, max_km:

  Inner and outer radii of the donut, in kilometres (used when
  `method = "donut"`). Every site moves at least `min_km` and at most
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

  Maximum re-draws per site before giving up. Default `100`. A site that
  cannot be placed on land is set to `NA` on both axes, with a warning:
  masque never emits the true coordinate as though it were masked.

- seed:

  Optional integer seed for reproducibility. The caller's RNG state is
  preserved.

- .group:

  Internal. A pre-computed grouping vector of length `nrow(df)`, used by
  [`mask()`](https://max578.github.io/masque/reference/mask.md) to group
  by the *original* table's site structure. Takes precedence over `by`.
  Not for direct use.

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

## A coordinate belongs to a site, not to a row

One displacement is drawn per **site**, not per row, and broadcast to
every row of that site. A table that holds many rows per physical place
– plots within a trial, samples within a paddock, observations within a
farm – therefore comes back with one masked coordinate per place,
exactly as the source table has one true coordinate per place. `by`
chooses how a site is identified:

- `by = NULL` (default) treats rows that share an identical input
  coordinate pair as one site. This needs no user action and cannot
  alter genuinely point-level data, where every input pair is already
  distinct.

- `by = c("trial")` (one or more column names) treats rows sharing those
  values as one site, for the case where a site's recorded coordinates
  differ slightly between rows. Where such a group holds more than one
  distinct input coordinate, the group's row-weighted centroid is used
  and the consolidation is reported.

- `by = FALSE` restores the pre-0.10.0 behaviour of displacing every row
  independently, and warns if the input carries repeated coordinate
  pairs. It exists only so a table masked by an earlier version can be
  reproduced.

Per-row displacement of a repeated coordinate is not merely unfaithful,
it leaks. Donut displacement is isotropic, so the mean of many
independent draws around one true site converges on that site: averaging
the 360 rows of a single trial recovers the true position to a median
0.58 km, against the 5 km floor the donut was asked for. One draw per
site removes the estimator and leaves the full displacement in place.

## Rebuilding, and the displacement budget

One displacement per site holds *within* a masked table. It does not
hold across several. Each rebuild with a fresh seed draws independently,
so a site masked repeatedly and kept in several versions can be averaged
back out, exactly as its rows could be before. Measured at the 5-20 km
default:

|               |                       |
|---------------|-----------------------|
| Rebuilds kept | Median recovery error |
| 1             | 14.2 km               |
| 2             | 10.1 km               |
| 4             | 6.4 km                |
| 8             | 4.5 km                |
| 16            | 3.1 km                |

Eight kept rebuilds fall below the 5 km floor the donut was asked for.

The remedy costs nothing: **reuse the seed**. The same `seed` reproduces
the same displacement for the same sites, so any number of rebuilds
yields one point and nothing to average. Draw a fresh seed only when you
intend to supersede every earlier version, and retire the ones you
replace.

Choose the unit carefully. It is the finest grouping that denotes **one
physical place at one time**. For a multi-year trial series that is
location by year, not location alone: trials at one named location in
different seasons legitimately sit in different paddocks, and collapsing
that real variation would be as wrong as inventing it.

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
# Four plots at each of three sites: one masked coordinate per site.
df <- data.frame(
  site = rep(c("A", "B", "C"), each = 4),
  lat  = rep(c(-34.9, -35.2, -33.6), each = 4),
  lon  = rep(c(138.6, 142.0, 148.2), each = 4)
)
if (requireNamespace("maps", quietly = TRUE)) {
  out <- jitter_coordinates(df, "lat", "lon", min_km = 5, max_km = 20,
                            seed = 1)
  nrow(unique(out[c("lat", "lon")])) # 3, one pair per site
}
#> [1] 3
```
