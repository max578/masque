# A table with no grained column must clone byte for byte as it did before
# grain synthesis: no extra draws, no reordering.

.repro_fixture <- function() {
  withr::with_seed(20261030L, {
    n <- 72L
    df <- data.frame(
      trial = rep(sprintf("T%d", 1:4), each = 18L),
      rep = rep(rep(1:3, each = 6L), 4L),
      genotype = rep(sprintf("G%d", 1:6), 12L),
      yield = round(stats::rnorm(n, 4, 0.6), 3),
      height = round(stats::rnorm(n, 90, 7), 1),
      count = stats::rpois(n, 12),
      soil_n = round(stats::runif(n, 5, 40), 2),
      texture = sample(c("clay", "loam", "sand"), n, TRUE),
      sown = as.Date("2024-05-01") + sample(0:30, n, TRUE),
      stringsAsFactors = FALSE
    )
    df$height[c(3, 17, 40)] <- NA
    df$texture[c(5, 60)] <- NA
    df
  })
}

.repro_roles <- function(df, mode) {
  r <- suppressWarnings(propose_roles(df, mode = mode, detect = FALSE))
  r <- set_role(r, c("trial", "rep"), role = "design", action = "keep")
  r <- set_role(r, "genotype", role = "treatment",
                action = if (mode == "collaborate") "alias" else "keep")
  r <- set_role(r, "yield", role = "outcome", action = "scramble")
  r <- set_role(r, c("height", "count", "soil_n"), role = "covariate",
                action = "scramble")
  r <- set_role(r, "texture", role = "covariate",
                action = if (mode == "collaborate") "alias" else "scramble")
  r <- set_role(r, "sown", role = "date", action = "scramble")
  r
}

# Text form of a clone, doubles at 10 significant digits.
.repro_canon <- function(m) {
  syn <- as.data.frame(synthetic(m))
  cols <- vapply(names(syn), function(nm) {
    x <- syn[[nm]]
    v <- if (is.double(x) && !inherits(x, "Date")) {
      sprintf("%.10g", x)
    } else {
      as.character(x)
    }
    paste(nm, paste(class(x), collapse = "/"), paste(v, collapse = ","),
          sep = "|")
  }, character(1))
  maps <- recipe(m)@level_maps
  map_txt <- vapply(names(maps), function(nm) {
    paste(nm, paste(names(maps[[nm]]), maps[[nm]], sep = "=", collapse = ","),
          sep = "|")
  }, character(1))
  digest::digest(paste(c(cols, map_txt), collapse = "\n"), algo = "sha256",
                 serialize = FALSE)
}

test_that("a table with no grained column clones as with grain = FALSE", {
  df <- .repro_fixture()
  for (mode in c("local", "collaborate")) {
    roles <- .repro_roles(df, mode)
    expect_length(.detect_grain(df, roles), 0L)
    for (cond in c(FALSE, TRUE)) {
      key <- sprintf("%s_%s", mode, cond)
      m <- suppressWarnings(suppressMessages(mask(
        df, roles, mode = mode, seed = 1L, conditional = cond
      )))
      expect_length(recipe(m)@grain, 0L)
      m0 <- suppressWarnings(suppressMessages(mask(
        df, roles, mode = mode, seed = 1L, conditional = cond, grain = FALSE
      )))
      expect_identical(synthetic(m), synthetic(m0), label = key)
      expect_identical(recipe(m)@level_maps, recipe(m0)@level_maps,
                       label = key)
    }
  }
})

test_that("on the recording platform the clones match the 0.16.0 base", {
  skip_on_cran()
  skip_unless_digest_platform()
  # Base 12ead24 digests; collaborate re-taken after the jitter clip went.
  base <- c(
    local_FALSE =
      "ba60bae634f27d436a003f1ab22bc4146a77e64aea643d9716349d0325499097",
    local_TRUE =
      "50992aff8e147e21a46c7aeee0276b2e3a47e140a67998d679a3869ecbc24b52",
    collaborate_FALSE =
      "816c6e8d7c466a000bed73c43b4b5d4a2a7c70a252e70c79d7a670d99f7ad0a8",
    collaborate_TRUE =
      "de986487ca13bd4e9e76d2eed909d7925bd5dcf7a0c81dabc0aafcd582121d4b"
  )
  df <- .repro_fixture()
  for (mode in c("local", "collaborate")) {
    roles <- .repro_roles(df, mode)
    for (cond in c(FALSE, TRUE)) {
      key <- sprintf("%s_%s", mode, cond)
      m <- suppressWarnings(suppressMessages(mask(
        df, roles, mode = mode, seed = 1L, conditional = cond
      )))
      expect_identical(.repro_canon(m), base[[key]], label = key)
    }
  }
})
