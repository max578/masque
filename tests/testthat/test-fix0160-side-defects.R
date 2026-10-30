.link_tables <- function() {
  sites <- sprintf("Site%02d", 1:12)
  plots <- data.frame(
    site = rep(sites, each = 4L), rep = rep(1:4, 12L),
    yield = round(seq(3, 6, length.out = 48L), 2), stringsAsFactors = FALSE
  )
  meta <- data.frame(
    site = sites, elev = seq(100, 650, by = 50), stringsAsFactors = FALSE
  )
  list(plots = plots, meta = meta)
}

.link_roles <- function(tables) {
  rp <- propose_roles(tables$plots, mode = "collaborate", detect = FALSE)
  rp <- set_role(rp, "site", role = "design", action = "alias")
  rp <- set_role(rp, "rep", role = "design", action = "keep")
  rp <- set_role(rp, "yield", role = "outcome", action = "scramble")
  rm <- propose_roles(tables$meta, mode = "collaborate", detect = FALSE)
  rm <- set_role(rm, "site", role = "design", action = "alias")
  rm <- set_role(rm, "elev", role = "covariate", action = "scramble")
  list(plots = rp, meta = rm)
}

.link_map <- function(seed, caller_seed) {
  tables <- .link_tables()
  set.seed(caller_seed)
  ms <- suppressWarnings(mask_set(
    tables, roles = .link_roles(tables), mode = "collaborate",
    seed = seed, quiet = TRUE
  ))
  recipe(ms)@links[[1L]]$map
}

test_that("mask_set() link maps follow seed, not the caller's RNG state", {
  a <- .link_map(seed = 7L, caller_seed = 1L)
  b <- .link_map(seed = 7L, caller_seed = 999L)
  expect_identical(a, b)
  expect_false(identical(a, .link_map(seed = 8L, caller_seed = 1L)))
})

test_that("jitter_coordinates() and synthesise_geospatial() refuse a bad seed", {
  df <- data.frame(lat = c(-34.9, -35.1), lon = c(138.6, 138.7))
  for (bad in list(1.5, NA_real_, c(1, 2), Inf, "1")) {
    expect_error(
      jitter_coordinates(df, "lat", "lon", seed = bad, on_land = FALSE),
      class = "masque_bad_seed_refusal"
    )
  }
  orig <- data.frame(
    site = c("a", "a", "b"), lat = c(-34.9, -34.9, -35.1),
    lon = c(138.6, 138.6, 138.7)
  )
  cent <- list(a = c(lat = -34.9, lon = 138.6), b = c(lat = -35.1, lon = 138.7))
  for (bad in list(1.5, NA_real_, c(1, 2))) {
    expect_error(
      synthesise_geospatial(orig, orig, "site", "lat", "lon", cent,
                            seed = bad),
      class = "masque_bad_seed_refusal"
    )
  }
})

test_that("conform_table() reports a label holding braces as text", {
  for (lab in c("{x}", "{nrow(done)}")) {
    df <- data.frame(
      tag = c(rep(paste(lab, "alpha"), 6L), paste(lab, "Alpha"),
              rep("plain", 5L)),
      stringsAsFactors = FALSE
    )
    out <- capture_full(
      cf <- conform_table(df, merge_labels = "auto", quiet = FALSE)
    )
    expect_identical(nrow(cf$merges), 1L)
    expect_match(
      gsub("\\s+", " ", out),
      sprintf('"%s Alpha" and "%s alpha" are the same category', lab, lab),
      fixed = TRUE
    )
    expect_false(grepl("list(", out, fixed = TRUE))
  }
})

test_that("the all-keep warning carries a masque_ class", {
  r <- propose_roles(iris, detect = FALSE)
  r <- set_role(r, names(iris), action = "keep")
  expect_warning(roles_validate(r, iris), class = "masque_all_keep")
})

test_that("a coords entry named latitude is not read as lat", {
  df <- data.frame(latitude = c(-34.9, -35.1), lon = c(138.6, 138.7))
  expect_error(
    .normalise_coords(list(list(latitude = "latitude", lon = "lon")), df),
    "needs `lat` and `lon`"
  )
  expect_error(
    .normalise_coords(list(list(lat = "latitude", lon = "lon",
                                method_extra = "x", min = 1)), df),
    NA
  )
  spec <- .normalise_coords(
    list(list(lat = "latitude", lon = "lon", min = 1)), df
  )
  expect_identical(spec[[1L]]$min_km, 5)
})
