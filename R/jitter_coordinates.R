#' Coarsen geographic coordinates by an on-land privacy jitter
#'
#' Displaces latitude / longitude pairs by a small random distance, in place,
#' so a synthetic table can carry realistic coordinates without revealing the
#' true location of a field, farm or site. Two geographic-masking schemes are
#' offered. The default `"donut"` displaces every point by a distance drawn
#' uniformly (by area) from an annulus between `min_km` and `max_km`, in a
#' random direction: this guarantees a minimum displacement (a privacy floor --
#' no point is left almost where it started) while bounding the maximum drift.
#' The `"gaussian"` scheme adds independent normal noise of standard deviation
#' `sd_km` to each axis; it is simpler but has an unbounded tail, so a handful
#' of points can move much further than intended.
#'
#' The displacement is computed in kilometres and converted to degrees with a
#' `cos(latitude)` correction on longitude, so the true ground distance matches
#' the requested magnitude at any latitude. Each candidate is checked against a
#' land mask and re-drawn until it falls on land, so a coastal point is never
#' pushed offshore. The original NA pattern is preserved cell-by-cell and the
#' two axes stay paired (if either coordinate is missing, both are set to NA).
#'
#' @section A coordinate belongs to a site, not to a row:
#'
#' One displacement is drawn per **site**, not per row, and broadcast to every
#' row of that site. A table that holds many rows per physical place -- plots
#' within a trial, samples within a paddock, observations within a farm --
#' therefore comes back with one masked coordinate per place, exactly as the
#' source table has one true coordinate per place. `by` chooses how a site is
#' identified:
#'
#' - `by = NULL` (default) treats rows that share an identical input coordinate
#'   pair as one site. This needs no user action and cannot alter genuinely
#'   point-level data, where every input pair is already distinct.
#' - `by = c("trial")` (one or more column names) treats rows sharing those
#'   values as one site, for the case where a site's recorded coordinates differ
#'   slightly between rows. Where such a group holds more than one distinct
#'   input coordinate, the group's row-weighted centroid is used and the
#'   consolidation is reported.
#' - `by = FALSE` restores the pre-0.10.0 behaviour of displacing every row
#'   independently, and warns if the input carries repeated coordinate pairs.
#'   It exists only so a table masked by an earlier version can be reproduced.
#'
#' Per-row displacement of a repeated coordinate is not merely unfaithful, it
#' leaks. Donut displacement is isotropic, so the mean of many independent
#' draws around one true site converges on that site: averaging the 360 rows of
#' a single trial recovers the true position to a median 0.58 km, against the
#' 5 km floor the donut was asked for. One draw per site removes the estimator
#' and leaves the full displacement in place.
#'
#' @section Rebuilding, and the displacement budget:
#'
#' One displacement per site holds *within* a masked table. It does not hold
#' across several. Each rebuild with a fresh seed draws independently, so a
#' site masked repeatedly and kept in several versions can be averaged back
#' out, exactly as its rows could be before. Measured at the 5-20 km default:
#'
#' \tabular{lr}{
#'   Rebuilds kept \tab Median recovery error \cr
#'   1  \tab 14.2 km \cr
#'   2  \tab 10.1 km \cr
#'   4  \tab  6.4 km \cr
#'   8  \tab  4.5 km \cr
#'   16 \tab  3.1 km
#' }
#'
#' Eight kept rebuilds fall below the 5 km floor the donut was asked for.
#'
#' The remedy costs nothing: **reuse the seed**. The same `seed` reproduces the
#' same displacement for the same sites, so any number of rebuilds yields one
#' point and nothing to average. Draw a fresh seed only when you intend to
#' supersede every earlier version, and retire the ones you replace.
#'
#' Choose the unit carefully. It is the finest grouping that denotes **one
#' physical place at one time**. For a multi-year trial series that is location
#' by year, not location alone: trials at one named location in different
#' seasons legitimately sit in different paddocks, and collapsing that real
#' variation would be as wrong as inventing it.
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
#' @param by How rows are grouped into sites. `NULL` (default) groups rows that
#'   share an identical input coordinate pair. A character vector names one or
#'   more columns of `df` whose values identify a site. `FALSE` displaces every
#'   row independently (the pre-0.10.0 behaviour). See the section above.
#' @param method `"donut"` (default) or `"gaussian"`.
#' @param min_km,max_km Inner and outer radii of the donut, in kilometres
#'   (used when `method = "donut"`). Every site moves at least `min_km` and at
#'   most `max_km`.
#' @param sd_km Per-axis standard deviation in kilometres (used when
#'   `method = "gaussian"`).
#' @param on_land Controls the land constraint. `TRUE` (default) rejects any
#'   displacement that lands in the sea, using [maps::map.where()] (requires the
#'   `maps` package). A function `function(lon, lat)` returning a logical vector
#'   supplies your own test (for example an `sf`-based high-resolution
#'   coastline). `FALSE` applies no constraint.
#' @param max_tries Maximum re-draws per site before giving up. Default `100`.
#'   A site that cannot be placed on land is set to `NA` on both axes, with a
#'   warning: masque never emits the true coordinate as though it were masked.
#' @param seed Optional integer seed for reproducibility. The caller's RNG state
#'   is preserved.
#' @param .group Internal. A pre-computed grouping vector of length
#'   `nrow(df)`, used by [mask()] to group by the *original* table's site
#'   structure. Takes precedence over `by`. Not for direct use.
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
#' # Four plots at each of three sites: one masked coordinate per site.
#' df <- data.frame(
#'   site = rep(c("A", "B", "C"), each = 4),
#'   lat  = rep(c(-34.9, -35.2, -33.6), each = 4),
#'   lon  = rep(c(138.6, 142.0, 148.2), each = 4)
#' )
#' if (requireNamespace("maps", quietly = TRUE)) {
#'   out <- jitter_coordinates(df, "lat", "lon", min_km = 5, max_km = 20,
#'                             seed = 1)
#'   nrow(unique(out[c("lat", "lon")])) # 3, one pair per site
#' }
#'
#' @seealso [synthesise_geospatial()] to instead re-anchor coordinates at
#'   user-supplied fake centroids.
#'
#' @export
jitter_coordinates <- function(df, lat_col, lon_col,
                               by = NULL,
                               method = c("donut", "gaussian"),
                               min_km = 5, max_km = 20, sd_km = 10,
                               on_land = TRUE, max_tries = 100L,
                               seed = NULL,
                               .group = NULL) {
  res <- .jitter_coords_impl(
    df, lat_col, lon_col,
    by = by, method = method, min_km = min_km, max_km = max_km,
    sd_km = sd_km, on_land = on_land, max_tries = max_tries,
    seed = seed, .group = .group
  )
  res$df
}

