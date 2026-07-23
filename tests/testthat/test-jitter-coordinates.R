# Regression contract for jitter_coordinates() (donut / gaussian geomasking).

.hav_km <- function(lon1, lat1, lon2, lat2) {
  r <- 6371
  dlat <- (lat2 - lat1) * pi / 180
  dlon <- (lon2 - lon1) * pi / 180
  a <- sin(dlat / 2)^2 +
    cos(lat1 * pi / 180) * cos(lat2 * pi / 180) * sin(dlon / 2)^2
  2 * r * asin(pmin(1, sqrt(a)))
}

test_that("donut jitter keeps every point within [min_km, max_km]", {
  set.seed(1)
  df <- data.frame(lat = stats::runif(300, -37, -30),
                   lon = stats::runif(300, 140, 149))
  out <- jitter_coordinates(df, "lat", "lon", method = "donut",
                            min_km = 5, max_km = 20, on_land = FALSE, seed = 1)
  d <- .hav_km(df$lon, df$lat, out$lon, out$lat)
  expect_true(all(d >= 4.8 & d <= 20.3)) # tolerance for 5-dp rounding
  expect_gt(median(d), 10)               # area-uniform annulus -> ~14 km mean
})

test_that("gaussian jitter is centred near sd_km with a heavier tail", {
  set.seed(2)
  df <- data.frame(lat = stats::runif(400, -37, -30),
                   lon = stats::runif(400, 140, 149))
  out <- jitter_coordinates(df, "lat", "lon", method = "gaussian",
                            sd_km = 10, on_land = FALSE, seed = 2)
  d <- .hav_km(df$lon, df$lat, out$lon, out$lat)
  expect_gt(median(d), 6)
  expect_lt(median(d), 16)
  expect_gt(max(d), 20) # unbounded tail, unlike the donut
})

test_that("NA coordinates stay NA and the two axes stay paired", {
  df <- data.frame(lat = c(-34, NA, -33, -35),
                   lon = c(138, 140, NA, 145))
  out <- jitter_coordinates(df, "lat", "lon", on_land = FALSE, seed = 1)
  expect_true(is.na(out$lat[2]) && is.na(out$lon[2])) # lat NA -> both NA
  expect_true(is.na(out$lat[3]) && is.na(out$lon[3])) # lon NA -> both NA
  expect_false(is.na(out$lat[1]))
  expect_false(is.na(out$lat[4]))
})

test_that("seed makes the jitter reproducible and preserves caller RNG", {
  df <- data.frame(lat = stats::runif(20, -36, -31),
                   lon = stats::runif(20, 141, 148))
  set.seed(99)
  before <- stats::runif(1)
  a <- jitter_coordinates(df, "lat", "lon", on_land = FALSE, seed = 7)
  b <- jitter_coordinates(df, "lat", "lon", on_land = FALSE, seed = 7)
  expect_identical(a, b)
  set.seed(99)
  expect_equal(before, stats::runif(1)) # local_preserve_seed
})

test_that("the on-land constraint keeps coastal points on land", {
  skip_if_not_installed("maps")
  df <- data.frame(lat = c(-34.9, -35.0, -34.6),
                   lon = c(138.5, 137.8, 135.9)) # South Australian coast
  out <- jitter_coordinates(df, "lat", "lon", min_km = 5, max_km = 20,
                            on_land = TRUE, seed = 1)
  expect_true(all(!is.na(maps::map.where("world", out$lon, out$lat))))
  expect_false(isTRUE(all.equal(df$lat, out$lat)))
})

test_that("invalid input is rejected", {
  df <- data.frame(lat = -34, lon = 138)
  expect_error(jitter_coordinates(df, "nope", "lon"), "not found")
  expect_error(jitter_coordinates(df, "lat", "lon", min_km = 20, max_km = 5),
               "min_km")
  df2 <- data.frame(lat = "x", lon = 138)
  expect_error(jitter_coordinates(df2, "lat", "lon"), "numeric")
})

test_that("mask(coords=) coarsens a declared pair on land and records it", {
  skip_if_not_installed("maps")
  set.seed(1)
  lon <- stats::runif(400, 139, 148)
  lat <- stats::runif(400, -36, -33)
  onl <- !is.na(maps::map.where("world", lon, lat))
  lon <- lon[onl][1:60]
  lat <- lat[onl][1:60]
  df <- data.frame(
    site  = factor(sample(c("A", "B", "C"), 60, TRUE)),
    gps_s = lat, gps_e = lon,
    yield = stats::rnorm(60)
  )
  df$gps_s[1] <- NA
  df$gps_e[1] <- NA
  roles <- suppressWarnings(propose_roles(df, mode = "collaborate"))
  m <- suppressWarnings(mask(df, roles, mode = "collaborate", seed = 1,
                             coords = list(c(lat = "gps_s", lon = "gps_e"))))
  syn <- synthetic(m)
  ok <- !is.na(df$gps_s) & !is.na(syn$gps_s)
  expect_false(isTRUE(all.equal(df$gps_s[ok], syn$gps_s[ok])))   # coarsened
  expect_true(all(!is.na(maps::map.where("world", syn$gps_e[ok], syn$gps_s[ok]))))
  d <- .hav_km(df$gps_e[ok], df$gps_s[ok], syn$gps_e[ok], syn$gps_s[ok])
  expect_true(all(d >= 4.8 & d <= 20.3))                          # within donut band
  expect_true(is.na(syn$gps_s[1]) && is.na(syn$gps_e[1]))         # NA stays NA, paired
  expect_true(any(grepl("coarsened", recipe(m)@warnings)))        # recorded
})

test_that("mask(coords=) validates the declared columns", {
  df <- data.frame(gps_s = c(-34, -35), gps_e = c(138, 140), y = c(1, 2))
  roles <- suppressWarnings(propose_roles(df, detect = FALSE))
  expect_error(
    suppressWarnings(mask(df, roles, coords = list(c(lat = "nope", lon = "gps_e")))),
    "not found"
  )
})

test_that("coords accepts the c() form with numeric params (string-coerced)", {
  skip_if_not_installed("maps")
  set.seed(3)
  lon <- stats::runif(300, 139, 148)
  lat <- stats::runif(300, -36, -33)
  onl <- !is.na(maps::map.where("world", lon, lat))
  df <- data.frame(gps_s = lat[onl][1:40], gps_e = lon[onl][1:40],
                   y = stats::rnorm(40))
  roles <- suppressWarnings(propose_roles(df, detect = FALSE))
  # c() coerces 10 / 18 to "10" / "18"; the coarsening must still honour them
  m <- suppressWarnings(mask(df, roles, seed = 1, mode = "local",
    coords = list(c(lat = "gps_s", lon = "gps_e", min_km = 10, max_km = 18))))
  syn <- synthetic(m)
  d <- .hav_km(df$gps_e, df$gps_s, syn$gps_e, syn$gps_s)
  expect_true(all(d >= 9.8 & d <= 18.3))
})
