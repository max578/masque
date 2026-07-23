#' Coarsen geographic coordinates by an on-land privacy jitter
#'
#' Displaces each latitude / longitude pair by a small random distance, in
#' place, so a synthetic table can carry realistic coordinates without
#' revealing the true location of a field, farm or site. Two geographic-masking
#' schemes are offered. The default `"donut"` displaces every point by a
#' distance drawn uniformly (by area) from an annulus between `min_km` and
#' `max_km`, in a random direction: this guarantees a minimum displacement (a
#' privacy floor -- no point is left almost where it started) while bounding the
#' maximum drift. The `"gaussian"` scheme adds independent normal noise of
#' standard deviation `sd_km` to each axis; it is simpler but has an unbounded
#' tail, so a handful of points can move much further than intended.
#'
#' The displacement is computed in kilometres and converted to degrees with a
#' `cos(latitude)` correction on longitude, so the true ground distance matches
#' the requested magnitude at any latitude. Each candidate is checked against a
#' land mask and re-drawn until it falls on land, so a coastal point is never
#' pushed offshore. The original NA pattern is preserved cell-by-cell and the
#' two axes stay paired (if either coordinate is missing, both are set to NA).
#'
#' @section Choosing the magnitude:
#'
#' The right displacement is not a universal constant: it is calibrated to the
#' density of the entities you are protecting, so that the masked point is
#' spatially k-anonymous (roughly, at least k comparable entities lie closer to
#' the masked point than the true one). Individual-level urban health data is
#' typically masked with a standard deviation of about 1 km, because cities are
#' dense. Agricultural fields and farms are orders of magnitude sparser, so a
#' comparable level of protection needs a much larger displacement -- a donut of
#' roughly 5 to 20 km (the default) moves a point across several properties
#' while keeping it in the same agroclimatic region. For a formal guarantee,
#' calibrate `min_km` / `max_km` to the local field density to hit a target
#' k-anonymity rather than relying on the default.
#'
#' @param df A data frame containing the coordinate columns.
#' @param lat_col,lon_col Column names of the latitude and longitude (numeric,
#'   in decimal degrees).
#' @param method `"donut"` (default) or `"gaussian"`.
#' @param min_km,max_km Inner and outer radii of the donut, in kilometres
#'   (used when `method = "donut"`). Every point moves at least `min_km` and at
#'   most `max_km`.
#' @param sd_km Per-axis standard deviation in kilometres (used when
#'   `method = "gaussian"`).
#' @param on_land Controls the land constraint. `TRUE` (default) rejects any
#'   displacement that lands in the sea, using [maps::map.where()] (requires the
#'   `maps` package). A function `function(lon, lat)` returning a logical vector
#'   supplies your own test (for example an `sf`-based high-resolution
#'   coastline). `FALSE` applies no constraint.
#' @param max_tries Maximum re-draws per point before giving up and leaving it
#'   unchanged (with a warning). Default `100`.
#' @param seed Optional integer seed for reproducibility. The caller's RNG state
#'   is preserved.
#'
#' @return `df`, with `lat_col` and `lon_col` overwritten by the jittered
#'   coordinates (rounded to five decimal places, about one metre).
#'
#' @references
#' Hampton, K. H., Fitch, M. K., Allshouse, W. B., Doherty, I. A., Gesink,
#' D. C., Leone, P. A., Serre, M. L., & Miller, W. C. (2010). Mapping health
#' data: improved privacy protection with donut method geomasking. *American
#' Journal of Epidemiology, 172*(9), 1062-1069. \doi{10.1093/aje/kwq248}
#'
#' Zandbergen, P. A. (2014). Ensuring confidentiality of geocoded health data:
#' assessing geographic masking strategies for individual-level data. *Advances
#' in Medicine, 2014*, 567049. \doi{10.1155/2014/567049}
#'
#' @examples
#' df <- data.frame(
#'   site = c("A", "B", "C"),
#'   lat  = c(-34.9, -35.2, -33.6),
#'   lon  = c(138.6, 142.0, 148.2)
#' )
#' # Move each site 5-20 km, staying on land (needs the `maps` package):
#' if (requireNamespace("maps", quietly = TRUE)) {
#'   jitter_coordinates(df, "lat", "lon", min_km = 5, max_km = 20, seed = 1)
#' }
#'
#' @seealso [synthesise_geospatial()] to instead re-anchor coordinates at
#'   user-supplied fake centroids.
#'
#' @export
jitter_coordinates <- function(df, lat_col, lon_col,
                               method = c("donut", "gaussian"),
                               min_km = 5, max_km = 20, sd_km = 10,
                               on_land = TRUE, max_tries = 100L,
                               seed = NULL) {
  method <- match.arg(method)
  if (!is.data.frame(df)) {
    cli::cli_abort("`df` must be a data frame; got {.cls {class(df)[1]}}.")
  }
  for (cn in c(lat_col, lon_col)) {
    if (!cn %in% names(df)) {
      cli::cli_abort("Column {.field {cn}} not found in `df`.")
    }
    if (!is.numeric(df[[cn]])) {
      cli::cli_abort("Column {.field {cn}} must be numeric decimal degrees.")
    }
  }
  if (method == "donut" && (min_km < 0 || max_km <= min_km)) {
    cli::cli_abort("Need `0 <= min_km < max_km`; got min_km = {min_km}, max_km = {max_km}.")
  }
  if (method == "gaussian" && sd_km <= 0) {
    cli::cli_abort("`sd_km` must be positive.")
  }

  land_fn <- .resolve_land_fn(on_land)

  withr::local_preserve_seed()
  if (!is.null(seed)) set.seed(seed)

  lat <- df[[lat_col]]
  lon <- df[[lon_col]]
  new_lat <- lat
  new_lon <- lon
  # Pairing: a coordinate is only valid when both axes are present.
  pair_na <- is.na(lat) | is.na(lon)
  new_lat[pair_na] <- NA_real_
  new_lon[pair_na] <- NA_real_

  pending <- which(!pair_na)
  tries <- 0L
  while (length(pending) > 0L && tries < max_tries) {
    tries <- tries + 1L
    la <- lat[pending]
    lo <- lon[pending]
    if (method == "donut") {
      # sqrt of a uniform on [min^2, max^2] is uniform by AREA over the annulus.
      radius <- sqrt(stats::runif(length(pending), min_km^2, max_km^2))
      bearing <- stats::runif(length(pending), 0, 2 * pi)
      d_north <- radius * cos(bearing)
      d_east <- radius * sin(bearing)
    } else {
      d_north <- stats::rnorm(length(pending), 0, sd_km)
      d_east <- stats::rnorm(length(pending), 0, sd_km)
    }
    cand_lat <- la + d_north / 111.32
    cand_lon <- lo + d_east / (111.32 * cos(la * pi / 180))
    ok <- land_fn(cand_lon, cand_lat)
    ok[is.na(ok)] <- FALSE
    new_lat[pending[ok]] <- round(cand_lat[ok], 5L)
    new_lon[pending[ok]] <- round(cand_lon[ok], 5L)
    pending <- pending[!ok]
  }
  if (length(pending) > 0L) {
    cli::cli_warn(c(
      "{length(pending)} coordinate(s) could not be placed on land in {max_tries} tries.",
      i = "Left unchanged. Increase {.arg max_tries}, widen the radii, or pass a finer {.arg on_land} test."
    ), class = "masque_geo_unplaced")
  }
  df[[lat_col]] <- new_lat
  df[[lon_col]] <- new_lon
  df
}