# Internal worker behind jitter_coordinates(). Returns both the jittered frame
# and a structured report (site count, consolidated sites, unplaced sites) so
# mask() can record what happened on the recipe instead of re-parsing warnings.
.jitter_coords_impl <- function(df, lat_col, lon_col,
                                by = NULL,
                                method = c("donut", "gaussian"),
                                min_km = 5, max_km = 20, sd_km = 10,
                                on_land = TRUE, max_tries = 100L,
                                seed = NULL,
                                .group = NULL) {
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
    cli::cli_abort(
      "Need `0 <= min_km < max_km`; got min_km = {min_km}, max_km = {max_km}."
    )
  }
  if (method == "gaussian" && sd_km <= 0) {
    cli::cli_abort("`sd_km` must be positive.")
  }
  grouping <- .resolve_coord_grouping(by, .group, df)

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

  valid <- which(!pair_na)
  if (!length(valid)) {
    df[[lat_col]] <- new_lat
    df[[lon_col]] <- new_lon
    return(list(df = df, report = .coord_report(grouping$mode, 0L, 0L)))
  }

  lat_v <- lat[valid]
  lon_v <- lon[valid]
  # Exact pair identity: match() on doubles compares values, not formatted
  # text, so two rows are one site only when their coordinates are truly
  # identical.
  pair_key <- paste(
    match(lat_v, unique(lat_v)), match(lon_v, unique(lon_v)),
    sep = "\r"
  )

  site_key <- switch(grouping$mode,
    coordinate = pair_key,
    row        = as.character(seq_along(valid)),
    column     = .site_key(lapply(grouping$key, function(x) x[valid]))
  )
  ug <- unique(site_key)
  gi <- match(site_key, ug)
  n_sites <- length(ug)

  if (identical(grouping$mode, "row") && anyDuplicated(pair_key)) {
    n_shared <- sum(duplicated(pair_key))
    cli::cli_warn(c(
      paste0(
        "`by = FALSE`: {n_shared} row{?s} share a coordinate pair with ",
        "another row and will be displaced independently."
      ),
      x = paste0(
        "Identical positions are split apart, which fabricates within-site ",
        "variation and lets the site's true centroid be recovered by averaging."
      ),
      i = paste0(
        "Use {.code by = NULL} (the default) to keep each site's rows ",
        "together, or name the site columns with {.arg by}."
      )
    ), class = "masque_geo_ungrouped")
  }

  # One source coordinate per site. In coordinate and row mode every row of a
  # site already carries the same pair, so the first row's value is exact. In
  # column mode a site whose rows disagree is consolidated to its row-weighted
  # centroid, which is reported because it discards real variation.
  first_idx <- match(seq_len(n_sites), gi)
  src_lat <- lat_v[first_idx]
  src_lon <- lon_v[first_idx]
  consolidated <- character()
  if (identical(grouping$mode, "column")) {
    combos <- unique(data.frame(g = gi, p = pair_key, stringsAsFactors = FALSE))
    hit <- which(tabulate(combos$g, nbins = n_sites) > 1L)
    if (length(hit)) {
      cnt <- tabulate(gi, nbins = n_sites)
      src_lat <- as.numeric(rowsum(lat_v, gi, reorder = TRUE)) / cnt
      src_lon <- as.numeric(rowsum(lon_v, gi, reorder = TRUE)) / cnt
      consolidated <- ug[hit]
      spread <- .site_spread_km(lat_v, lon_v, gi, hit)
      shown <- utils::head(consolidated, 5L)
      cli::cli_warn(c(
        paste0(
          "{length(hit)} site{?s} named by {.arg by} hold more than one ",
          "input coordinate and were consolidated to the site centroid."
        ),
        i = "Site{?s}: {.val {shown}}.",
        i = "Widest internal spread {round(max(spread), 1)} km."
      ), class = "masque_geo_consolidated")
      wide_limit <- if (method == "donut") max_km else 3 * sd_km
      wide <- hit[spread > wide_limit]
      if (length(wide)) {
        wide_shown <- utils::head(ug[wide], 5L)
        cli::cli_warn(c(
          paste0(
            "{length(wide)} site{?s} span more than the displacement radius ",
            "({round(wide_limit, 1)} km) internally."
          ),
          x = paste0(
            "Consolidating them discards real spatial structure; {.arg by} ",
            "may name too coarse a unit."
          ),
          i = "Site{?s}: {.val {wide_shown}}."
        ), class = "masque_geo_wide_group")
      }
    }
  }

  out_lat <- rep(NA_real_, n_sites)
  out_lon <- rep(NA_real_, n_sites)
  pending <- seq_len(n_sites)
  tries <- 0L
  while (length(pending) > 0L && tries < max_tries) {
    tries <- tries + 1L
    la <- src_lat[pending]
    lo <- src_lon[pending]
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
    out_lat[pending[ok]] <- round(cand_lat[ok], 5L)
    out_lon[pending[ok]] <- round(cand_lon[ok], 5L)
    pending <- pending[!ok]
  }
  if (length(pending) > 0L) {
    # Fail closed. Leaving the site unchanged would ship the TRUE coordinate
    # inside a table the caller believes is masked.
    cli::cli_warn(c(
      paste0(
        "{length(pending)} site{?s} could not be placed on land in ",
        "{max_tries} tries."
      ),
      x = "Set to NA on both axes rather than left at the true coordinate.",
      i = paste0(
        "Increase {.arg max_tries}, widen the radii, or pass a finer ",
        "{.arg on_land} test."
      )
    ), class = "masque_geo_unplaced")
  }

  new_lat[valid] <- out_lat[gi]
  new_lon[valid] <- out_lon[gi]
  df[[lat_col]] <- new_lat
  df[[lon_col]] <- new_lon
  list(
    df = df,
    report = .coord_report(
      grouping$mode, n_sites, length(valid),
      consolidated = consolidated, unplaced = length(pending)
    )
  )
}

