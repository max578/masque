# Findings of the external review of 0.18.0: summary noise on few finite
# values, the grain path, integer64, logicals, and the null-mode stream.

# The shipped files of a handover folder, as one character vector.
handover_text <- function(m) {
  out <- file.path(withr::local_tempdir(.local_envir = parent.frame()), "pack")
  suppressWarnings(handover(m, out))
  unlist(lapply(list.files(out, full.names = TRUE), readLines))
}

test_that("one finite cell in a 30-row column does not reach the clone", {
  withr::local_seed(1L)
  d <- data.frame(
    block = rep(paste0("B", 1:5), each = 6), gen = rep(paste0("G", 1:6), 5),
    yield = stats::rnorm(30, 5), y = NA_real_
  )
  d$y[7] <- 42.5
  r <- propose_roles(d, detect = FALSE)
  expect_warning(
    m <- mask(d, r, seed = 3L, quiet = TRUE),
    class = "masque_noise_small_sample"
  )
  s <- synthetic(m)
  expect_identical(is.na(s$y), is.na(d$y))
  expect_false(any(s$y == 42.5, na.rm = TRUE))
  expect_false(any(grepl("42.5", handover_text(m), fixed = TRUE)))
})

test_that("one observed unit of a grained column does not reach the clone", {
  withr::local_seed(2L)
  d <- data.frame(
    site = rep(paste0("S", 1:4), each = 8), rep = rep(1:2, 16),
    gen = rep(paste0("G", 1:4), 8), yield = stats::rnorm(32, 5),
    rain = NA_real_
  )
  d$rain[d$site == "S2"] <- 300
  r <- propose_roles(d, detect = FALSE)
  expect_warning(
    m <- mask(d, r, seed = 3L, quiet = TRUE),
    class = "masque_noise_small_sample"
  )
  s <- synthetic(m)
  expect_identical(is.na(s$rain), is.na(d$rain))
  expect_false(any(s$rain == 300, na.rm = TRUE))
  expect_false(any(grepl("300", handover_text(m), fixed = TRUE)))
})

test_that("four observed units of a grained column are not resampled", {
  withr::local_seed(3L)
  d <- data.frame(
    site = rep(paste0("S", 1:4), each = 8), rep = rep(1:2, 16),
    gen = rep(paste0("G", 1:4), 8), yield = stats::rnorm(32, 5)
  )
  d$rain <- c(300, 380, 420, 510)[as.integer(factor(d$site))]
  r <- propose_roles(d, detect = FALSE)
  expect_warning(
    m <- mask(d, r, seed = 9L, quiet = TRUE),
    class = "masque_noise_small_sample"
  )
  s <- synthetic(m)
  expect_false(any(s$rain %in% c(300, 380, 420, 510)))
  # The unit grain itself is kept: one value per site.
  expect_true(all(tapply(s$rain, d$site, data.table::uniqueN) == 1L))
})

test_that("twelve finite values use the summary and warn nothing", {
  d <- data.frame(b = rep(c("A", "B"), 10), v = c(1:12 + 0.5, rep(NA, 8)))
  r <- propose_roles(d, detect = FALSE)
  expect_no_warning(m <- mask(d, r, seed = 1L, quiet = TRUE))
  v <- synthetic(m)$v
  q <- stats::quantile(d$v, c(0.01, 0.99), na.rm = TRUE, names = FALSE)
  expect_true(all(v >= q[1] & v <= q[2], na.rm = TRUE))
})

test_that("integer64 is refused", {
  d <- data.frame(b = rep(c("A", "B"), 5))
  d$v <- structure(as.double(1:10), class = "integer64")
  r <- propose_roles(d, detect = FALSE)
  expect_error(
    mask(d, r, seed = 2L, quiet = TRUE),
    class = "masque_integer64_refusal"
  )
  # Kept or dropped, the column is not read, so it passes.
  r2 <- set_role(r, "v", action = "drop")
  expect_s3_class(
    synthetic(suppressWarnings(mask(d, r2, seed = 2L, quiet = TRUE))),
    "data.frame"
  )
})

test_that("a short all-TRUE logical is refused in null mode", {
  d <- data.frame(b = c("A", "A", "B", "B"), f = TRUE)
  r <- propose_roles(d, detect = FALSE)
  expect_error(
    mask(d, r, seed = 1L, quiet = TRUE),
    class = "masque_too_few_rows_refusal"
  )
})

