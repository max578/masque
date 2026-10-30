# F14 + N1: no accidental display of a recipe-holding object shows a label or
# the seed. saveRDS(), dput() and reveal_maps() show the maps by design.

.leak_tokens <- c("LEAKTOKEN_ALPHA", "LEAKTOKEN_BETA", "424242")

.leak_plots <- function() {
  data.frame(
    site = factor(rep(c("LEAKTOKEN_ALPHA", "LEAKTOKEN_BETA"), each = 30L)),
    rep = rep(rep(1:3, each = 10L), 2L),
    gen = factor(rep(sprintf("G%02d", 1:10), 6L)),
    yield = round(5 + seq_len(60L) %% 7 / 3, 2)
  )
}

.leak_roles <- function(df) {
  r <- propose_roles(df, mode = "collaborate")
  for (col in names(df)) {
    spec <- switch(col,
      site = list(role = "design", action = "alias"),
      rep = list(role = "design", action = "keep"),
      gen = list(role = "treatment", action = "alias"),
      yield = list(role = "outcome", action = "scramble"),
      rain = list(role = "covariate", action = "scramble"),
      year = list(role = "design", action = "keep")
    )
    r <- set_role(r, col, role = spec$role, action = spec$action)
  }
  r
}

.leak_single <- function() {
  df <- .leak_plots()
  mask(df, .leak_roles(df), mode = "collaborate", seed = 424242L)
}

.leak_set <- function() {
  sites <- data.frame(
    site = factor(rep(c("LEAKTOKEN_ALPHA", "LEAKTOKEN_BETA"), 5L)),
    year = rep(2016:2020, each = 2L),
    rain = c(410, 395, 520, 480, 300, 350, 610, 590, 455, 470)
  )
  tables <- list(plots = .leak_plots(), sites = sites)
  roles <- lapply(tables, .leak_roles)
  mask_set(
    tables, roles = roles, mode = "collaborate", seed = 424242L, quiet = TRUE
  )
}

# Every display route a user or an IDE can reach without asking for the maps.
.display_routes <- function(x) {
  knit <- if (requireNamespace("knitr", quietly = TRUE)) {
    value <- NULL
    printed <- capture_full(value <- knitr::knit_print(x))
    # knitr writes a character result into the document as it stands.
    text <- if (is.character(value)) as.character(value) else character()
    paste(c(printed, text), collapse = "\n")
  } else {
    ""
  }
  list(
    print = capture_full(print(x)),
    format = paste(format(x), collapse = "\n"),
    str = capture_full(utils::str(x)),
    str_nested = capture_full(utils::str(list(held = x))),
    summary = capture_full(print(summary(x))),
    knit_print = knit
  )
}

.expect_no_tokens <- function(routes, what) {
  for (route in names(routes)) {
    for (tok in .leak_tokens) {
      expect_false(
        grepl(tok, routes[[route]], fixed = TRUE),
        info = sprintf("%s: %s() shows %s", what, route, tok)
      )
    }
  }
}

test_that("no display route of a single recipe or masque shows a label or the seed", {
  skip_if_not_installed("knitr")
  m <- .leak_single()
  rec <- recipe(m)
  # The fixture holds the tokens where an accidental dump would find them.
  expect_true(any(grepl("LEAKTOKEN_ALPHA", names(rec@level_maps$site))))
  expect_identical(rec@seed, 424242L)

  .expect_no_tokens(.display_routes(rec), "masque_recipe")
  .expect_no_tokens(.display_routes(m), "masque")
})

test_that("no display route of a recipe bundle or masque_set shows a label or the seed", {
  skip_if_not_installed("knitr")
  ms <- .leak_set()
  bundle <- recipe(ms)
  expect_true(any(grepl(
    "LEAKTOKEN_BETA", names(bundle@recipes$plots@level_maps$site)
  )))

  .expect_no_tokens(.display_routes(bundle), "masque_recipe_set")
  .expect_no_tokens(.display_routes(ms), "masque_set")
})

test_that("format() returns one redacted line for every recipe-holding class", {
  m <- .leak_single()
  ms <- .leak_set()
  for (x in list(recipe(m), m, recipe(ms), ms)) {
    out <- format(x)
    expect_type(out, "character")
    expect_length(out, 1L)
  }
  expect_match(format(recipe(ms)), "masque_recipe_set")
  expect_match(format(ms), "masque_set")
})

test_that("the bundle print shows its header, link names and each table's redacted recipe", {
  ms <- .leak_set()
  out <- capture_full(print(recipe(ms)))
  expect_match(out, "masque_recipe_set")
  expect_match(out, "site", fixed = TRUE)
  expect_match(out, "plots", fixed = TRUE)
  expect_match(out, "sites", fixed = TRUE)
  # One redacted per-table block per table, each with its own private banner.
  per_table <- regmatches(out, gregexpr("Seed: present \\(redacted\\)", out))
  expect_length(per_table[[1L]], 2L)
  expect_match(out, "PRIVATE")
  # A link's map is not shown, only its name and tables.
  expect_false(grepl("site_K", out, fixed = TRUE))
})

test_that("str() lists no property values, including an unknown one holding labels", {
  m <- .leak_single()
  rec <- recipe(m)
  rec@cleaning <- list(near_duplicates = data.frame(
    a = "LEAKTOKEN_GAMMA", b = "LEAKTOKEN_GAMMB"
  ))
  out <- capture_full(utils::str(rec))
  expect_false(grepl("LEAKTOKEN_GAMM", out, fixed = TRUE))
  expect_match(out, "masque_recipe")
  expect_match(out, "reveal_maps", fixed = TRUE)
})

test_that("knit_print() returns redacted text for knitr", {
  skip_if_not_installed("knitr")
  m <- .leak_single()
  value <- knitr::knit_print(recipe(m))
  expect_s3_class(value, "knit_asis")
  expect_match(as.character(value), "masque_recipe")
  expect_match(as.character(value), "redacted")
})

test_that("a knitted document shows no label or seed", {
  skip_if_not_installed("knitr")
  skip_if_not_installed("rmarkdown")
  m <- .leak_single()
  ms <- .leak_set()
  env <- new.env()
  env$rec <- recipe(m)
  env$bundle <- recipe(ms)
  env$m <- m
  env$ms <- ms
  src <- withr::local_tempfile(fileext = ".Rmd")
  out <- withr::local_tempfile(fileext = ".md")
  writeLines(c(
    "```{r}", "rec", "bundle", "m", "ms", "str(bundle)", "```"
  ), src)
  knitr::knit(src, output = out, envir = env, quiet = TRUE)
  text <- paste(readLines(out), collapse = "\n")
  for (tok in .leak_tokens) {
    expect_false(grepl(tok, text, fixed = TRUE), info = tok)
  }
  expect_match(text, "masque_recipe_set")
})