# A structured account of one coordinate-pair jitter, recorded on the recipe.
.coord_report <- function(mode, n_sites, n_rows,
                          consolidated = character(), unplaced = 0L) {
  list(
    grouping     = mode,
    n_sites      = as.integer(n_sites),
    n_rows       = as.integer(n_rows),
    consolidated = as.character(consolidated),
    unplaced     = as.integer(unplaced)
  )
}

# Resolve `by` / `.group` into a grouping mode plus, for column mode, the
# grouping vectors themselves. `.group` (pre-computed by mask() from the
# ORIGINAL table) takes precedence over `by`.
.resolve_coord_grouping <- function(by, .group, df) {
  if (!is.null(.group)) {
    if (length(.group) != nrow(df)) {
      cli::cli_abort(paste0(
        "`.group` must have one entry per row of `df` ({nrow(df)}); ",
        "got {length(.group)}."
      ))
    }
    return(list(mode = "column", key = list(.group)))
  }
  if (is.null(by)) {
    return(list(mode = "coordinate", key = NULL))
  }
  if (isFALSE(by)) {
    return(list(mode = "row", key = NULL))
  }
  if (isTRUE(by)) {
    cli::cli_abort(c(
      "`by = TRUE` is not a grouping.",
      i = paste0(
        "Use {.code by = NULL} to group rows by identical input coordinate, ",
        "or name the site columns, for example {.code by = \"trial\"}."
      )
    ))
  }
  if (!is.character(by) || !length(by)) {
    cli::cli_abort(paste0(
      "`by` must be `NULL`, `FALSE`, or a character vector of column names; ",
      "got {.cls {class(by)[1]}}."
    ))
  }
  missing_cols <- setdiff(by, names(df))
  if (length(missing_cols)) {
    cli::cli_abort(
      "`by` column{?s} not found in `df`: {.field {missing_cols}}."
    )
  }
  list(mode = "column", key = unname(as.list(df[, by, drop = FALSE])))
}

