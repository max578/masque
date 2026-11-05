# A site's displacement is a function of the seed and the site's value, never
# of where its rows sit in the table.

.fx_sites <- function(n_sites = 60L, each = 4L) {
  lat <- -37 + (seq_len(n_sites) * 0.0773) %% 5
  lon <- 139 + (seq_len(n_sites) * 0.1319) %% 10
  data.frame(
    site = rep(sprintf("S%03d", seq_len(n_sites)), each = each),
    lat = rep(lat, each = each),
    lon = rep(lon, each = each),
    stringsAsFactors = FALSE
  )
}

.fx_moved <- function(df, out, sites = unique(df$site)) {
  i <- match(sites, df$site)
  cbind(dlat = out$lat[i] - df$lat[i], dlon = out$lon[i] - df$lon[i])
}

test_that("shuffled rows keep every site's displacement", {
  df <- .fx_sites()
  a <- jitter_coordinates(df, "lat", "lon", on_land = FALSE, seed = 42L)
  shuffled <- df[withr::with_seed(9L, sample.int(nrow(df))), ]
  b <- jitter_coordinates(shuffled, "lat", "lon", on_land = FALSE, seed = 42L)
  expect_identical(.fx_moved(df, a), .fx_moved(shuffled, b, unique(df$site)))
})

test_that("an added or removed site leaves the other sites alone", {
  df <- .fx_sites()
  a <- jitter_coordinates(df, "lat", "lon", on_land = FALSE, seed = 42L)

  extra <- data.frame(site = "NEW", lat = -30, lon = 150)
  more <- rbind(extra, df)
  b <- jitter_coordinates(more, "lat", "lon", on_land = FALSE, seed = 42L)
  expect_identical(.fx_moved(df, a), .fx_moved(more, b, unique(df$site)))

  fewer <- df[df$site != "S001", ]
  d <- jitter_coordinates(fewer, "lat", "lon", on_land = FALSE, seed = 42L)
  kept <- unique(fewer$site)
  expect_identical(.fx_moved(df, a, kept), .fx_moved(fewer, d, kept))
})

test_that("a named site unit is keyed on its value, not its position", {
  df <- .fx_sites()
  a <- jitter_coordinates(
    df, "lat", "lon", by = "site", on_land = FALSE, seed = 42L
  )
  shuffled <- rbind(data.frame(site = "NEW", lat = -30, lon = 150),
                    df[rev(seq_len(nrow(df))), ])
  b <- jitter_coordinates(
    shuffled, "lat", "lon", by = "site", on_land = FALSE, seed = 42L
  )
  expect_identical(.fx_moved(df, a), .fx_moved(shuffled, b, unique(df$site)))
})

test_that("mask() keeps the displacement across a shuffled or extended table", {
  df <- .fx_sites()
  df$y <- withr::with_seed(1L, stats::rnorm(nrow(df)))
  roles <- propose_roles(df, detect = FALSE)
  roles$role[roles$col == "site"] <- "design"
  roles$action[roles$col == "site"] <- "keep"
  roles$role[roles$col == "y"] <- "outcome"
  roles$action[roles$col == "y"] <- "scramble"
  roles$role[roles$col %in% c("lat", "lon")] <- "covariate"
  roles$action[roles$col %in% c("lat", "lon")] <- "keep"
  spec <- list(list(lat = "lat", lon = "lon", on_land = FALSE))
  run <- function(d) {
    synthetic(suppressWarnings(mask(d, roles, seed = 42L, coords = spec)))
  }
  a <- run(df)
  sh <- df[withr::with_seed(3L, sample.int(nrow(df))), ]
  b <- run(sh)
  more <- rbind(df, transform(df[1L, ], site = "NEW", lat = -30, lon = 150))
  d <- run(more)
  sites <- unique(df$site)
  expect_identical(.fx_moved(df, a), .fx_moved(sh, b, sites))
  expect_identical(.fx_moved(df, a), .fx_moved(more, d, sites))
})

test_that("kept rebuilds under one seed add nothing to average", {
  df <- .fx_sites()
  a <- jitter_coordinates(df, "lat", "lon", on_land = FALSE, seed = 42L)
  rebuilds <- lapply(1:8, function(s) {
    d <- df[withr::with_seed(s, sample.int(nrow(df))), ]
    o <- jitter_coordinates(d, "lat", "lon", on_land = FALSE, seed = 42L)
    .fx_moved(d, o, unique(df$site))
  })
  for (r in rebuilds) expect_identical(r, .fx_moved(df, a))
})

