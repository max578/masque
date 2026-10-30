# F11 and the data card (contract C8 v0.1): roles(), data_card(), the YAML
# writer, provenance, the name map, sets and the leak rule.

skip_if_not_installed("yaml")

.card_mask <- function(alias_names = FALSE, seed = 424242L) {
  df <- .card_plots()
  suppressWarnings(mask(
    df, .card_roles(df), mode = "collaborate", seed = seed,
    alias_names = alias_names
  ))
}

# roles() ---------------------------------------------------------------------

test_that("roles() returns the four public columns, one row per clone column", {
  m <- .card_mask()
  r <- roles(m)
  expect_s3_class(r, "data.table")
  expect_identical(names(r), c("col", "role", "action", "kind"))
  expect_identical(r$col, names(synthetic(m)))
  expect_identical(r$role[r$col == "gen"], "treatment")
  expect_identical(r$action[r$col == "site"], "alias")
})

test_that("roles() speaks the clone's names on an aliased clone", {
  m <- .card_mask(alias_names = TRUE)
  r <- roles(m)
  expect_identical(r$col, names(synthetic(m)))
  expect_false(any(names(.card_plots()) %in% r$col))
  map <- recipe(m)@column_name_map
  expect_identical(r$role[r$col == map$gen], "treatment")
})

test_that("roles() leaves out a dropped column and refuses a non-masque", {
  df <- .card_plots()
  r <- set_role(.card_roles(df), "weeds", action = "drop")
  m <- suppressWarnings(mask(df, r, mode = "collaborate", seed = 1L))
  expect_false("weeds" %in% roles(m)$col)
  expect_error(roles(df), class = "masque_bad_masque_obj_refusal")
})

# The card against the composeR schema ----------------------------------------

test_that("data_card() is valid against composeR's C8 v0.1 schema", {
  m <- .card_mask()
  card <- data_card(m)
  .expect_valid_card(card)
  expect_identical(card$card_version, "0.1")
  expect_identical(card$produced_by$package, "masque")
  expect_identical(
    card$produced_by$version, as.character(utils::packageVersion("masque"))
  )
  expect_identical(card$produced_by$mode, "collaborate")
  expect_identical(card$table$name, "clone")
  expect_identical(card$table$source, "clone")
  expect_identical(card$table$n_rows, 72L)
  expect_identical(card$table$n_cols, 7L)
})

test_that("the written YAML parses back to the card, and is valid", {
  m <- .card_mask()
  path <- withr::local_tempfile(fileext = ".yaml")
  card <- data_card(m, file = path)
  back <- yaml::read_yaml(path)
  expect_identical(back, card)
  .expect_valid_card(back)
  bytes <- readBin(path, "raw", file.size(path))
  expect_false(any(bytes == as.raw(13L)))
  lines <- readLines(path, encoding = "UTF-8")
  expect_false(any(grepl("[ \t]$", lines)))
  # A one-name column list is a sequence; a provenance class is a scalar.
  expect_true("  treatment_cols:" %in% lines)
  expect_true("    - \"gen\"" %in% lines)
  expect_true("    treatment_cols: \"structure\"" %in% lines)
})

# Design block from the role table (N2) ----------------------------------------

test_that("the design block is the role table, not the detector", {
  m <- .card_mask(alias_names = TRUE)
  map <- recipe(m)@column_name_map
  card <- data_card(m, env = map$site, unit = NULL)
  d <- card$design
  expect_null(d$class)
  expect_identical(unlist(d$treatment_cols), map$gen)
  expect_identical(unlist(d$block_cols), map$rep)
  expect_identical(unlist(d$env_cols), map$site)
  expect_identical(d$n_env, 3L)
  expect_identical(d$provenance$treatment_cols, "structure")
  expect_identical(d$provenance$env_cols, "analyst")
  expect_identical(d$provenance$n_env, "structure")
  .expect_valid_card(card)
})

