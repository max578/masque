# mask_set() link maps draw from their own sub-stream of `seed`.

# 12 sites linked between a plot table and a site table.
.ls_tables <- function() {
  sites <- sprintf("Site%02d", 1:12)
  list(
    plots = data.frame(
      site = rep(sites, each = 4L), rep = rep(1:4, 12L),
      yield = round(seq(3, 6, length.out = 48L), 2),
      stringsAsFactors = FALSE
    ),
    meta = data.frame(
      site = sites, elev = seq(100, 650, by = 50), stringsAsFactors = FALSE
    )
  )
}

.ls_map <- function(seed) {
  tables <- .ls_tables()
  rp <- propose_roles(tables$plots, mode = "collaborate", detect = FALSE)
  rp <- set_role(rp, "site", role = "design", action = "alias")
  rp <- set_role(rp, "rep", role = "design", action = "keep")
  rp <- set_role(rp, "yield", role = "outcome", action = "scramble")
  rm <- propose_roles(tables$meta, mode = "collaborate", detect = FALSE)
  rm <- set_role(rm, "site", role = "design", action = "alias")
  rm <- set_role(rm, "elev", role = "covariate", action = "scramble")
  ms <- suppressWarnings(mask_set(
    tables, roles = list(plots = rp, meta = rm), mode = "collaborate",
    seed = seed, quiet = TRUE
  ))
  recipe(ms)@links[[1L]]$map
}

test_that("link maps repeat exactly for a seed", {
  expect_identical(.ls_map(11L), .ls_map(11L))
})

test_that("link maps are not drawn from the tables' own stream", {
  for (s in 1:5) {
    map <- .ls_map(s)
    order <- as.integer(sub(".*_K", "", unname(map)))
    table_stream <- withr::with_seed(s, sample.int(12L))
    expect_false(identical(order, table_stream), label = paste("seed", s))
  }
})

test_that("the link sub-stream differs from the table and coords streams", {
  for (s in c(-5L, 0L, 1L, 7L, .Machine$integer.max)) {
    link <- masque:::.link_seed(s)
    expect_true(link != s)
    expect_false(link %in% masque:::.sub_seeds(s, 10L))
  }
})
