# Regression contract for the site-coordinate invariant (0.10.0).
#
# "Within each site unit, every row carries an identical coordinate pair."
#
# Before 0.10.0 jitter_coordinates() displaced every row independently. That
# fabricated within-site variation in every coordinate-joined covariate, made
# coordinate join keys accidentally unique, and -- because donut displacement
# is isotropic -- let the true site be recovered by averaging a site's rows.

.hav_km <- function(lon1, lat1, lon2, lat2) {
  r <- 6371
  dlat <- (lat2 - lat1) * pi / 180
  dlon <- (lon2 - lon1) * pi / 180
  a <- sin(dlat / 2)^2 +
    cos(lat1 * pi / 180) * cos(lat2 * pi / 180) * sin(dlon / 2)^2
  2 * r * asin(pmin(1, sqrt(a)))
}

# n sites x k rows, one true coordinate per site.
.site_fixture <- function(n = 6L, k = 8L) {
  data.frame(
    trial = rep(paste0("T", seq_len(n)), each = k),
    lat   = rep(seq(-36, -33, length.out = n), each = k),
    lon   = rep(seq(139, 147, length.out = n), each = k)
  )
}

test_that("one coordinate per site survives the jitter", {
  df <- .site_fixture(n = 6L, k = 8L)
  out <- jitter_coordinates(df, "lat", "lon", on_land = FALSE, seed = 1)

  expect_equal(nrow(unique(out[c("lat", "lon")])), 6L)
  # Every site is internally identical.
  by_site <- split(out[c("lat", "lon")], df$trial)
  one_pair <- function(s) nrow(unique(s)) == 1L
  expect_true(all(vapply(by_site, one_pair, logical(1))))
  # Sites remain distinct from one another.
  expect_equal(length(unique(paste(out$lat, out$lon))), 6L)
})

test_that("the donut contract still holds, now per site", {
  df <- .site_fixture(n = 8L, k = 12L)
  out <- jitter_coordinates(df, "lat", "lon", method = "donut",
                            min_km = 5, max_km = 20, on_land = FALSE, seed = 2)
  d <- .hav_km(df$lon, df$lat, out$lon, out$lat)
  expect_true(all(d >= 4.8 & d <= 20.3))

  out_g <- jitter_coordinates(df, "lat", "lon", method = "gaussian",
                              sd_km = 10, on_land = FALSE, seed = 2)
  expect_equal(nrow(unique(out_g[c("lat", "lon")])), 8L)
  dg <- .hav_km(df$lon, df$lat, out_g$lon, out_g$lat)
  expect_gt(median(dg), 6)
})

test_that("a site's true position is not recoverable by averaging its rows", {
  # The privacy regression. Per-row jitter left the centroid of a 360-row site
  # a median 0.58 km from the truth, against a 5 km floor.
  n <- 360L
  df <- data.frame(lat = rep(-34.9, n), lon = rep(138.6, n))
  err <- vapply(1:10, function(s) {
    o <- jitter_coordinates(df, "lat", "lon", min_km = 5, max_km = 20,
                            on_land = FALSE, seed = s)
    .hav_km(138.6, -34.9, mean(o$lon), mean(o$lat))
  }, numeric(1))
  expect_true(all(err >= 5))
})

test_that("genuinely point-level data is untouched by the grouping", {
  set.seed(11)
  df <- data.frame(lat = stats::runif(150, -37, -32),
                   lon = stats::runif(150, 139, 149))
  expect_equal(nrow(unique(df)), 150L) # every input pair distinct
  out <- jitter_coordinates(df, "lat", "lon", on_land = FALSE, seed = 5)
  expect_equal(nrow(unique(out[c("lat", "lon")])), 150L)
  d <- .hav_km(df$lon, df$lat, out$lon, out$lat)
  expect_true(all(d >= 4.8 & d <= 20.3))
})

