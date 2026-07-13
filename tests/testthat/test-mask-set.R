# Set layer: read_set ingestion, mask_set cross-table linking, the
# recipe bundle, round-tripping, and write_set.

make_set <- function() {
  list(
    trials = data.frame(
      env = rep(c("E1", "E2"), each = 6),
      gen = rep(c("Scope", "Compass", "Spartacus"), 4),
      yield = c(3.1, 2.9, 4.0, 3.7, 5.2, 5.0, 3.3, 2.8, 4.1, 3.6, 5.1, 4.9),
      stringsAsFactors = FALSE
    ),
    pedigree = data.frame(
      gen = c("Scope", "Compass", "Spartacus"),
      maturity = c("early", "mid", "late"),
      stringsAsFactors = FALSE
    )
  )
}

trt_roles <- function(tables, mode = "collaborate") {
  list(
    trials = set_role(
      propose_roles(tables$trials, mode = mode, detect = FALSE),
      "gen", role = "treatment"
    ),
    pedigree = set_role(
      propose_roles(tables$pedigree, mode = mode, detect = FALSE),
      "gen", role = "treatment"
    )
  )
}

test_that("read_set validates a named list of tables", {
  s <- read_set(make_set())
  expect_named(s, c("trials", "pedigree"))
})

test_that("read_set rejects unnamed or malformed sets", {
  expect_error(read_set(list(data.frame(a = 1))), "must be named")
  expect_error(
    read_set(list(t1 = data.frame(a = 1), t1 = data.frame(b = 2))),
    "Duplicate"
  )
  expect_error(read_set(list(t1 = data.frame())), "no columns")
})

test_that("read_set reads a folder of CSVs", {
  d <- withr::local_tempdir()
  tab <- make_set()
  utils::write.csv(tab$trials, file.path(d, "trials.csv"), row.names = FALSE)
  utils::write.csv(tab$pedigree, file.path(d, "pedigree.csv"), row.names = FALSE)
  s <- read_set(d)
  expect_setequal(names(s), c("trials", "pedigree"))
  expect_equal(nrow(s$trials), 12L)
})

test_that("mask_set links a shared column and aliases it consistently", {
  m <- mask_set(make_set(), roles = trt_roles(make_set()),
    mode = "collaborate", seed = 1, quiet = TRUE
  )
  st <- synthetic(m)$trials
  sp <- synthetic(m)$pedigree
  # Same genotype -> same alias in both tables (the join survives).
  expect_setequal(
    unique(as.character(st$gen)), unique(as.character(sp$gen))
  )
  expect_false(any(c("Scope", "Compass") %in% as.character(st$gen)))
  # One link recorded.
  expect_equal(length(recipe(m)@links), 1L)
  expect_equal(recipe(m)@links[[1]]$name, "gen")
})

test_that("a linked column survives even when its action is drop", {
  # pedigree$gen auto-classifies as text -> drop in collaborate, but as a
  # link it must be kept (aliased) so the join still resolves.
  tables <- make_set()
  m <- mask_set(tables, mode = "collaborate", seed = 1, quiet = TRUE)
  expect_true("gen" %in% names(synthetic(m)$pedigree))
})

test_that("mask_set round-trips through apply_recipe + unmask", {
  tables <- make_set()
  m <- mask_set(tables, roles = trt_roles(tables),
    mode = "collaborate", seed = 1, quiet = TRUE
  )
  back <- unmask(synthetic(m), recipe(m))
  expect_equal(as.character(back$trials$gen), tables$trials$gen)
  expect_equal(as.character(back$pedigree$gen), tables$pedigree$gen)

  fwd <- apply_recipe(tables, recipe(m))
  expect_setequal(names(fwd), c("trials", "pedigree"))
  # Forward translation lands in the same alias namespace as the synthetic.
  expect_setequal(
    unique(as.character(fwd$trials$gen)),
    unique(as.character(synthetic(m)$trials$gen))
  )
})

test_that("links = FALSE masks each table independently", {
  tables <- make_set()
  m <- mask_set(tables, roles = trt_roles(tables), links = FALSE,
    mode = "collaborate", seed = 1, quiet = TRUE
  )
  expect_equal(length(recipe(m)@links), 0L)
  # Independent aliasing: the two tables need not agree.
  st <- synthetic(m)$trials
  sp <- synthetic(m)$pedigree
  expect_false(any(c("Scope", "Compass") %in% as.character(st$gen)))
})

test_that("write_set mirrors folder format and never writes the recipe", {
  tables <- make_set()
  m <- mask_set(tables, roles = trt_roles(tables),
    mode = "collaborate", seed = 1, quiet = TRUE
  )
  d <- withr::local_tempdir()
  out <- file.path(d, "masked")
  write_set(m, out)
  files <- list.files(out)
  expect_setequal(files, c("trials.csv", "pedigree.csv"))
  # Round-trip the written CSVs back in.
  back_in <- read_set(out)
  expect_setequal(names(back_in), c("trials", "pedigree"))
})

test_that("write_set refuses to overwrite without overwrite = TRUE", {
  tables <- make_set()
  # trt_roles() keeps every non-treatment column, so mask() legitimately
  # warns that nothing will be masked; the warning is not this test's
  # subject.
  m <- suppressWarnings(mask_set(tables, roles = trt_roles(tables),
    mode = "local", seed = 1, quiet = TRUE
  ))
  d <- withr::local_tempdir()
  write_set(m, d)
  expect_error(write_set(m, d), "already contains")
  expect_silent(write_set(m, d, overwrite = TRUE))
})

test_that("the shipped met_set fixture masks and joins", {
  dir <- system.file("extdata", "met_set", package = "masque")
  skip_if(dir == "", "met_set fixture not installed")
  s <- read_set(dir)
  expect_setequal(names(s), c("agronomy", "quality"))
  m <- mask_set(dir, mode = "collaborate", seed = 1, quiet = TRUE)
  ag <- synthetic(m)$agronomy
  qa <- synthetic(m)$quality
  # gen is a shared treatment-like key -> linked and consistently aliased.
  link_names <- vapply(recipe(m)@links, `[[`, character(1L), "name")
  expect_true("gen" %in% link_names)
  expect_setequal(unique(as.character(ag$gen)), unique(as.character(qa$gen)))
  # env auto-classifies as design (kept byte-identical), so the join on
  # env still resolves without an alias map.
  expect_setequal(unique(as.character(ag$env)), unique(as.character(qa$env)))
})