# Collapse one or more grouping vectors into a single site key. NA is a level
# like any other: rows with a missing site label form their own site.
.site_key <- function(cols) {
  parts <- lapply(cols, function(x) {
    x <- as.character(x)
    x[is.na(x)] <- "NA"
    x
  })
  do.call(paste, c(parts, list(sep = "\r")))
}

# Bounding-box diagonal, in km, of each named site's input coordinates.
.site_spread_km <- function(lat_v, lon_v, gi, which_sites) {
  sp <- split(seq_along(gi), gi)
  vapply(which_sites, function(k) {
    idx <- sp[[as.character(k)]]
    la <- lat_v[idx]
    lo <- lon_v[idx]
    d_lat <- diff(range(la)) * 111.32
    d_lon <- diff(range(lo)) * 111.32 * cos(mean(la) * pi / 180)
    sqrt(d_lat^2 + d_lon^2)
  }, numeric(1))
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
# of either. Jitter parameters default to a donut of 5-20 km on land, grouped
# by identical input coordinate.
.normalise_coords <- function(coords, df) {
  if (is.null(coords)) {
    return(list())
  }
  if (is.character(coords) && length(names(coords))) {
    coords <- list(coords)
  }
  if (!is.list(coords)) {
    cli::cli_abort(c(
      paste0(
        "`coords` must be a named `c(lat =, lon =)`, a ",
        "`list(lat =, lon =, ...)`, or a list of them."
      )
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
        cli::cli_abort(
          "Coordinate column {.field {cn}} must be numeric decimal degrees."
        )
      }
    }
    # A `c(lat = "a", lon = "b", min_km = 5)` vector coerces the numbers to
    # strings; coerce them back so both the vector and the list forms work.
    num <- function(x, default) if (is.null(x)) default else as.numeric(x)
    on_land <- spec$on_land
    if (is.null(on_land)) {
      on_land <- TRUE
    } else if (is.character(on_land)) {
      on_land <- as.logical(on_land)
    }
    list(
      lat     = as.character(spec$lat),
      lon     = as.character(spec$lon),
      by      = .normalise_coord_by(spec$by, df),
      method  = spec$method %||% "donut",
      min_km  = num(spec$min_km, 5),
      max_km  = num(spec$max_km, 20),
      sd_km   = num(spec$sd_km, 10),
      on_land = on_land
    )
  })
}

# Normalise one spec's `by`. NULL keeps the default (group by identical input
# coordinate); FALSE is the legacy per-row draw; a character vector names site
# columns, which must exist in the ORIGINAL table because that is where the
# site structure lives. The `c()` form stringifies everything, so "FALSE"
# coming back as text is read as the logical it was written as.
.normalise_coord_by <- function(by, df) {
  if (is.null(by)) {
    return(NULL)
  }
  if (is.character(by) && length(by) == 1L && by %in% c("TRUE", "FALSE")) {
    by <- as.logical(by)
  }
  if (isFALSE(by)) {
    return(FALSE)
  }
  if (isTRUE(by)) {
    cli::cli_abort(c(
      "`by = TRUE` is not a grouping.",
      i = paste0(
        "Omit {.arg by} to group rows by identical input coordinate, or name ",
        "the site columns, for example {.code by = \"trial\"}."
      )
    ))
  }
  if (!is.character(by)) {
    cli::cli_abort(paste0(
      "A `coords` entry's `by` must be `NULL`, `FALSE`, or column names; ",
      "got {.cls {class(by)[1]}}."
    ))
  }
  missing_cols <- setdiff(by, names(df))
  if (length(missing_cols)) {
    cli::cli_abort(c(
      "`coords` grouping column{?s} not found: {.field {missing_cols}}.",
      i = paste0(
        "Sites are grouped on the original table, so {.arg by} names its ",
        "columns."
      )
    ))
  }
  by
}