test_that("env, spatial and unit must name design columns of the clone", {
  m <- .card_mask(alias_names = TRUE)
  expect_error(data_card(m, env = "site"), class = "masque_bad_card_column_refusal")
  map <- recipe(m)@column_name_map
  expect_error(
    data_card(m, env = map$yield), class = "masque_bad_card_column_refusal"
  )
  card <- data_card(m, unit = map$rep)
  expect_identical(card$design$unit_col, map$rep)
  expect_false(map$rep %in% unlist(card$design$block_cols))
})

# Provenance ------------------------------------------------------------------

test_that("every statistic tagged structure is exact against the original", {
  df <- .card_plots()
  m <- .card_mask(alias_names = TRUE)
  map <- recipe(m)@column_name_map
  real <- stats::setNames(names(map), unlist(map))
  card <- data_card(m)
  checked <- 0L
  for (col in card$columns) {
    x <- df[[real[[col$name]]]]
    obs <- x[!is.na(x)]
    for (stat in names(col$provenance)) {
      if (col$provenance[[stat]] != "structure" || stat == "kind") next
      truth <- switch(stat,
        n_levels = length(unique(obs)),
        n_missing = sum(is.na(x)),
        na_share = round(mean(is.na(x)), 6),
        zero_share = round(mean(obs == 0), 6)
      )
      expect_equal(col[[stat]], truth, info = paste(col$name, stat))
      checked <- checked + 1L
    }
  }
  expect_gt(checked, 10L)
  by_name <- stats::setNames(card$columns, vapply(card$columns, `[[`, "", "name"))
  expect_identical(by_name[[map$yield]]$provenance$n_levels, "clone_estimate")
  expect_identical(by_name[[map$site]]$provenance$n_levels, "structure")
  expect_identical(by_name[[map$rating]]$kind, "ordered")
})

test_that("events: pattern counts are structure, times and censoring estimates", {
  df <- .events_fixture(n = 300L)
  m <- suppressWarnings(mask(
    df, .events_roles(df), mode = "collaborate", seed = 7L,
    events = .events_spec
  ))
  card <- data_card(m)
  d <- card$design
  expect_identical(d$event_time_col, "time_rec")
  expect_identical(d$event_status_col, "status_rec")
  expect_identical(unlist(d$competing_status_cols), "status_death")
  expect_identical(d$n_events, sum(df$status_rec == 1L))
  expect_identical(d$provenance$n_events, "structure")
  expect_identical(d$provenance$censored_share, "clone_estimate")
  by_name <- stats::setNames(card$columns, vapply(card$columns, `[[`, "", "name"))
  expect_identical(by_name$time_rec$provenance$n_levels, "clone_estimate")
  expect_identical(by_name$status_rec$provenance$n_levels, "structure")
  expect_identical(by_name$status_death$provenance$zero_share, "structure")
  .expect_valid_card(card)

  card2 <- data_card(m, primary_event = 2L)
  expect_identical(card2$design$event_time_col, "time_death")
  expect_identical(unlist(card2$design$competing_status_cols), "status_rec")
  expect_identical(card2$design$n_events, sum(df$status_death == 1L))
  expect_error(
    data_card(m, primary_event = 3L), class = "masque_bad_card_event_refusal"
  )
})

test_that("event columns are carded under their aliases", {
  df <- .events_fixture(n = 300L)
  m <- suppressWarnings(mask(
    df, .events_roles(df), mode = "collaborate", seed = 7L,
    events = .events_spec, alias_names = TRUE
  ))
  map <- recipe(m)@column_name_map
  d <- data_card(m)$design
  expect_identical(d$event_time_col, map$time_rec)
  expect_identical(d$event_status_col, map$status_rec)
})

# Table name ------------------------------------------------------------------

test_that("a table name outside the schema pattern is refused, not cleaned", {
  m <- .card_mask()
  for (bad in c("my table", "1trial", "", "trial-2", NA_character_)) {
    expect_error(
      data_card(m, name = bad),
      class = "masque_bad_card_name_refusal", info = bad
    )
  }
  err <- tryCatch(data_card(m, name = "a b"), error = identity)
  expect_s3_class(err, "orchestra_refusal")
  expect_identical(data_card(m, name = "plots.v2")$table$name, "plots.v2")
})

