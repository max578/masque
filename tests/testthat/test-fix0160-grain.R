# A column constant within a design unit is synthesised once per unit and
# broadcast to the unit's rows, so the clone keeps its grain (F7).

# 6 trials x 3 reps x 20 genotypes, blocks restarted within rep, a trial-level
# numeric (aet) and categorical (soil) covariate.
.fx_met <- function() {
  withr::with_seed(1L, {
    trials <- sprintf("T%d", 1:6)
    gens <- sprintf("G%02d", 1:20)
    g <- expand.grid(
      genotype = gens, rep = 1:3, trial = trials,
      stringsAsFactors = FALSE, KEEP.OUT.ATTRS = FALSE
    )
    g$block <- NA_character_
    for (t in trials) {
      for (r in 1:3) {
        idx <- which(g$trial == t & g$rep == r)
        g$block[idx] <- sprintf("B%d", sample(rep(1:4, each = 5)))
      }
    }
    trial_eff <- c(0.8, -0.5, 0.3, 1.1, -0.2, 0.0)
    gen_eff <- stats::rnorm(20, 0, 0.3)
    rep_eff <- c(0.1, 0, -0.1)
    g$yield <- round(3 + trial_eff[match(g$trial, trials)] +
      gen_eff[match(g$genotype, gens)] + rep_eff[g$rep] +
      stats::rnorm(nrow(g), 0, 0.35), 2)
    g$aet <- c(312.456, 287.901, 401.233, 355.678, 298.112, 376.543)[
      match(g$trial, trials)
    ]
    g$plot_cov <- round(stats::rnorm(nrow(g), 50, 8), 2)
    g$soil <- c("clay", "loam", "sand", "clay", "loam", "sand")[
      match(g$trial, trials)
    ]
    g[, c("trial", "rep", "block", "genotype", "yield", "aet", "plot_cov",
          "soil")]
  })
}

.fx_met_roles <- function(df, mode) {
  collab <- identical(mode, "collaborate")
  r <- suppressWarnings(propose_roles(df, mode = mode, detect = FALSE))
  r <- set_role(r, c("trial", "rep", "block"), role = "design",
                action = "keep")
  r <- set_role(r, "genotype", role = "treatment",
                action = if (collab) "alias" else "keep")
  r <- set_role(r, "yield", role = "outcome", action = "scramble")
  r <- set_role(r, c("aet", "plot_cov"), role = "covariate",
                action = "scramble")
  r <- set_role(r, "soil", role = "covariate",
                action = if (collab) "alias" else "scramble")
  r
}

# 3 sites x 2 years x 2 reps x 8 genotypes; rain is set per site-year, so it is
# constant within neither site nor year alone.
.fx_site_year <- function() {
  withr::with_seed(9L, {
    g <- expand.grid(
      genotype = sprintf("G%d", 1:8), rep = 1:2, year = c(2024L, 2025L),
      site = c("North", "South", "East"),
      stringsAsFactors = FALSE, KEEP.OUT.ATTRS = FALSE
    )
    sy <- paste(g$site, g$year)
    g$rain <- c(410.5, 388.2, 502.7, 455.1, 361.9, 420.4)[
      match(sy, unique(sy))
    ]
    g$yield <- round(stats::rnorm(nrow(g), 3, 0.4), 2)
    g[, c("site", "year", "rep", "genotype", "yield", "rain")]
  })
}

.fx_site_year_roles <- function(df, mode) {
  r <- suppressWarnings(propose_roles(df, mode = mode, detect = FALSE))
  r <- set_role(r, c("site", "year", "rep"), role = "design",
                action = "keep")
  r <- set_role(r, "genotype", role = "treatment", action = "keep")
  r <- set_role(r, "yield", role = "outcome", action = "scramble")
  r <- set_role(r, "rain", role = "covariate", action = "scramble")
  r
}

