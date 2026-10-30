# Sets whose headers need legalising: guided proposals, roles keyed either way,
# and the per-table cleaning record that makes the set round-trip.

names_set <- function() {
  set.seed(11)
  sites <- c("Roseworthy", "Minnipa", "Hart", "Loxton", "Turretfield", "Yanco")
  gens <- c("Scope", "Compass", "Spartacus", "Trojan")
  g <- expand.grid(
    Genotype = gens, Rep = 1:2, site = sites,
    stringsAsFactors = FALSE, KEEP.OUT.ATTRS = FALSE
  )
  trial <- data.frame(
    g$site, g$Genotype, g$Rep, round(3 + stats::rnorm(nrow(g), 0, 0.4), 2),
    stringsAsFactors = FALSE
  )
  names(trial) <- c("Site Name", "Genotype", "Rep", "Yield (t/ha)")
  site_tab <- data.frame(
    sites, round(stats::runif(6, 300, 600)), stringsAsFactors = FALSE
  )
  names(site_tab) <- c("Site Name", "Rainfall (mm)")
  list(trial = trial, sites = site_tab)
}

# Roles set explicitly. `key` maps a header to the name the roles use.
names_roles <- function(tabs, mode, key = identity) {
  rt <- propose_roles(tabs$trial, mode = mode, detect = FALSE)
  rt <- set_role(rt, key("Site Name"), role = "design")
  rt <- set_role(rt, key("Genotype"), role = "treatment")
  rt <- set_role(rt, key("Rep"), role = "design")
  rt <- set_role(rt, key("Yield (t/ha)"), role = "outcome")
  rs <- propose_roles(tabs$sites, mode = mode, detect = FALSE)
  rs <- set_role(rs, key("Site Name"), role = "design")
  rs <- set_role(rs, key("Rainfall (mm)"), role = "covariate")
  list(trial = rt, sites = rs)
}

no_repair_warning <- function(expr) {
  withCallingHandlers(
    expr,
    masque_name_repaired = function(w) invokeRestart("muffleWarning")
  )
}

clean_names_of <- function(tabs) {
  lapply(tabs, function(t) no_repair_warning(clean_table(t, quiet = TRUE))$data)
}

write_names_workbook <- function(tabs) {
  path <- file.path(withr::local_tempdir(.local_envir = parent.frame()),
                    "trials.xlsx")
  writexl::write_xlsx(tabs, path = path)
  path
}

write_names_folder <- function(tabs) {
  d <- withr::local_tempdir(.local_envir = parent.frame())
  for (nm in names(tabs)) {
    data.table::fwrite(tabs[[nm]], file.path(d, paste0(nm, ".csv")))
  }
  d
}

test_that("guided masque() on a workbook with illegal headers masks it", {
  skip_if_not_installed("writexl")
  skip_if_not_installed("readxl")
  path <- write_names_workbook(names_set())
  for (mode in c("local", "collaborate")) {
    m <- no_repair_warning(
      masque(path, mode = mode, seed = 1, ask = FALSE, quiet = TRUE)
    )
    expect_true(S7::S7_inherits(m, masque_set), info = mode)
    expect_true(
      all(c("Site.Name", "Yield..t.ha.") %in% names(synthetic(m)$trial)),
      info = mode
    )
  }
})

test_that("guided masque() on a folder with illegal headers masks it", {
  d <- write_names_folder(names_set())
  for (mode in c("local", "collaborate")) {
    m <- no_repair_warning(
      masque(d, mode = mode, seed = 1, ask = FALSE, quiet = TRUE)
    )
    expect_true(S7::S7_inherits(m, masque_set), info = mode)
    expect_true(
      all(c("Site.Name", "Rainfall..mm.") %in% names(synthetic(m)$sites)),
      info = mode
    )
  }
})

test_that("roles keyed by the original headers work on every set path", {
  skip_if_not_installed("writexl")
  skip_if_not_installed("readxl")
  tabs <- names_set()
  path <- write_names_workbook(tabs)
  d <- write_names_folder(tabs)
  for (mode in c("local", "collaborate")) {
    roles <- names_roles(tabs, mode)
    m1 <- no_repair_warning(
      mask_set(tabs, roles = roles, mode = mode, seed = 1, quiet = TRUE)
    )
    m2 <- no_repair_warning(
      masque(path, roles = roles, mode = mode, seed = 1, quiet = TRUE)
    )
    m3 <- no_repair_warning(
      masque(d, roles = roles, mode = mode, seed = 1, quiet = TRUE)
    )
    for (m in list(m1, m2, m3)) {
      expect_named(
        synthetic(m)$trial, c("Site.Name", "Genotype", "Rep", "Yield..t.ha."),
        info = mode
      )
      rec <- recipe(m)@recipes$trial
      expect_equal(
        rec@roles$role[match(c("Genotype", "Yield..t.ha."), rec@roles$col)],
        c("treatment", "outcome"),
        info = mode
      )
    }
  }
})

