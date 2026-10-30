.grain_set <- function() {
  withr::with_seed(21L, {
    plots <- expand.grid(
      gen = sprintf("G%02d", 1:6), rep = 1:2, site = sprintf("S%d", 1:6),
      stringsAsFactors = FALSE, KEEP.OUT.ATTRS = FALSE
    )
    plots$yield <- round(stats::rnorm(nrow(plots), 4, 0.5), 2)
    plots$aet <- c(312.4, 287.9, 401.2, 355.6, 298.1, 376.5)[
      match(plots$site, sprintf("S%d", 1:6))
    ]
    sites <- data.frame(
      site = sprintf("S%d", 1:6), elev = c(120, 340, 95, 410, 220, 180),
      stringsAsFactors = FALSE
    )
    list(plots = plots, sites = sites)
  })
}

.grain_set_roles <- function(tables) {
  rp <- suppressWarnings(propose_roles(tables$plots, mode = "local",
                                       detect = FALSE))
  rp <- set_role(rp, c("site", "rep"), role = "design", action = "keep")
  rp <- set_role(rp, "gen", role = "treatment", action = "keep")
  rp <- set_role(rp, "yield", role = "outcome", action = "scramble")
  rp <- set_role(rp, "aet", role = "covariate", action = "scramble")
  rs <- propose_roles(tables$sites, mode = "local", detect = FALSE)
  rs <- set_role(rs, "site", role = "design", action = "keep")
  rs <- set_role(rs, "elev", role = "covariate", action = "scramble")
  list(plots = rp, sites = rs)
}

.per_site <- function(syn) {
  vapply(split(syn$aet, syn$site), function(v) length(unique(v)), integer(1L))
}

test_that("mask_set() passes grain to every table", {
  tables <- .grain_set()
  roles <- .grain_set_roles(tables)
  on <- suppressWarnings(mask_set(tables, roles = roles, mode = "local",
                                  seed = 2L, quiet = TRUE))
  off <- suppressWarnings(mask_set(tables, roles = roles, mode = "local",
                                   seed = 2L, quiet = TRUE, grain = FALSE))
  expect_true(all(.per_site(synthetic(on)$plots) == 1L))
  expect_true(any(.per_site(synthetic(off)$plots) > 1L))
  g_on <- recipe(on)@recipes$plots@grain
  g_off <- recipe(off)@recipes$plots@grain
  expect_identical(g_on[[1L]]$synthesised, "unit")
  expect_identical(g_off[[1L]]$synthesised, "row")
  expect_error(
    mask_set(tables, roles = roles, mode = "local", seed = 2L, quiet = TRUE,
             grain = NA),
    class = "masque_bad_grain_refusal"
  )
})

test_that("masque() passes grain to a set", {
  tables <- .grain_set()
  roles <- .grain_set_roles(tables)
  off <- suppressWarnings(masque(tables, roles = roles, mode = "local",
                                 seed = 2L, ask = FALSE, quiet = TRUE,
                                 grain = FALSE))
  expect_identical(recipe(off)@recipes$plots@grain[[1L]]$synthesised, "row")
  on <- suppressWarnings(masque(tables, roles = roles, mode = "local",
                                seed = 2L, ask = FALSE, quiet = TRUE))
  expect_true(all(.per_site(synthetic(on)$plots) == 1L))
})
