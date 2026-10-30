# The documented `coords` forms (F5) and the reviewed plan holding against a
# coordinate declaration (N3).

# Four sites, ten rows each, one true coordinate per site.
.fx_sites <- function() {
  set.seed(5)
  sites <- data.frame(
    site = sprintf("S%d", 1:4),
    lat = c(-34.9285, -33.8688, -37.8136, -27.4698),
    lon = c(138.6007, 151.2093, 144.9631, 153.0251),
    stringsAsFactors = FALSE
  )
  df <- sites[rep(1:4, each = 10), ]
  rownames(df) <- NULL
  df$genotype <- rep(sprintf("G%02d", 1:10), 4)
  df$yield <- round(stats::rnorm(40, 3, 0.5), 2)
  df
}

.fx_site_roles <- function(df, coord_action = "keep") {
  r <- suppressWarnings(propose_roles(df, mode = "local", detect = FALSE))
  r <- set_role(r, "site", role = "design", action = "keep")
  r <- set_role(r, "genotype", role = "treatment", action = "keep")
  r <- set_role(r, "yield", role = "outcome", action = "scramble")
  if (!is.null(coord_action)) {
    r <- set_role(r, c("lat", "lon"), action = coord_action)
  }
  r
}

.fx_one_displacement_per_site <- function(df, syn) {
  per_site <- tapply(paste(syn$lat, syn$lon), df$site, function(v) {
    length(unique(v))
  })
  moved <- tapply(syn$lat != df$lat | syn$lon != df$lon, df$site, all)
  all(per_site == 1L) && all(moved) &&
    length(unique(paste(syn$lat, syn$lon))) == 4L
}

# ---- F5: every documented form of `coords` ---------------------------------

test_that("each documented coords form gives one displacement per site", {
  df <- .fx_sites()
  roles <- .fx_site_roles(df)
  forms <- list(
    vector = c(lat = "lat", lon = "lon", on_land = FALSE),
    wrapped = list(list(lat = "lat", lon = "lon", on_land = FALSE)),
    bare = list(lat = "lat", lon = "lon", on_land = FALSE),
    bare_params = list(
      lat = "lat", lon = "lon", min_km = 1, max_km = 3, on_land = FALSE
    )
  )
  for (nm in names(forms)) {
    m <- suppressWarnings(
      mask(df, roles, mode = "local", seed = 1, coords = forms[[nm]])
    )
    syn <- synthetic(m)
    expect_true(.fx_one_displacement_per_site(df, syn), label = nm)
    rec <- recipe(m)
    expect_length(rec@coords, 1L)
    expect_identical(rec@coords[[1]]$n_sites, 4L)
  }
})

test_that("the bare list form honours its jitter parameters", {
  df <- .fx_sites()
  m <- suppressWarnings(mask(
    df, .fx_site_roles(df), mode = "local", seed = 1,
    coords = list(lat = "lat", lon = "lon", min_km = 1, max_km = 3,
                  on_land = FALSE)
  ))
  rec <- recipe(m)@coords[[1]]
  expect_identical(rec$min_km, 1)
  expect_identical(rec$max_km, 3)
  syn <- synthetic(m)
  r <- 6371
  dlat <- (syn$lat - df$lat) * pi / 180
  dlon <- (syn$lon - df$lon) * pi / 180
  a <- sin(dlat / 2)^2 +
    cos(df$lat * pi / 180) * cos(syn$lat * pi / 180) * sin(dlon / 2)^2
  d <- 2 * r * asin(pmin(1, sqrt(a)))
  expect_true(all(d >= 0.9 & d <= 3.1))
})

# ---- N3: a declaration never overrides a reviewed action -------------------

test_that("an explicit drop or scramble on a declared coordinate is refused", {
  df <- .fx_sites()
  for (act in c("drop", "scramble")) {
    roles <- .fx_site_roles(df, coord_action = act)
    expect_error(
      suppressWarnings(mask(
        df, roles, mode = "local", seed = 1,
        coords = list(list(lat = "lat", lon = "lon", on_land = FALSE))
      )),
      class = "masque_coords_action_refusal"
    )
  }
})

test_that("a direct edit away from the proposal is also explicit", {
  df <- .fx_sites()
  roles <- .fx_site_roles(df, coord_action = NULL)
  roles$action[roles$col == "lat"] <- "scramble"
  err <- tryCatch(
    suppressWarnings(mask(
      df, roles, mode = "local", seed = 1,
      coords = list(list(lat = "lat", lon = "lon", on_land = FALSE))
    )),
    masque_coords_action_refusal = function(e) e
  )
  expect_s3_class(err, "orchestra_refusal")
  expect_match(conditionMessage(err), "lat")
  expect_match(conditionMessage(err), "keep")
})

test_that("the proposed default yields to the declaration and says so", {
  df <- .fx_sites()
  roles <- .fx_site_roles(df, coord_action = NULL)
  # propose_roles() proposes drop for a coordinate-named column.
  expect_true(all(roles$action[roles$col %in% c("lat", "lon")] != "keep"))
  m <- suppressWarnings(mask(
    df, roles, mode = "local", seed = 1,
    coords = list(list(lat = "lat", lon = "lon", on_land = FALSE))
  ))
  rec <- recipe(m)
  expect_identical(rec@roles$action[rec@roles$col %in% c("lat", "lon")],
                   c("keep", "keep"))
  expect_true(any(grepl("set to keep for the geomask", rec@warnings)))
  expect_true(.fx_one_displacement_per_site(df, synthetic(m)))
})

test_that("an explicit keep needs no note", {
  df <- .fx_sites()
  m <- suppressWarnings(mask(
    df, .fx_site_roles(df, coord_action = "keep"), mode = "local", seed = 1,
    coords = list(list(lat = "lat", lon = "lon", on_land = FALSE))
  ))
  expect_false(any(grepl("for the geomask", recipe(m)@warnings)))
})

test_that("a roles table without provenance cannot override a declaration", {
  df <- .fx_sites()
  roles <- .fx_site_roles(df, coord_action = NULL)
  attr(roles, "proposed_actions") <- NULL
  expect_error(
    suppressWarnings(mask(
      df, roles, mode = "local", seed = 1,
      coords = list(list(lat = "lat", lon = "lon", on_land = FALSE))
    )),
    class = "masque_coords_action_refusal"
  )
})