test_that("`by` consolidates a site whose coordinates differ slightly", {
  df <- data.frame(
    trial = rep(c("T1", "T2"), each = 4),
    lat = c(-34.9000, -34.9001, -34.9002, -34.9000, rep(-35.2, 4)),
    lon = c(138.6000, 138.6001, 138.6000, 138.6002, rep(142.0, 4))
  )
  expect_warning(
    out <- jitter_coordinates(df, "lat", "lon", by = "trial",
                              on_land = FALSE, seed = 1),
    class = "masque_geo_consolidated"
  )
  expect_equal(nrow(unique(out[c("lat", "lon")])), 2L)
  expect_equal(length(unique(out$lat[1:4])), 1L)

  # The default grouping would have split that site into four.
  plain <- jitter_coordinates(df, "lat", "lon", on_land = FALSE, seed = 1)
  expect_equal(nrow(unique(plain[c("lat", "lon")])), 5L)
})

test_that("a `by` group wider than the displacement radius is flagged", {
  df <- data.frame(
    trial = rep("T1", 4),
    lat = c(-34.9, -34.9, -35.9, -35.9),
    lon = c(138.6, 138.6, 140.6, 140.6)
  )
  seen <- character()
  withCallingHandlers(
    jitter_coordinates(df, "lat", "lon", by = "trial", on_land = FALSE,
                       seed = 1),
    warning = function(w) {
      seen <<- c(seen, class(w)[1])
      invokeRestart("muffleWarning")
    }
  )
  expect_true("masque_geo_wide_group" %in% seen)
  expect_true("masque_geo_consolidated" %in% seen)
})

test_that("`by = FALSE` reproduces the old per-row draw and says so", {
  df <- .site_fixture(n = 3L, k = 5L)
  expect_warning(
    out <- jitter_coordinates(df, "lat", "lon", by = FALSE,
                              on_land = FALSE, seed = 1),
    class = "masque_geo_ungrouped"
  )
  expect_equal(nrow(unique(out[c("lat", "lon")])), 15L)

  # No warning when there is nothing to split: point-level input.
  set.seed(3)
  pt <- data.frame(lat = stats::runif(20, -36, -33),
                   lon = stats::runif(20, 140, 147))
  expect_no_warning(
    jitter_coordinates(pt, "lat", "lon", by = FALSE, on_land = FALSE, seed = 1)
  )
})

test_that("an unplaceable site fails closed to NA, never to the true value", {
  df <- .site_fixture(n = 3L, k = 4L)
  never <- function(lon, lat) rep(FALSE, length(lon))
  expect_warning(
    out <- jitter_coordinates(df, "lat", "lon", on_land = never,
                              max_tries = 3L, seed = 1),
    class = "masque_geo_unplaced"
  )
  expect_true(all(is.na(out$lat)))
  expect_true(all(is.na(out$lon)))
  # Explicitly: the true coordinate is gone, not merely displaced.
  expect_false(any(out$lat %in% df$lat, na.rm = TRUE))

  # A site the test admits is still placed normally.
  half <- function(lon, lat) lat < -34.5
  out2 <- suppressWarnings(
    jitter_coordinates(df, "lat", "lon", on_land = half,
                       max_tries = 50L, seed = 2)
  )
  expect_true(any(!is.na(out2$lat)))
})

test_that("NA coordinate rows stay NA and never enter a site centroid", {
  df <- data.frame(
    trial = rep(c("T1", "T2"), each = 3),
    lat = c(-34.9, NA, -34.9, -35.2, -35.2, -35.2),
    lon = c(138.6, 138.6, NA, 142.0, 142.0, 142.0)
  )
  out <- jitter_coordinates(df, "lat", "lon", by = "trial",
                            on_land = FALSE, seed = 1)
  expect_true(all(is.na(out$lat[2:3])))
  expect_true(all(is.na(out$lon[2:3])))
  # T1's single valid row still gets a coordinate, and T2 stays internally one.
  expect_false(is.na(out$lat[1]))
  expect_equal(length(unique(out$lat[4:6])), 1L)
})

test_that("`by` rejects a non-grouping", {
  df <- .site_fixture(n = 2L, k = 2L)
  expect_error(
    jitter_coordinates(df, "lat", "lon", by = TRUE, on_land = FALSE),
    "not a grouping"
  )
  expect_error(
    jitter_coordinates(df, "lat", "lon", by = "nope", on_land = FALSE),
    "not found"
  )
  expect_error(
    jitter_coordinates(df, "lat", "lon", by = 1L, on_land = FALSE),
    "must be"
  )
})

