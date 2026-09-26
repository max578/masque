#' Re-anchor synthetic geospatial coordinates at plausible-but-fake locations
#'
#' Replaces the latitude / longitude values in a masqued data frame with
#' coordinates anchored at user-supplied centroids and clustered to
#' preserve the original's site-count-per-anchor structure. The function
#' never reads the real coordinates beyond counting how many distinct
#' sites the original holds per anchor level -- so it leaks the
#' replication-per-site distribution and the count of distinct sites,
#' nothing more.
#'
#' Typical use: after `mask()` produces a synthetic with copula-drawn or
#' missing coordinates, call `synthesise_geospatial()` to substitute
#' plausible points. The synthetic ends up with:
#'
#' \describe{
#'   \item{the same number of distinct sites per anchor level}{
#'     (e.g., if the original has five distinct trial sites in NSW,
#'     the synthetic will have five fake sites in NSW);}
#'   \item{the original's per-site replication distribution}{
#'     (each fake site receives a share of the synthetic rows
#'     proportional to its real counterpart's count);}
#'   \item{within-site tight clustering and between-site spread}{
#'     (small jitter within site; larger spread between sites within
#'     each anchor centroid's neighbourhood).}
#' }
#'
#' What the function does **not** preserve:
#'
#' \itemize{
#'   \item the real positions of the sites (they are random within a
#'         user-defined neighbourhood of each anchor centroid);
#'   \item the relative spacing or bearings between real sites;
#'   \item any spatial autocorrelation in the outcome.
#' }
#'
#' Coordinates that are `NA` in the original remain `NA` in the
#' synthetic -- the NA pattern is preserved cell-by-cell.
#'
#' @param synth A synthetic data frame (typically `synthetic(mask(...))`).
#' @param original The original data frame from which `synth` was derived
#'   (needed only to count distinct sites per anchor).
#' @param anchor_col Name of the column whose levels anchor each cluster
#'   (e.g., `"M_STATE"`). Must exist in both `synth` and `original`.
#' @param lat_col,lon_col Column names of the latitude and longitude
#'   fields to overwrite in `synth`.
#' @param anchor_centroids Named list keyed by anchor levels; each
#'   element is a length-2 numeric named `c(lat, lon)`. The user supplies
#'   plausible centroids (e.g., state centroids); the function never
#'   infers them from the original to avoid leaking position
#'   information. Any other shape (a data frame, an unnamed list, an
#'   element that is not a `c(lat, lon)` pair, or a list naming none of
#'   the anchor levels) is refused with a
#'   `masque_bad_anchor_centroids_refusal` error. A level absent from an
#'   otherwise well-formed list is warned about and its rows get `NA`.
#' @param site_spread_deg Half-width of the box (in decimal degrees)
#'   around each anchor centroid within which fake site centroids are
#'   uniformly placed. Default `0.6`.
#' @param jitter_deg Within-site uniform jitter (in decimal degrees)
#'   added to each row's assigned site centroid. Default `0.05`.
#' @param seed Optional integer seed for reproducibility. The function
#'   uses `withr::local_preserve_seed()` so the caller's RNG state is
#'   left untouched.
#'
#' @return `synth`, with `lat_col` and `lon_col` overwritten by the
#'   re-anchored coordinates.
#'
#' @examples
#' \donttest{
#' # Toy example: 50 rows split across two states.
#' set.seed(1)
#' n <- 50
#' df <- data.frame(
#'   state = sample(c("NSW", "VIC"), n, replace = TRUE),
#'   lat   = stats::rnorm(n, -33, 0.3),
#'   lon   = stats::rnorm(n, 145, 0.3),
#'   y     = stats::rnorm(n)
#' )
#' roles <- propose_roles(df, detect = FALSE)
#' roles$role[roles$col == "y"] <- "outcome"
#' roles$role[roles$col %in% c("lat", "lon")] <- "covariate"
#' roles$role[roles$col == "state"] <- "design"
#' m <- mask(df, roles, mode = "collaborate", seed = 1L)
#' centroids <- list(
#'   NSW = c(lat = -32.5, lon = 147),
#'   VIC = c(lat = -36.5, lon = 144)
#' )
#' synth_geo <- synthesise_geospatial(
#'   synthetic(m), df,
#'   anchor_col = "state", lat_col = "lat", lon_col = "lon",
#'   anchor_centroids = centroids, seed = 2L
#' )
#' head(synth_geo[, c("state", "lat", "lon")])
#' }
#'
#' @export
synthesise_geospatial <- function(synth, original,
                                  anchor_col, lat_col, lon_col,
                                  anchor_centroids,
                                  site_spread_deg = 0.6,
                                  jitter_deg = 0.05,
                                  seed = NULL) {
  if (!is.data.frame(synth) || !is.data.frame(original)) {
    cli::cli_abort("`synth` and `original` must both be data frames.")
  }
  for (cn in c(anchor_col, lat_col, lon_col)) {
    if (!cn %in% names(synth) || !cn %in% names(original)) {
      cli::cli_abort(
        "Column {.field {cn}} missing from {.code synth} or {.code original}."
      )
    }
  }
  .check_anchor_centroids(anchor_centroids, synth[[anchor_col]])
  if (nrow(synth) != nrow(original)) {
    cli::cli_abort(c(
      "`synth` and `original` must have the same number of rows.",
      i = "Got nrow(synth) = {nrow(synth)}, nrow(original) = {nrow(original)}.",
      "*" = paste0(
        "`synthesise_geospatial()` preserves the original's NA mask ",
        "cell-by-cell; the two frames must align row-by-row."
      )
    ))
  }

  withr::local_preserve_seed()
  if (!is.null(seed)) set.seed(seed)

  # 1. Per (anchor, site) replication counts in the original.
  has_xy <- !is.na(original[[lat_col]]) & !is.na(original[[lon_col]])
  o <- original[has_xy, c(anchor_col, lat_col, lon_col), drop = FALSE]
  if (nrow(o) > 0L) {
    o$.key <- paste(as.character(o[[anchor_col]]),
      o[[lat_col]], o[[lon_col]],
      sep = "\u0001"
    )
    tab <- table(o$.key)
    keys <- strsplit(names(tab), "\u0001", fixed = TRUE)
    sites <- data.frame(
      anchor = vapply(keys, `[`, character(1L), 1L),
      n = as.integer(tab),
      stringsAsFactors = FALSE
    )
  } else {
    sites <- data.frame(anchor = character(0L), n = integer(0L))
  }
  sites_by_anchor <- split(sites$n, sites$anchor)

  # 2. For each anchor level present in synth, generate fake-site centroids
  # placed uniformly within +/-site_spread_deg of the user-supplied centroid.
  fake_sites <- list()
  synth_anchor <- as.character(synth[[anchor_col]])
  for (a in unique(stats::na.omit(synth_anchor))) {
    if (!a %in% names(anchor_centroids)) {
      cli::cli_warn(c(
        "Anchor level {.val {a}} has no centroid in {.arg anchor_centroids}.",
        i = paste0(
          "Coordinates for {sum(synth_anchor == a, na.rm = TRUE)} ",
          "synthetic row{?s} will be NA."
        )
      ))
      next
    }
    n_sites <- length(sites_by_anchor[[a]] %||% integer(0L))
    if (n_sites == 0L) n_sites <- 1L # fallback
    c_lat <- anchor_centroids[[a]][["lat"]]
    c_lon <- anchor_centroids[[a]][["lon"]]
    fake_sites[[a]] <- data.frame(
      lat = c_lat + stats::runif(n_sites, -site_spread_deg, site_spread_deg),
      lon = c_lon + stats::runif(n_sites, -site_spread_deg, site_spread_deg)
    )
  }

  # 3. Assign each synthetic row to a fake site within its anchor, keeping the
  # original's rows per site, then add a small within-site jitter.
  out_lat <- rep(NA_real_, nrow(synth))
  out_lon <- rep(NA_real_, nrow(synth))
  # NA cells follow the original, since `synth` may already have been filled
  # by an earlier step.
  na_in_original <- is.na(original[[lat_col]]) | is.na(original[[lon_col]])

  for (a in unique(stats::na.omit(synth_anchor))) {
    sa <- fake_sites[[a]]
    if (is.null(sa) || nrow(sa) == 0L) next
    idx <- which(synth_anchor == a & !na_in_original)
    if (length(idx) == 0L) next
    weights <- sites_by_anchor[[a]] %||% rep(1L, nrow(sa))
    if (length(weights) != nrow(sa)) weights <- rep(1L, nrow(sa))
    pick <- sample(seq_len(nrow(sa)),
      size    = length(idx),
      replace = TRUE,
      prob    = weights / sum(weights)
    )
    out_lat[idx] <- sa$lat[pick] +
      stats::runif(length(idx), -jitter_deg, jitter_deg)
    out_lon[idx] <- sa$lon[pick] +
      stats::runif(length(idx), -jitter_deg, jitter_deg)
  }

  synth[[lat_col]] <- out_lat
  synth[[lon_col]] <- out_lon
  synth
}

