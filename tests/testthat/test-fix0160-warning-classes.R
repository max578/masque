# Every package warning carries a masque_ class.

test_that("a roles table without an action column warns by class", {
  df <- data.frame(blk = rep(1:2, 5), y = stats::rnorm(10))
  roles <- data.frame(
    col = c("blk", "y"), role = c("design", "outcome"),
    kind = c("integer", "numeric"), stringsAsFactors = FALSE
  )
  expect_warning(
    roles_validate(roles, df, mode = "local"),
    class = "masque_roles_upgraded"
  )
})

test_that("a hand-built roles table used in the other mode warns by class", {
  df <- data.frame(blk = rep(1:2, 5), y = stats::rnorm(10))
  r <- propose_roles(df, mode = "local", detect = FALSE)
  attr(r, "proposed_actions") <- NULL
  expect_warning(
    masque:::.reresolve_for_mode(r, "collaborate"),
    class = "masque_roles_mode_mismatch"
  )
})

test_that("an anchor level without a centroid warns by class", {
  df <- data.frame(
    state = rep(c("NSW", "VIC"), each = 5),
    lat = c(rep(-33, 5), rep(-37, 5)), lon = c(rep(147, 5), rep(144, 5))
  )
  expect_warning(
    synthesise_geospatial(df, df,
      anchor_col = "state", lat_col = "lat", lon_col = "lon",
      anchor_centroids = list(NSW = c(lat = -32.5, lon = 147)), seed = 1L
    ),
    class = "masque_geo_anchor_missing"
  )
})

test_that("a design plot panel that cannot be drawn warns by class", {
  df <- data.frame(
    trt = rep(c("a", "b"), 6), y = stats::rnorm(12),
    stringsAsFactors = FALSE
  )
  ds <- suppressWarnings(detect_design(df))
  ds@spatial_cols <- character()
  expect_warning(
    masque:::.plot_spatial(ds, df, "base"),
    class = "masque_plot_skipped"
  )
  ds@treatment_col <- NA_character_
  expect_warning(
    masque:::.plot_replication_tile(ds, df, "base"),
    class = "masque_plot_skipped"
  )
  ds@treatment_col <- "trt"
  ds@block_cols <- character()
  expect_warning(
    masque:::.plot_replication_tile(ds, df, "base"),
    class = "masque_plot_skipped"
  )
})
