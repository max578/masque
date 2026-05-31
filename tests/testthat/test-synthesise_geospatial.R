# Tests for synthesise_geospatial(): preserve site-count per anchor,
# preserve NA pattern, never read real coords.

.toy_df <- function(seed = 1L) {
  set.seed(seed)
  # NSW: 3 distinct sites; VIC: 2 distinct sites; replication 10 each.
  nsw <- expand.grid(site = 1:3, plot = 1:10)
  nsw$state <- "NSW"
  nsw$lat <- -33 + nsw$site * 0.4 # well-separated real positions
  nsw$lon <- 147 + nsw$site * 0.4
  vic <- expand.grid(site = 1:2, plot = 1:10)
  vic$state <- "VIC"
  vic$lat <- -37 + vic$site * 0.5
  vic$lon <- 144 + vic$site * 0.5
  df <- rbind(nsw, vic)
  df$y <- rnorm(nrow(df))
  df$site <- NULL
  df$plot <- NULL
  df[sample(nrow(df)), ]
}

.centroids <- list(
  NSW = c(lat = -32.5, lon = 147),
  VIC = c(lat = -36.5, lon = 144)
)

test_that("synthesise_geospatial errors on missing columns", {
  df <- .toy_df()
  expect_error(
    synthesise_geospatial(df, df,
      anchor_col = "missing",
      lat_col = "lat", lon_col = "lon",
      anchor_centroids = .centroids
    ),
    "missing"
  )
})

test_that("synthesise_geospatial errors on non-data-frame input", {
  expect_error(
    synthesise_geospatial(1:10, 1:10, "state", "lat", "lon",
      anchor_centroids = .centroids
    ),
    "data frames"
  )
})

test_that("synthesise_geospatial errors on unnamed anchor_centroids", {
  df <- .toy_df()
  expect_error(
    synthesise_geospatial(df, df, "state", "lat", "lon",
      anchor_centroids = list(c(lat = -32, lon = 147))
    ),
    "named list"
  )
})

test_that("output shape matches input shape", {
  df <- .toy_df()
  out <- synthesise_geospatial(df, df, "state", "lat", "lon",
    anchor_centroids = .centroids, seed = 1L
  )
  expect_equal(nrow(out), nrow(df))
  expect_equal(ncol(out), ncol(df))
  expect_named(out, names(df))
})

test_that("synthetic coordinates sit inside the expected per-anchor box", {
  df <- .toy_df()
  out <- synthesise_geospatial(df, df, "state", "lat", "lon",
    anchor_centroids = .centroids,
    site_spread_deg = 0.6, jitter_deg = 0.05,
    seed = 1L
  )
  for (a in names(.centroids)) {
    idx <- which(out$state == a)
    cent <- .centroids[[a]]
    expect_true(all(abs(out$lat[idx] - cent[["lat"]]) <= 0.6 + 0.05 + 1e-9))
    expect_true(all(abs(out$lon[idx] - cent[["lon"]]) <= 0.6 + 0.05 + 1e-9))
  }
})

test_that("number of distinct synthetic sites per anchor matches original", {
  df <- .toy_df()
  # Zero jitter -> distinct site centroids land on exactly distinct
  # (lat, lon) pairs, so `unique()` is a faithful count.
  out <- synthesise_geospatial(df, df, "state", "lat", "lon",
    anchor_centroids = .centroids,
    site_spread_deg = 0.6, jitter_deg = 0,
    seed = 1L
  )
  recover_sites <- function(sub) nrow(unique(sub[, c("lat", "lon")]))
  expect_equal(recover_sites(out[out$state == "NSW", ]), 3L)
  expect_equal(recover_sites(out[out$state == "VIC", ]), 2L)
})

test_that("NA pattern in coordinates is preserved", {
  df <- .toy_df()
  df$lat[1:5] <- NA
  df$lon[1:5] <- NA
  out <- synthesise_geospatial(df, df, "state", "lat", "lon",
    anchor_centroids = .centroids, seed = 1L
  )
  expect_true(all(is.na(out$lat[1:5])))
  expect_true(all(is.na(out$lon[1:5])))
  expect_false(any(is.na(out$lat[-c(1:5)])))
})

test_that("anchor levels missing from anchor_centroids produce NA + warning", {
  df <- .toy_df()
  partial <- list(NSW = c(lat = -32.5, lon = 147)) # VIC missing
  expect_warning(
    out <- synthesise_geospatial(df, df, "state", "lat", "lon",
      anchor_centroids = partial, seed = 1L
    ),
    "VIC"
  )
  expect_true(all(is.na(out$lat[out$state == "VIC"])))
})

test_that("caller's RNG state is not mutated", {
  df <- .toy_df()
  set.seed(99)
  before <- .Random.seed
  invisible(synthesise_geospatial(df, df, "state", "lat", "lon",
    anchor_centroids = .centroids, seed = 1L
  ))
  after <- .Random.seed
  expect_identical(before, after)
})

test_that("seed gives reproducible output", {
  df <- .toy_df()
  o1 <- synthesise_geospatial(df, df, "state", "lat", "lon",
    anchor_centroids = .centroids, seed = 1L
  )
  o2 <- synthesise_geospatial(df, df, "state", "lat", "lon",
    anchor_centroids = .centroids, seed = 1L
  )
  expect_equal(o1$lat, o2$lat)
  expect_equal(o1$lon, o2$lon)
})

# v0.4.1: NA-mask authority is the *original*, not the *synth* (CODEX
# finding 6). Constructs a case where synth has full coords but original
# has missing ones, and asserts the output preserves the original's NAs.

test_that("synthesise_geospatial uses original's NA mask, not synth's", {
  df <- .toy_df()
  # synth has full coordinates, original has NAs in rows 1:5
  synth_full <- df
  orig_with_na <- df
  orig_with_na$lat[1:5] <- NA
  orig_with_na$lon[1:5] <- NA

  out <- synthesise_geospatial(
    synth_full, orig_with_na,
    "state", "lat", "lon",
    anchor_centroids = .centroids, seed = 1L
  )

  # Rows missing in the original must remain NA in the output, even
  # though synth_full had full coordinates for them.
  expect_true(all(is.na(out$lat[1:5])))
  expect_true(all(is.na(out$lon[1:5])))
  expect_false(any(is.na(out$lat[-c(1:5)])))
})

test_that("synthesise_geospatial errors on row-count mismatch", {
  df <- .toy_df()
  expect_error(
    synthesise_geospatial(df[1:10, ], df, "state", "lat", "lon",
      anchor_centroids = .centroids
    ),
    "same number of rows"
  )
})