# All coordinate column names across a set of normalised specs.
.coord_cols <- function(specs) {
  unique(unlist(lapply(specs, function(s) c(s$lat, s$lon)), use.names = FALSE))
}

# Apply each spec's jitter to the synthetic frame, in place, and return the
# frame alongside one report per spec.
#
# `original` supplies the site grouping: a `by` column may be aliased, permuted
# or dropped in the synthetic, but the site structure being preserved is a
# property of the source table, so the grouping key is built there.
#
# Each spec draws from its own sub-stream. Passing one seed to every spec (as
# masque did before 0.10.0) gave two declared coordinate pairs in one table
# identical displacement vectors.
.apply_coord_jitter <- function(synth, specs, seed, original = NULL) {
  n <- length(specs)
  if (!n) {
    return(list(df = synth, reports = list()))
  }
  sub_seeds <- with_rng_state(
    seed, sample.int(.Machine$integer.max, n)
  )
  reports <- vector("list", n)
  for (i in seq_len(n)) {
    s <- specs[[i]]
    grp <- NULL
    if (is.character(s$by)) {
      if (is.null(original)) {
        cli::cli_abort(
          "Internal: coordinate grouping needs the original table."
        )
      }
      grp <- .site_key(unname(as.list(original[, s$by, drop = FALSE])))
    }
    res <- .jitter_coords_impl(
      synth, lat_col = s$lat, lon_col = s$lon,
      by = if (isFALSE(s$by)) FALSE else NULL,
      method = s$method, min_km = s$min_km, max_km = s$max_km,
      sd_km = s$sd_km, on_land = s$on_land, seed = sub_seeds[[i]],
      .group = grp
    )
    synth <- res$df
    reports[[i]] <- c(
      list(lat = s$lat, lon = s$lon, method = s$method,
           min_km = s$min_km, max_km = s$max_km, sd_km = s$sd_km,
           by = if (is.null(s$by)) NA_character_ else as.character(s$by)),
      res$report
    )
  }
  list(df = synth, reports = reports)
}

# One human-readable line per coordinate pair, recorded on the recipe so the
# site grouping a clone was built under is visible without re-running mask().
.coord_report_line <- function(rep) {
  grouped <- switch(rep$grouping,
    coordinate = "grouped by identical input coordinate",
    column     = paste0("grouped by ", paste(rep$by, collapse = " + ")),
    row        = "ungrouped (one displacement per row)"
  )
  extra <- character()
  if (length(rep$consolidated)) {
    extra <- c(extra, sprintf(
      "%d site(s) consolidated to a centroid", length(rep$consolidated)
    ))
  }
  if (rep$unplaced > 0L) {
    extra <- c(extra, sprintf(
      "%d site(s) unplaceable on land, set to NA", rep$unplaced
    ))
  }
  sprintf(
    "coords %s/%s: %s, %d site(s) over %d row(s)%s.",
    rep$lat, rep$lon, grouped, rep$n_sites, rep$n_rows,
    if (length(extra)) paste0("; ", paste(extra, collapse = "; ")) else ""
  )
}

# The same account, phrased for the recipe print method.
.coord_print_line <- function(rep) {
  grouped <- switch(rep$grouping,
    coordinate = "one site per distinct input coordinate",
    column     = paste0("sites from ", paste(rep$by, collapse = " + ")),
    row        = "UNGROUPED: one displacement per row"
  )
  extra <- character()
  if (length(rep$consolidated)) {
    extra <- c(extra, sprintf(
      "%d consolidated", length(rep$consolidated)
    ))
  }
  if (rep$unplaced > 0L) {
    extra <- c(extra, sprintf("%d unplaceable, set to NA", rep$unplaced))
  }
  sprintf(
    "%s / %s: %s jitter %s, %s, %d site(s) over %d row(s)%s",
    rep$lat, rep$lon, rep$method,
    if (identical(rep$method, "donut")) {
      sprintf("%g-%g km", rep$min_km, rep$max_km)
    } else {
      sprintf("sd %g km", rep$sd_km)
    },
    grouped, rep$n_sites, rep$n_rows,
    if (length(extra)) paste0(" (", paste(extra, collapse = "; "), ")") else ""
  )
}