# Resolve the `on_land` argument into a vectorised predicate (lon, lat) -> lgl.
.resolve_land_fn <- function(on_land) {
  if (is.function(on_land)) {
    return(on_land)
  }
  if (isTRUE(on_land)) {
    if (!requireNamespace("maps", quietly = TRUE)) {
      cli::cli_abort(c(
        "`on_land = TRUE` needs the {.pkg maps} package.",
        i = "Install {.pkg maps}, pass your own {.code function(lon, lat)} test, or set {.code on_land = FALSE}."
      ))
    }
    return(function(lo, la) !is.na(maps::map.where("world", lo, la)))
  }
  function(lo, la) rep(TRUE, length(lo))
}

# Normalise the `coords` argument of mask() into a list of fully-specified
# coordinate-pair jitter specs. Accepts a single named vector
# `c(lat = "a", lon = "b")`, a named list `list(lat = , lon = , ...)`, or a list
# of either. Jitter parameters default to a donut of 5-20 km on land.
.normalise_coords <- function(coords, df) {
  if (is.null(coords)) {
    return(list())
  }
  if (is.character(coords) && length(names(coords))) {
    coords <- list(coords)
  }
  if (!is.list(coords)) {
    cli::cli_abort(c(
      "`coords` must be a named `c(lat =, lon =)`, a `list(lat =, lon =, ...)`, or a list of them."
    ))
  }
  lapply(coords, function(spec) {
    if (is.character(spec)) spec <- as.list(spec)
    if (is.null(spec$lat) || is.null(spec$lon)) {
      cli::cli_abort("Each `coords` entry needs `lat` and `lon` column names.")
    }
    for (cn in c(spec$lat, spec$lon)) {
      if (!cn %in% names(df)) {
        cli::cli_abort("Coordinate column {.field {cn}} not found in `df`.")
      }
      if (!is.numeric(df[[cn]])) {
        cli::cli_abort("Coordinate column {.field {cn}} must be numeric decimal degrees.")
      }
    }
    list(
      lat     = spec$lat,
      lon     = spec$lon,
      method  = spec$method %||% "donut",
      min_km  = spec$min_km %||% 5,
      max_km  = spec$max_km %||% 20,
      sd_km   = spec$sd_km %||% 10,
      on_land = if (is.null(spec$on_land)) TRUE else spec$on_land
    )
  })
}

# All coordinate column names across a set of normalised specs.
.coord_cols <- function(specs) {
  unique(unlist(lapply(specs, function(s) c(s$lat, s$lon)), use.names = FALSE))
}

# Apply each spec's jitter to the synthetic frame, in place.
.apply_coord_jitter <- function(synth, specs, seed) {
  seed_i <- if (is.null(seed)) NULL else as.integer(seed)
  for (s in specs) {
    synth <- jitter_coordinates(
      synth, lat_col = s$lat, lon_col = s$lon, method = s$method,
      min_km = s$min_km, max_km = s$max_km, sd_km = s$sd_km,
      on_land = s$on_land, seed = seed_i
    )
  }
  synth
}