# The card is a subset of the clone (S3, O1) -----------------------------------

test_that("rebuilt from synthetic(m) and roles(m) alone, the card is byte-equal", {
  for (alias in c(FALSE, TRUE)) {
    m <- .card_mask(alias_names = alias)
    a <- withr::local_tempfile(fileext = ".yaml")
    b <- withr::local_tempfile(fileext = ".yaml")
    data_card(m, file = a)
    rebuilt <- .card_build(
      synthetic(m), roles(m), mode = m@mode, events = list()
    )
    .card_write(rebuilt, b)
    expect_identical(
      readBin(a, "raw", file.size(a)), readBin(b, "raw", file.size(b)),
      info = paste("alias_names =", alias)
    )
  }
  # Same clone, card written twice: same bytes.
  m <- .card_mask()
  a <- withr::local_tempfile(fileext = ".yaml")
  b <- withr::local_tempfile(fileext = ".yaml")
  data_card(m, file = a)
  data_card(m, file = b)
  expect_identical(tools::md5sum(a)[[1L]], tools::md5sum(b)[[1L]])
})

test_that("an aliased clone's card carries no real label, name or seed", {
  m <- .card_mask(alias_names = TRUE, seed = 424242L)
  path <- withr::local_tempfile(fileext = ".yaml")
  data_card(m, file = path, env = recipe(m)@column_name_map$site)
  text <- paste(readLines(path, encoding = "UTF-8"), collapse = "\n")
  df <- .card_plots()
  tokens <- c(
    "424242", "SITEALPHA", "SITEBRAVO", "SITECHARLIE", "GENO01", "GENO08",
    paste0("\"", names(df), "\"")
  )
  for (tok in tokens) {
    expect_false(grepl(tok, text, fixed = TRUE), info = tok)
  }
  for (nm in names(df)) {
    expect_false(grepl(paste0("\\b", nm, "\\b"), text, perl = TRUE), info = nm)
  }
})

# Sets ------------------------------------------------------------------------

test_that("a set gives one card per table, and one file per table", {
  plots <- .card_plots()
  sites <- data.frame(
    site = factor(c("SITEALPHA", "SITEBRAVO", "SITECHARLIE")),
    rain = c(410, 395, 520)
  )
  rs <- list(
    plots = .card_roles(plots),
    sites = set_role(
      set_role(propose_roles(sites, mode = "collaborate"), "site",
               role = "design", action = "alias"),
      "rain", role = "covariate", action = "keep"
    )
  )
  s <- suppressWarnings(mask_set(
    list(plots = plots, sites = sites), roles = rs, mode = "collaborate",
    seed = 5L, quiet = TRUE
  ))
  cards <- data_card(s)
  expect_identical(names(cards), c("plots", "sites"))
  for (nm in names(cards)) {
    .expect_valid_card(cards[[nm]])
    expect_identical(cards[[nm]]$table$name, nm)
    expect_identical(cards[[nm]]$table$n_rows, nrow(synthetic(s)[[nm]]))
  }
  rset <- roles(s)
  expect_identical(names(rset), c("plots", "sites"))
  expect_identical(rset$sites$col, names(synthetic(s)$sites))

  dir <- withr::local_tempdir()
  data_card(s, file = dir)
  expect_setequal(
    list.files(dir), c("plots.data_card.yaml", "sites.data_card.yaml")
  )
  expect_identical(
    yaml::read_yaml(file.path(dir, "sites.data_card.yaml")), cards$sites
  )
})

test_that("the writer quotes and escapes every string", {
  txt <- .card_yaml(list(a = "say \"hi\"\\ok", b = list(), c = 2L, d = 0.5))
  expect_identical(
    txt,
    "a: \"say \\\"hi\\\"\\\\ok\"\nb: []\nc: 2\nd: 0.500000\n"
  )
  expect_identical(yaml::yaml.load(txt)$a, "say \"hi\"\\ok")
})