test_that("a one-value logical warns that it is copied", {
  d <- data.frame(b = rep(c("A", "B"), 15), f = TRUE)
  r <- propose_roles(d, detect = FALSE)
  expect_warning(
    m <- mask(d, r, seed = 1L, quiet = TRUE),
    class = "masque_noise_single_value"
  )
  expect_true(all(synthetic(m)$f))
})

test_that("a logical with few observed values is drawn over both values", {
  d <- data.frame(b = rep(c("A", "B"), 15), f = c(rep(TRUE, 6), rep(NA, 24)))
  r <- propose_roles(d, detect = FALSE)
  expect_warning(
    m <- mask(d, r, seed = 1L, quiet = TRUE),
    class = "masque_noise_small_sample"
  )
  f <- synthetic(m)$f
  expect_identical(is.na(f), is.na(d$f))
  expect_type(f, "logical")
})

test_that("moving a value that sets no knot leaves the clone unchanged", {
  # n = 101: type-7 knots sit on order statistics 2, 11, 21, ..., 91, 100.
  d <- data.frame(b = rep(c("A", "B"), length.out = 101), v = (1:101) + 0.5)
  moved <- d
  moved$v[5] <- 5.2
  r <- propose_roles(d, detect = FALSE)
  a <- synthetic(mask(d, r, seed = 6L, quiet = TRUE))
  b <- synthetic(mask(moved, r, seed = 6L, quiet = TRUE))
  expect_identical(a$v, b$v)
  # Falsifier: moving a knot does change it.
  knot <- d
  knot$v[11] <- 11.2
  k <- synthetic(mask(knot, r, seed = 6L, quiet = TRUE))
  expect_false(identical(a$v, k$v))
})

test_that("standard noise reads type flags only, not the mean", {
  withr::local_seed(5L)
  d <- data.frame(
    b = rep(c("A", "B"), 10),
    a = stats::rpois(20, 3) + 2L, c = stats::rpois(20, 40) + 2L
  )
  r <- propose_roles(d, detect = FALSE)
  one <- synthetic(mask(d[, c("b", "a")], r[r$col != "c", ],
    seed = 5L, noise = "standard", quiet = TRUE
  ))
  two <- synthetic(mask(d[, c("b", "c")], r[r$col != "a", ],
    seed = 5L, noise = "standard", quiet = TRUE
  ))
  expect_identical(as.numeric(one$a), as.numeric(two$c))
})

test_that("categorical noise does not keep a balanced factor's frequencies", {
  d <- data.frame(
    b = rep(c("A", "B"), 30),
    f = factor(rep(c("x", "y", "z"), each = 20))
  )
  r <- propose_roles(d, detect = FALSE)
  s <- synthetic(mask(d, r, seed = 1L, quiet = TRUE))
  expect_false(all(table(s$f) == 20L))
})

test_that("summary draws stay in [p1, p99] and leave it only by rounding", {
  withr::local_seed(8L)
  v <- stats::rnorm(200, 10, 3)
  knots <- masque:::.noise_summary(v)
  draws <- masque:::.noise_from_summary(knots, 5000L)
  expect_true(all(draws >= knots[1] & draws <= knots[11]))
  # Falsifier: a draw just outside the knots is caught by the same check.
  expect_false(all(c(draws, knots[11] + 1e-9) <= knots[11]))

  d <- data.frame(b = rep(c("A", "B"), 10), v = 1:20)
  r <- propose_roles(d, detect = FALSE)
  q <- stats::quantile(d$v, c(0.01, 0.99), names = FALSE)
  for (sd in 1:30) {
    s <- synthetic(mask(d, r, seed = sd, quiet = TRUE))$v
    expect_true(all(s >= round(q[1]) & s <= round(q[2])), info = sd)
  }
})

test_that("null and collaborate clones of one column are not paired", {
  withr::local_seed(4L)
  # One drawn column only: a second column, or a noise label, would consume
  # draws first and hide the pairing (0.999 under a shared stream).
  d <- data.frame(
    b = factor(rep(c("A", "B"), 100)), v = stats::rnorm(200, 10, 2)
  )
  rn <- set_role(
    propose_roles(d, mode = "null", detect = FALSE), "b", role = "design"
  )
  rc <- set_role(
    propose_roles(d, mode = "collaborate", detect = FALSE), "b",
    role = "design"
  )
  n <- synthetic(mask(d, rn, mode = "null", seed = 1L, quiet = TRUE))$v
  co <- suppressWarnings(synthetic(
    mask(d, rc, mode = "collaborate", seed = 1L, quiet = TRUE)
  ))$v
  expect_lt(abs(stats::cor(n, co)), 0.3)
})
