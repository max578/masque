# Null mode, the default since 0.18.0: design and missing-value pattern exact,
# labels coded, every outcome, covariate and date drawn independently.

null_fixture <- function() {
  withr::with_seed(3L, {
    n <- 60L
    df <- data.frame(
      site = factor(rep(c("Roseworthy", "Minnipa", "Turretfield"), each = 20L)),
      rep = rep(1:4, 15L),
      variety = factor(rep(sprintf("V%02d", 1:5), 12L)),
      yield = round(stats::rlnorm(n, 1.5, 0.3), 2),
      share = stats::runif(n),
      count = stats::rpois(n, 4),
      soil = sample(c("clay", "loam", "sand"), n, TRUE),
      grade = factor(sample(c("A", "B", "C", "D"), n, TRUE)),
      wet = sample(c(TRUE, FALSE), n, TRUE),
      sown = as.Date("2021-05-01") + sample(0:30, n, TRUE),
      plot_id = seq_len(n),
      notes = paste("plot", seq_len(n)),
      stringsAsFactors = FALSE
    )
    df$yield[c(4L, 30L)] <- NA
    df$soil[7L] <- NA
    df$sown[11L] <- NA
    df
  })
}

null_roles <- function(df) {
  r <- propose_roles(df, detect = FALSE)
  r <- set_role(r, "site", role = "design")
  r <- set_role(r, "rep", role = "design")
  set_role(r, "variety", role = "treatment")
}

test_that("null is the default mode of propose_roles() and mask()", {
  df <- null_fixture()
  r <- propose_roles(df, detect = FALSE)
  expect_identical(attr(r, "mode"), "null")
  m <- mask(df, r, seed = 1L, quiet = TRUE)
  expect_identical(recipe(m)@mode, "null")
  expect_identical(m@mode, "null")
})

test_that("null defaults: design coded or kept, outcomes noise, ids dropped", {
  df <- null_fixture()
  r <- null_roles(df)
  act <- stats::setNames(r$action, r$col)
  expect_identical(unname(act["site"]), "alias")
  expect_identical(unname(act["rep"]), "keep")
  expect_identical(unname(act["variety"]), "alias")
  for (cl in c("yield", "share", "count", "soil", "grade", "wet", "sown")) {
    expect_identical(unname(act[cl]), "noise", info = cl)
  }
  expect_identical(unname(act["plot_id"]), "drop")
  expect_identical(unname(act["notes"]), "drop")
})

test_that("design structure, NA mask and storage classes are exact", {
  df <- null_fixture()
  s <- synthetic(mask(df, null_roles(df), seed = 2L, quiet = TRUE))
  expect_identical(s$rep, df$rep)
  first_seen <- function(x) match(x, unique(x))
  expect_identical(first_seen(s$site), first_seen(df$site))
  expect_identical(first_seen(s$variety), first_seen(df$variety))
  expect_false(any(levels(s$site) %in% levels(df$site)))
  expect_false(any(c("plot_id", "notes") %in% names(s)))
  for (cl in names(s)) {
    expect_identical(is.na(s[[cl]]), is.na(df[[cl]]), info = cl)
    expect_identical(class(s[[cl]]), class(df[[cl]]), info = cl)
  }
})

test_that("summary noise stays in [p1, p99] and keeps the type", {
  df <- null_fixture()
  s <- synthetic(mask(df, null_roles(df), seed = 4L, quiet = TRUE))
  for (cl in c("yield", "share", "count")) {
    q <- stats::quantile(df[[cl]], c(0.01, 0.99), na.rm = TRUE, names = FALSE)
    v <- s[[cl]][!is.na(s[[cl]])]
    expect_true(all(v >= floor(q[1]) & v <= ceiling(q[2])), info = cl)
  }
  expect_type(s$count, "integer")
  expect_true(all(s$share > 0 & s$share < 1))
  expect_true(all(s$yield > 0, na.rm = TRUE))
  sown <- s$sown[!is.na(s$sown)]
  expect_true(all(sown >= min(df$sown, na.rm = TRUE)))
  expect_true(all(sown <= max(df$sown, na.rm = TRUE)))
})

test_that("categorical noise is uniform over coded levels", {
  df <- null_fixture()
  m <- mask(df, null_roles(df), seed = 5L, quiet = TRUE)
  s <- synthetic(m)
  expect_setequal(unique(stats::na.omit(s$soil)), sprintf("soil_L%03d", 1:3))
  expect_identical(levels(s$grade), sprintf("grade_L%03d", 1:4))
  expect_setequal(names(recipe(m)@level_maps$soil), c("clay", "loam", "sand"))
  expect_type(s$wet, "logical")
})