# A data frame passes `is.list()` with names, so it is refused by name; a
# list naming none of the anchor levels would return every coordinate NA.
.check_anchor_centroids <- function(anchor_centroids, anchor_values) {
  refuse <- function(...) {
    cli::cli_abort(
      c(...,
        i = paste0(
          "Supply a named list, one element per anchor level, each a ",
          "numeric `c(lat = , lon = )`."
        )
      ),
      class = c("masque_bad_anchor_centroids_refusal", "orchestra_refusal")
    )
  }
  if (is.data.frame(anchor_centroids)) {
    refuse(paste0(
      "`anchor_centroids` is a data frame, not a named list of ",
      "`c(lat, lon)` pairs."
    ))
  }
  if (!is.list(anchor_centroids) || is.null(names(anchor_centroids)) ||
    !length(anchor_centroids) || !all(nzchar(names(anchor_centroids)))) {
    refuse("`anchor_centroids` must be a non-empty named list.")
  }
  well_formed <- vapply(anchor_centroids, function(ctr) {
    is.numeric(ctr) && length(ctr) == 2L &&
      all(c("lat", "lon") %in% names(ctr)) && !anyNA(ctr)
  }, logical(1L))
  if (!all(well_formed)) {
    refuse(
      paste0(
        "{sum(!well_formed)} element{?s} of `anchor_centroids` {?is/are} ",
        "not a numeric `c(lat = , lon = )` pair: "
      ),
      x = "{.val {names(anchor_centroids)[!well_formed]}}"
    )
  }
  present <- unique(as.character(stats::na.omit(anchor_values)))
  if (length(present) && !any(present %in% names(anchor_centroids))) {
    refuse(
      "No anchor level of `synth` has a centroid in `anchor_centroids`.",
      x = "Levels in `synth`: {.val {present}}",
      x = "Names supplied: {.val {names(anchor_centroids)}}"
    )
  }
  invisible(TRUE)
}