test_that("roles keyed by the legalised names keep working", {
  tabs <- names_set()
  for (mode in c("local", "collaborate")) {
    roles <- names_roles(clean_names_of(tabs), mode, key = make.names)
    m <- no_repair_warning(
      mask_set(tabs, roles = roles, mode = mode, seed = 1, quiet = TRUE)
    )
    expect_named(
      synthetic(m)$trial, c("Site.Name", "Genotype", "Rep", "Yield..t.ha."),
      info = mode
    )
  }
})

collision_set <- function() {
  set.seed(5)
  a <- data.frame(
    rep(c("north", "south", "east"), each = 6),
    rep(c("x1", "x2", "x3"), 6),
    round(stats::rnorm(18, 4, 1), 2),
    stringsAsFactors = FALSE
  )
  names(a) <- c("Site Name", "Site.Name", "Yield")
  b <- data.frame(
    c("north", "south", "east", "north", "south", "east"),
    round(stats::runif(6, 1, 9), 1),
    stringsAsFactors = FALSE
  )
  names(b) <- c("Site Name", "depth")
  list(a = a, b = b)
}

test_that("Site Name beside Site.Name legalises without a duplicate", {
  tabs <- collision_set()
  cleaned <- clean_names_of(tabs)
  expect_named(cleaned$a, c("Site.Name", "Site.Name_1", "Yield"))

  roles_orig <- lapply(tabs, propose_roles, mode = "local", detect = FALSE)
  roles_clean <- lapply(cleaned, propose_roles, mode = "local", detect = FALSE)
  for (roles in list(roles_orig, roles_clean)) {
    m <- no_repair_warning(
      mask_set(tabs, roles = roles, mode = "local", seed = 1, quiet = TRUE)
    )
    expect_named(synthetic(m)$a, c("Site.Name", "Site.Name_1", "Yield"))
    back <- unmask(synthetic(m), recipe(m))
    expect_named(back$a, names(tabs$a))
  }

  # The single-table verb accepts both keyings too.
  for (r in list(roles_orig$a, roles_clean$a)) {
    m1 <- no_repair_warning(mask(tabs$a, r, mode = "local", seed = 1))
    expect_named(synthetic(m1), c("Site.Name", "Site.Name_1", "Yield"))
  }

  # The guided path proposes on the cleaned names.
  mg <- no_repair_warning(
    masque(tabs, mode = "local", seed = 1, ask = FALSE, quiet = TRUE)
  )
  expect_named(synthetic(mg)$a, c("Site.Name", "Site.Name_1", "Yield"))
})

test_that("each set recipe carries its cleaning record and round-trips", {
  tabs <- names_set()
  for (mode in c("local", "collaborate")) {
    roles <- names_roles(tabs, mode)
    m <- no_repair_warning(
      mask_set(tabs, roles = roles, mode = mode, seed = 1, quiet = TRUE)
    )
    rec <- recipe(m)
    expect_false(is.null(rec@recipes$trial@cleaning), info = mode)
    expect_equal(
      rec@recipes$trial@cleaning$name_map,
      c("Site Name" = "Site.Name", "Yield (t/ha)" = "Yield..t.ha."),
      info = mode
    )

    # Forward on the raw tables lands in the synthetic namespace.
    fwd <- apply_recipe(tabs, rec)
    for (nm in names(tabs)) {
      expect_identical(names(fwd[[nm]]), names(synthetic(m)[[nm]]), info = mode)
    }

    # Back from the clone restores the original headers.
    back <- unmask(synthetic(m), rec)
    for (nm in names(tabs)) {
      expect_identical(names(back[[nm]]), names(tabs[[nm]]), info = mode)
    }

    # Forward then back reproduces the original, column by column.
    rt <- unmask(fwd, rec)
    for (nm in names(tabs)) {
      for (col in names(tabs[[nm]])) {
        expect_identical(
          as.character(rt[[nm]][[col]]), as.character(tabs[[nm]][[col]]),
          info = paste(mode, nm, col)
        )
      }
    }

    # The set round trip matches the single-table one for the same table.
    m1 <- no_repair_warning(
      mask(tabs$sites, roles$sites, mode = mode, seed = 1)
    )
    expect_identical(
      names(apply_recipe(tabs$sites, recipe(m1))), names(fwd$sites),
      info = mode
    )
    expect_identical(
      names(unmask(synthetic(m1), recipe(m1))), names(back$sites),
      info = mode
    )
  }
})