test_that("standard noise draws on fixed scales by type", {
  df <- null_fixture()
  s <- synthetic(mask(
    df, null_roles(df), seed = 6L, noise = "standard", quiet = TRUE
  ))
  expect_true(all(s$share > 0 & s$share < 1))
  expect_true(all(s$yield > 0, na.rm = TRUE))
  expect_type(s$count, "integer")
  expect_true(all(s$count >= 0L))
  sown <- s$sown[!is.na(s$sown)]
  expect_true(all(format(sown, "%Y") == "2000"))
  expect_identical(recipe(mask(
    df, null_roles(df), seed = 6L, noise = "standard", quiet = TRUE
  ))@noise, "standard")
})

test_that("a site-level covariate gets one draw per site", {
  df <- null_fixture()
  df$rain <- c(310, 280, 450)[as.integer(df$site)]
  r <- null_roles(df)
  m <- mask(df, r, seed = 7L, quiet = TRUE)
  s <- synthetic(m)
  per_site <- tapply(s$rain, s$site, function(v) length(unique(v)))
  expect_true(all(per_site == 1L))
})

test_that("null mode refuses a conditional clone", {
  df <- null_fixture()
  expect_error(
    mask(df, null_roles(df), conditional = TRUE, seed = 1L),
    class = "masque_null_conditional_refusal"
  )
})

test_that("noise is refused on design, treatment and id columns", {
  df <- null_fixture()
  r <- null_roles(df)
  for (cl in c("rep", "variety", "plot_id")) {
    expect_error(
      mask(df, set_role(r, cl, action = "noise"), seed = 1L, quiet = TRUE),
      "noise",
      info = cl
    )
  }
})

test_that("an invalid noise argument is refused", {
  df <- null_fixture()
  expect_error(
    mask(df, null_roles(df), noise = "fancy", seed = 1L),
    class = "masque_bad_noise_refusal"
  )
})

test_that("the recipe round-trips labels on a null clone", {
  df <- null_fixture()
  m <- mask(df, null_roles(df), seed = 8L, quiet = TRUE)
  fwd <- apply_recipe(df, recipe(m))
  expect_identical(fwd$variety, synthetic(m)$variety)
  back <- unmask(synthetic(m)$variety, recipe(m), column = "variety")
  expect_identical(as.character(back), as.character(df$variety))
})

test_that("the audit of a null clone finds no HIGH column", {
  df <- null_fixture()
  m <- mask(df, null_roles(df), seed = 9L, quiet = TRUE)
  expect_false(is.null(m@audit))
  expect_false(any(m@audit$leakage_class == "high"))
})

test_that("a local or collaborate roles table can still be used", {
  df <- null_fixture()
  r <- propose_roles(df, mode = "local", detect = FALSE)
  m <- mask(df, r, seed = 1L, quiet = TRUE)
  expect_identical(recipe(m)@mode, "local")
})

test_that("mask_set() links keys but not noise columns in null mode", {
  plots <- data.frame(
    trial_key = rep(c("T1", "T2", "T3"), each = 10L),
    yield = withr::with_seed(1L, round(stats::rnorm(30L, 5), 1)),
    stringsAsFactors = FALSE
  )
  trials <- data.frame(
    trial_key = sprintf("T%d", 1:6),
    yield = c(5.1, 4.9, 5.0, 5.3, 4.7, 5.2),
    stringsAsFactors = FALSE
  )
  # Shared yield values would make yield a link outside null mode.
  expect_gt(length(intersect(plots$yield, trials$yield)), 0L)
  roles <- list(
    plots = set_role(
      propose_roles(plots, detect = FALSE), "trial_key", role = "id",
      action = "alias"
    ),
    trials = set_role(
      propose_roles(trials, detect = FALSE), "trial_key", role = "id",
      action = "alias"
    )
  )
  ms <- mask_set(
    list(plots = plots, trials = trials), roles = roles, seed = 1L,
    quiet = TRUE
  )
  s <- synthetic(ms)
  expect_identical(ms@mode, "null")
  expect_true(all(s$plots$trial_key %in% s$trials$trial_key))
  expect_identical(
    unname(vapply(recipe(ms)@links, `[[`, "", "name")), "trial_key"
  )
})

test_that("non-finite numeric cells are kept in place", {
  df <- null_fixture()
  df$share[c(2L, 9L)] <- c(Inf, -Inf)
  s <- synthetic(mask(df, null_roles(df), seed = 10L, quiet = TRUE))
  expect_identical(s$share[c(2L, 9L)], c(Inf, -Inf))
  expect_true(all(is.finite(s$share[-c(2L, 9L)])))
})

test_that("a numeric noise column in a table under five rows is refused", {
  tiny <- data.frame(
    site = factor(c("A", "B", "C")), rain = c(310, 280, 450),
    zone = c("n", "s", "n"), stringsAsFactors = FALSE
  )
  r <- propose_roles(tiny, detect = FALSE)
  expect_error(
    mask(tiny, r, seed = 1L, quiet = TRUE),
    class = "masque_too_few_rows_refusal"
  )
  # Categorical noise alone discloses nothing and is accepted.
  r2 <- set_role(r, "rain", action = "drop")
  s <- synthetic(mask(tiny, r2, seed = 1L, quiet = TRUE))
  expect_true(all(grepl("^zone_L", s$zone)))
})