# Text form of a clone: doubles to 15 significant digits, then the level maps.
.fx_canon <- function(m) {
  syn <- as.data.frame(synthetic(m))
  cols <- vapply(names(syn), function(nm) {
    x <- syn[[nm]]
    v <- if (is.double(x) && !inherits(x, "Date")) {
      sprintf("%.15g", x)
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

.fx_distinct_by <- function(x, g) {
  as.vector(tapply(x, g, function(v) length(unique(v[!is.na(v)]))))
}

# One value per unit, in unit order.
.fx_unit_values <- function(x, g) {
  as.vector(tapply(x, g, function(v) unique(v[!is.na(v)])[1L]))
}

.fx_combos <- list(
  list(mode = "local", cond = FALSE), list(mode = "local", cond = TRUE),
  list(mode = "collaborate", cond = FALSE),
  list(mode = "collaborate", cond = TRUE)
)

# ---- detection -------------------------------------------------------------

test_that("the trial-level columns are found at the trial grain", {
  df <- .fx_met()
  g <- .detect_grain(df, .fx_met_roles(df, "local"))
  expect_length(g, 1L)
  expect_identical(g[[1]]$unit, "trial")
  expect_identical(g[[1]]$cols, c("aet", "soil"))
  expect_identical(g[[1]]$n_units, 6L)
  # The alias action on a categorical covariate is a candidate too.
  g_c <- .detect_grain(df, .fx_met_roles(df, "collaborate"))
  expect_identical(g_c[[1]]$cols, c("aet", "soil"))
})

test_that("a nested design reports the coarsest unit", {
  df <- .fx_met()
  df$block <- paste(df$trial, df$rep, df$block, sep = "-") # unique labels
  g <- .detect_grain(df, .fx_met_roles(df, "local"))
  expect_identical(g[[1]]$unit, "trial")
})

test_that("a crossed site:year covariate is found on the interaction", {
  df <- .fx_site_year()
  roles <- .fx_site_year_roles(df, "local")
  expect_false(all(.fx_distinct_by(df$rain, df$site) <= 1L))
  expect_false(all(.fx_distinct_by(df$rain, df$year) <= 1L))
  g <- .detect_grain(df, roles)
  expect_length(g, 1L)
  expect_identical(g[[1]]$unit, c("site", "year"))
  expect_identical(g[[1]]$cols, "rain")
  expect_identical(g[[1]]$n_units, 6L)
})

test_that("constant columns, unreplicated units and kept columns have no grain", {
  df <- .fx_met()
  df$const <- 7.5
  df$plot <- seq_len(nrow(df))
  roles <- .fx_met_roles(df, "local")
  roles <- set_role(roles, "const", role = "covariate", action = "scramble")
  roles <- set_role(roles, "plot", role = "design", action = "keep")
  roles <- set_role(roles, "soil", action = "keep")
  g <- .detect_grain(df, roles)
  expect_identical(g[[1]]$cols, "aet")
  # A unit with one row per level (plot) is not a grain even though every
  # column is constant within it.
  roles2 <- set_role(roles, c("trial", "rep", "block"), role = "covariate",
                     action = "keep")
  expect_length(.detect_grain(df, roles2), 0L)
})

# ---- synthesis -------------------------------------------------------------

test_that("trial-level columns keep one value per trial in every mode", {
  df <- .fx_met()
  for (cb in .fx_combos) {
    lab <- sprintf("%s cond=%s", cb$mode, cb$cond)
    m <- suppressWarnings(mask(
      df, .fx_met_roles(df, cb$mode), mode = cb$mode, seed = 1,
      conditional = cb$cond
    ))
    syn <- synthetic(m)
    expect_identical(.fx_distinct_by(syn$aet, df$trial), rep(1L, 6), label = lab)
    expect_identical(.fx_distinct_by(syn$soil, df$trial), rep(1L, 6),
                     label = lab)
    # Row-level columns still vary within trial.
    expect_true(all(.fx_distinct_by(syn$plot_cov, df$trial) > 1L), label = lab)
    # Soil's frequencies across trials are the original's.
    expect_identical(
      sort(as.vector(table(.fx_unit_values(syn$soil, df$trial)))),
      sort(as.vector(table(.fx_unit_values(df$soil, df$trial)))),
      label = lab
    )
    # Design columns and the treatment incidence are untouched.
    for (cn in c("trial", "rep", "block")) {
      expect_identical(syn[[cn]], df[[cn]], label = paste(lab, cn))
    }
    first_seen <- function(x) factor(x, levels = unique(x))
    expect_identical(
      unname(unclass(table(first_seen(syn$genotype), syn$trial))),
      unname(unclass(table(first_seen(df$genotype), df$trial))),
      label = lab
    )
    gr <- recipe(m)@grain
    expect_length(gr, 1L)
    expect_identical(gr[[1]]$synthesised, "unit", label = lab)
    expect_identical(gr[[1]]$reason, "", label = lab)
    expect_true(any(grepl("aet, soil synthesised once per trial (6 units)",
                          recipe(m)@warnings, fixed = TRUE)), label = lab)
  }
})

test_that("local unit values are drawn from the original unit values", {
  # Local numeric synthesis returns observed values (type 1 quantiles), so
  # with six units the clone's trial values are the real ones, resampled.
  df <- .fx_met()
  orig <- .fx_unit_values(df$aet, df$trial)
  for (s in 1:5) {
    m <- suppressWarnings(mask(
      df, .fx_met_roles(df, "local"), mode = "local", seed = s
    ))
    vals <- .fx_unit_values(synthetic(m)$aet, df$trial)
    expect_true(all(vals %in% orig))
  }
})

test_that("collaborate unit values are not confined to the original values", {
  df <- .fx_met()
  orig <- .fx_unit_values(df$aet, df$trial)
  m <- suppressWarnings(mask(
    df, .fx_met_roles(df, "collaborate"), mode = "collaborate", seed = 1
  ))
  vals <- .fx_unit_values(synthetic(m)$aet, df$trial)
  expect_lt(mean(vals %in% orig), 1)
  expect_true(all(vals >= min(orig) & vals <= max(orig)))
  expect_identical(recipe(m)@grain[[1]]$n_units, 6L)
  # Soil is aliased after the unit-level permutation.
  expect_false(any(synthetic(m)$soil %in% df$soil))
  expect_identical(names(recipe(m)@level_maps$soil), sort(unique(df$soil)))
})

test_that("the NA mask and an all-missing unit survive", {
  df <- .fx_met()
  df$aet[df$trial == "T6"] <- NA # a unit with no value at all
  df$aet[which(df$trial == "T1")[1:4]] <- NA
  df$soil[which(df$trial == "T2")[1:3]] <- NA
  roles <- .fx_met_roles(df, "collaborate")
  g <- .detect_grain(df, roles)
  expect_identical(g[[1]]$cols, c("aet", "soil"))
  m <- suppressWarnings(mask(df, roles, mode = "collaborate", seed = 2))
  syn <- synthetic(m)
  expect_identical(is.na(syn$aet), is.na(df$aet))
  expect_identical(is.na(syn$soil), is.na(df$soil))
  expect_true(all(.fx_distinct_by(syn$aet, df$trial) <= 1L))
  expect_identical(.fx_distinct_by(syn$aet, df$trial)[6], 0L)
})

test_that("a crossed site:year covariate keeps one value per site-year", {
  df <- .fx_site_year()
  sy <- paste(df$site, df$year)
  for (mode in c("local", "collaborate")) {
    m <- suppressWarnings(mask(
      df, .fx_site_year_roles(df, mode), mode = mode, seed = 3
    ))
    syn <- synthetic(m)
    expect_identical(.fx_distinct_by(syn$rain, sy), rep(1L, 6), label = mode)
    expect_identical(recipe(m)@grain[[1]]$unit, c("site", "year"))
    expect_true(any(grepl("once per site:year", recipe(m)@warnings)))
  }
})

test_that("fewer than five units in collaborate mode fall back to rows", {
  df <- .fx_met()
  df <- df[df$trial %in% c("T1", "T2", "T3", "T4"), ]
  rownames(df) <- NULL
  expect_warning(
    m <- mask(df, .fx_met_roles(df, "collaborate"), mode = "collaborate",
              seed = 1),
    class = "masque_grain_small_units"
  )
  gr <- recipe(m)@grain[[1]]
  expect_identical(gr$synthesised, "row")
  expect_identical(gr$n_units, 4L)
  expect_match(gr$reason, "fewer than 5 units")
  expect_true(any(.fx_distinct_by(synthetic(m)$aet, df$trial) > 1L))
  # Local mode proceeds at unit level and records the count.
  expect_no_warning(
    m_l <- mask(df, .fx_met_roles(df, "local"), mode = "local", seed = 1),
    class = "masque_grain_small_units"
  )
  expect_identical(recipe(m_l)@grain[[1]]$synthesised, "unit")
  expect_identical(recipe(m_l)@grain[[1]]$n_units, 4L)
  expect_identical(.fx_distinct_by(synthetic(m_l)$aet, df$trial), rep(1L, 4))
})

test_that("grain = FALSE is the row-level clone of masque 0.15", {
  # Digests of the same calls on the unmodified 0.16.0 base (12ead24).
  base <- c(
    local_FALSE =
      "65154f4d80860124e54c67e3fcccc934d3757823dac158f5d2dda8ac98764601",
    local_TRUE =
      "789a764980d220b4924e1367dd6e47fe8db31c903d9b02196d5635390a689808",
    collaborate_FALSE =
      "bb8c3fa8180eb32a18887d517ca9e709b5049f8e5306bd6c5b6294b6fbbd2f39",
    collaborate_TRUE =
      "cf60a1627fc0b9aff9c81a6ffa1fe5c733e7605134d9b9ba0bd3e0e804fc106f"
  )
  df <- .fx_met()
  for (cb in .fx_combos) {
    key <- sprintf("%s_%s", cb$mode, cb$cond)
    m <- suppressWarnings(mask(
      df, .fx_met_roles(df, cb$mode), mode = cb$mode, seed = 1L,
      conditional = cb$cond, grain = FALSE
    ))
    gr <- recipe(m)@grain
    expect_identical(gr[[1]]$synthesised, "row", label = key)
    expect_identical(gr[[1]]$reason, "grain = FALSE", label = key)
    skip_on_cran()
    expect_identical(.fx_canon(m), base[[key]], label = key)
  }
})

test_that("grain must be a single TRUE or FALSE", {
  df <- .fx_met()
  roles <- .fx_met_roles(df, "local")
  for (bad in list(NA, "yes", c(TRUE, FALSE), 1)) {
    expect_error(
      suppressWarnings(mask(df, roles, seed = 1, grain = bad)),
      class = "masque_bad_grain_refusal"
    )
  }
})

test_that("a grained clone round-trips through apply_recipe() and unmask()", {
  df <- .fx_met()
  m <- suppressWarnings(mask(
    df, .fx_met_roles(df, "collaborate"), mode = "collaborate", seed = 1
  ))
  rec <- recipe(m)
  fwd <- apply_recipe(df, rec)
  expect_identical(sort(unique(fwd$soil)), sort(unique(synthetic(m)$soil)))
  expect_identical(fwd$aet, df$aet)
  back <- unmask(fwd, rec)
  expect_identical(back$soil, df$soil)
  expect_identical(back$genotype, df$genotype)
})