# ---- the invariant through mask() -------------------------------------------

.masked_sites <- function(df, coords, ...) {
  roles <- suppressWarnings(propose_roles(df, detect = FALSE))
  m <- suppressWarnings(mask(df, roles, seed = 1, coords = coords, ...))
  synthetic(m)
}

test_that("mask(coords=) inherits the site invariant by default", {
  df <- .site_fixture(n = 5L, k = 6L)
  df$y <- stats::rnorm(30)
  syn <- .masked_sites(
    df, list(list(lat = "lat", lon = "lon", on_land = FALSE))
  )
  expect_equal(nrow(unique(as.data.frame(syn[c("lat", "lon")]))), 5L)
  by_site <- split(as.data.frame(syn[c("lat", "lon")]), df$trial)
  one_pair <- function(s) nrow(unique(s)) == 1L
  expect_true(all(vapply(by_site, one_pair, logical(1))))
})

test_that("mask(coords=) accepts `by` and groups on the original table", {
  df <- data.frame(
    trial = rep(c("T1", "T2", "T3"), each = 4),
    lat = c(rep(-34.9, 3), -34.9001, rep(-35.2, 4), rep(-33.6, 4)),
    lon = c(rep(138.6, 3), 138.6001, rep(142.0, 4), rep(148.2, 4)),
    y = stats::rnorm(12)
  )
  roles <- suppressWarnings(propose_roles(df, mode = "collaborate"))
  # `trial` is aliased in the synthetic; the grouping must still hold, because
  # it is taken from the original table rather than the masked one.
  m <- suppressWarnings(mask(df, roles, mode = "collaborate", seed = 1,
    coords = list(list(lat = "lat", lon = "lon", by = "trial",
                       on_land = FALSE))))
  syn <- synthetic(m)
  expect_equal(nrow(unique(as.data.frame(syn[c("lat", "lon")]))), 3L)
  expect_equal(length(unique(syn$lat[1:4])), 1L)

  rec <- recipe(m)
  expect_length(rec@coords, 1L)
  expect_equal(rec@coords[[1]]$grouping, "column")
  expect_equal(rec@coords[[1]]$by, "trial")
  expect_equal(rec@coords[[1]]$n_sites, 3L)
  expect_equal(length(rec@coords[[1]]$consolidated), 1L)
  expect_true(any(grepl("grouped by trial", rec@warnings)))
})

test_that("two declared coordinate pairs are displaced independently", {
  # Before 0.10.0 every spec was handed the same seed, so two pairs in one
  # table received identical displacement vectors.
  df <- data.frame(
    a_lat = rep(-34.9, 6), a_lon = rep(138.6, 6),
    b_lat = rep(-34.9, 6), b_lon = rep(138.6, 6),
    y = stats::rnorm(6)
  )
  syn <- .masked_sites(df, list(
    list(lat = "a_lat", lon = "a_lon", on_land = FALSE),
    list(lat = "b_lat", lon = "b_lon", on_land = FALSE)
  ))
  expect_false(isTRUE(all.equal(syn$a_lat[1], syn$b_lat[1])))
  expect_false(isTRUE(all.equal(syn$a_lon[1], syn$b_lon[1])))
})

test_that("mask(coords=) rejects a grouping column not in the original", {
  df <- data.frame(lat = c(-34.9, -35.2), lon = c(138.6, 142.0), y = c(1, 2))
  roles <- suppressWarnings(propose_roles(df, detect = FALSE))
  expect_error(
    suppressWarnings(mask(df, roles, coords = list(
      list(lat = "lat", lon = "lon", by = "nope")))),
    "not found"
  )
})

test_that("a pre-0.10.0 recipe reads back with no coordinate record", {
  df <- .site_fixture(n = 2L, k = 3L)
  df$y <- stats::rnorm(6)
  roles <- suppressWarnings(propose_roles(df, detect = FALSE))
  m <- suppressWarnings(mask(df, roles, seed = 1))
  rec <- recipe(m)
  attr(rec, "coords") <- NULL # as an older recipe deserialises
  expect_length(rec@coords, 0L)
  expect_no_error(suppressMessages(utils::capture.output(print(rec))))
})