test_that("the group mean over many seeds sits on the site, with the floor", {
  # The same site under many fresh seeds; its rows share one displacement.
  df <- data.frame(lat = rep(-34.9, 8L), lon = rep(138.6, 8L))
  seeds <- 1:4000
  moved <- t(vapply(seeds, function(s) {
    o <- jitter_coordinates(df, "lat", "lon", on_land = FALSE, seed = s)
    if (nrow(unique(o)) != 1L) stop("a site split apart")
    c(o$lat[1L] - df$lat[1L], o$lon[1L] - df$lon[1L])
  }, numeric(2)))
  north <- moved[, 1L] * 111.32
  east <- moved[, 2L] * 111.32 * cos(-34.9 * pi / 180)
  r <- sqrt(north^2 + east^2)
  # The per-axis SD of the 5-20 km donut is sqrt((R^2 + r^2) / 4) = 10.31 km.
  mcse <- 10.31 / sqrt(length(seeds))
  expect_lt(abs(mean(north)), 3.5 * mcse)
  expect_lt(abs(mean(east)), 3.5 * mcse)
  expect_gte(min(r), 5 - 0.01)
  expect_lte(max(r), 20 + 0.01)
  # Area-uniform radius and uniform bearing, by Kolmogorov-Smirnov.
  u_r <- (r^2 - 25) / (400 - 25)
  expect_gt(stats::ks.test(pmin(pmax(u_r, 0), 1), "punif")$p.value, 0.001)
  u_b <- (atan2(east, north) + pi) / (2 * pi)
  expect_gt(stats::ks.test(u_b, "punif")$p.value, 0.001)
})

test_that("sites are displaced independently within a table", {
  df <- .fx_sites(2000L, 1L)
  df <- unique(df)
  out <- jitter_coordinates(df, "lat", "lon", on_land = FALSE, seed = 7L)
  m <- .fx_moved(df, out)
  expect_lt(abs(stats::cor(m[-1L, "dlat"], m[-nrow(m), "dlat"])), 0.1)
  expect_lt(abs(stats::cor(m[, "dlat"], m[, "dlon"])), 0.1)
})

test_that("the gaussian scheme is keyed the same way and has the right SD", {
  df <- .fx_sites(3000L, 1L)
  run <- function(d) {
    jitter_coordinates(d, "lat", "lon", method = "gaussian", sd_km = 10,
                       on_land = FALSE, seed = 5L)
  }
  a <- run(df)
  sh <- df[rev(seq_len(nrow(df))), ]
  expect_identical(.fx_moved(df, a), .fx_moved(sh, run(sh), unique(df$site)))
  expect_lt(abs(stats::sd(.fx_moved(df, a)[, "dlat"]) * 111.32 - 10), 0.8)
})

test_that("a land test re-draws from the site's own sequence", {
  df <- .fx_sites()
  # Reject everything west of 145 E, whatever the row order.
  land <- function(lon, lat) lon > 145
  a <- suppressWarnings(jitter_coordinates(
    df, "lat", "lon", on_land = land, seed = 42L, max_tries = 40L
  ))
  sh <- df[rev(seq_len(nrow(df))), ]
  b <- suppressWarnings(jitter_coordinates(
    sh, "lat", "lon", on_land = land, seed = 42L, max_tries = 40L
  ))
  expect_identical(.fx_moved(df, a), .fx_moved(sh, b, unique(df$site)))
})

test_that("two coordinate pairs at one place draw differently", {
  df <- data.frame(a_lat = -34.9, a_lon = 138.6, b_lat = -34.9, b_lon = 138.6)
  o <- jitter_coordinates(df, "a_lat", "a_lon", on_land = FALSE, seed = 1L)
  o <- jitter_coordinates(o, "b_lat", "b_lon", on_land = FALSE, seed = 1L)
  expect_false(identical(o$a_lat, o$b_lat))
})

test_that("draws do not depend on the caller's RNG kind or state", {
  df <- .fx_sites()
  a <- jitter_coordinates(df, "lat", "lon", on_land = FALSE, seed = 42L)
  withr::local_seed(3L, .rng_kind = "L'Ecuyer-CMRG")
  before <- .Random.seed
  b <- jitter_coordinates(df, "lat", "lon", on_land = FALSE, seed = 42L)
  expect_identical(a, b)
  expect_identical(before, .Random.seed)
})

test_that("a CSV round trip of computed coordinates keeps the draw", {
  n <- 50L
  set.seed(31L)
  df <- data.frame(lat = stats::runif(n, -38, -33), lon = stats::runif(n, 139, 149))
  a <- jitter_coordinates(df, "lat", "lon", on_land = FALSE, seed = 4L)
  f <- withr::local_tempfile(fileext = ".csv")
  utils::write.csv(df, f, row.names = FALSE)
  back <- utils::read.csv(f)
  b <- jitter_coordinates(back, "lat", "lon", on_land = FALSE, seed = 4L)
  expect_lt(max(abs((a$lat - df$lat) - (b$lat - back$lat))), 2e-5)
  expect_lt(max(abs((a$lon - df$lon) - (b$lon - back$lon))), 2e-5)
})
