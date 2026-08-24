# Contract for the unmasked-coordinate guard (0.11.0).
#
# A masked table must not carry a real coordinate. The caller may state
# otherwise three ways -- declare the pair to `coords`, give the column a
# masking action, or pass `allow_unmasked_coords = TRUE` -- and nothing else
# gets a coordinate through.

.coord_fixture <- function(lat_name = "gps_s", lon_name = "gps_e", n = 40L) {
  d <- data.frame(
    a = rep(letters[1:4], length.out = n),
    y = stats::rnorm(n)
  )
  d[[lat_name]] <- rep(
    c(-34.90521, -35.21877, -33.61093, -36.10448), length.out = n
  )
  d[[lon_name]] <- rep(
    c(138.60113, 142.00762, 148.20391, 145.10228), length.out = n
  )
  d
}

# Roles that keep everything except the two ordinary columns.
.keep_roles <- function(d) {
  r <- suppressWarnings(propose_roles(d, detect = FALSE))
  r$action[r$col %in% setdiff(names(d), c("a", "y"))] <- "keep"
  r
}

test_that("a named coordinate column cannot be written unmasked", {
  set.seed(1)
  d <- .coord_fixture()
  expect_error(
    suppressWarnings(mask(d, .keep_roles(d), seed = 1)),
    class = "masque_unmasked_coords"
  )
})

test_that("the refusal names the column and reads in the singular", {
  set.seed(1)
  d <- .coord_fixture()
  d$gps_e <- NULL
  r <- suppressWarnings(propose_roles(d, detect = FALSE))
  r$action[r$col == "gps_s"] <- "keep"
  err <- tryCatch(
    suppressWarnings(mask(d, r, seed = 1)),
    masque_unmasked_coords = function(e) e
  )
  expect_match(conditionMessage(err), "gps_s")
  expect_match(conditionMessage(err), "Coordinate column ") # not "columns"
})

test_that("declaring the pair to `coords` satisfies the guard", {
  set.seed(1)
  d <- .coord_fixture()
  m <- suppressWarnings(mask(
    d, .keep_roles(d), seed = 1,
    coords = list(list(lat = "gps_s", lon = "gps_e", on_land = FALSE))
  ))
  syn <- synthetic(m)
  expect_false(isTRUE(all.equal(syn$gps_s, d$gps_s))) # coarsened, not kept
})

test_that("a masking action satisfies the guard", {
  set.seed(1)
  d <- .coord_fixture()
  # propose_roles() proposes `drop` for a PII-named column by default.
  r <- suppressWarnings(propose_roles(d, detect = FALSE))
  expect_no_error(suppressWarnings(mask(d, r, seed = 1)))
})

test_that("`allow_unmasked_coords` is the stated-otherwise escape", {
  set.seed(1)
  d <- .coord_fixture()
  expect_warning(
    m <- mask(d, .keep_roles(d), seed = 1, allow_unmasked_coords = TRUE),
    class = "masque_unmasked_coords_allowed"
  )
  expect_identical(synthetic(m)$gps_s, d$gps_s)  # written through, as asked
  expect_true(recipe(m)@allow_unmasked_coords)   # and recorded
})

test_that("`allow_unmasked_coords` is validated", {
  set.seed(1)
  d <- .coord_fixture()
  expect_error(
    suppressWarnings(mask(d, .keep_roles(d), allow_unmasked_coords = "yes")),
    "single logical"
  )
})

test_that("coordinate-shaped values warn without blocking", {
  # Names carry no coordinate token, so confidence is lower: warn, do not stop.
  set.seed(1)
  d <- .coord_fixture(lat_name = "site_x", lon_name = "site_y")
  expect_warning(
    mask(d, .keep_roles(d), seed = 1),
    class = "masque_coords_suspected"
  )
})

test_that("ordinary numeric covariates do not trip the value-shape test", {
  set.seed(1)
  n <- 40L
  d <- data.frame(
    a       = rep(letters[1:4], length.out = n),
    temp_c  = round(stats::rnorm(n, 18, 6), 1),   # 1 dp
    yield_t = round(stats::runif(n, 1, 9), 2),    # 2 dp
    ph      = round(stats::runif(n, 4.5, 8.5), 1),
    y       = stats::rnorm(n)
  )
  r <- suppressWarnings(propose_roles(d, detect = FALSE))
  r$action[r$col %in% c("temp_c", "yield_t", "ph")] <- "keep"
  expect_no_warning(mask(d, r, seed = 1), class = "masque_coords_suspected")
})

test_that("whole-number and low-precision columns are not coordinates", {
  d <- data.frame(
    plot_no = as.numeric(1:40),                    # in range, but whole
    rate    = rep(c(12.5, 25.0, 50.0, 75.0), 10)   # in range, 1 dp
  )
  expect_length(.coordinate_shaped_pairs(d, names(d)), 0L)
})

test_that("a lone coordinate-shaped column is not a pair", {
  set.seed(2)
  d <- data.frame(one = stats::runif(40, -40, -30))
  expect_length(.coordinate_shaped_pairs(d, names(d)), 0L)
})

# ---- the audit no longer calls a coarsened coordinate "kept as-is" ----------

test_that("a coarsened coordinate audits as medium, described correctly", {
  set.seed(1)
  n <- 6L
  k <- 20L
  d <- data.frame(
    trial = rep(paste0("T", seq_len(n)), each = k),
    gen   = rep(letters[1:5], length.out = n * k),
    gps_s = rep(seq(-36, -33, length.out = n), each = k),
    gps_e = rep(seq(139, 147, length.out = n), each = k),
    y     = stats::rnorm(n * k)
  )
  r <- suppressWarnings(propose_roles(d, mode = "collaborate"))
  m <- suppressWarnings(mask(
    d, r, mode = "collaborate", seed = 1,
    coords = list(list(lat = "gps_s", lon = "gps_e", by = "trial",
                       on_land = FALSE))
  ))
  a <- audit_mask(m, d)
  rows <- a[a$col %in% c("gps_s", "gps_e"), ]
  expect_true(all(rows$leakage_class == "medium"))
  expect_true(all(grepl("coarsened in place", rows$notes)))
  expect_false(any(grepl("kept as-is", rows$notes)))
})
