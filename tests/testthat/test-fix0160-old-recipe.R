# Objects as masque 0.15.0 wrote them: the class definition each one carries
# lacks the properties added in 0.16.0, and their attributes are absent.
.age_s7 <- function(x, drop) {
  cls <- attr(x, "S7_class")
  old_cls <- S7::new_class(
    cls@name, package = "masque",
    properties = cls@properties[setdiff(names(cls@properties), drop)]
  )
  for (p in drop) attr(x, p) <- NULL
  attr(x, "S7_class") <- old_cls
  x
}
.age_recipe <- function(rec) .age_s7(rec, c("conform", "events", "grain"))

.old_fixture <- function() {
  withr::with_seed(2L, {
    g <- expand.grid(
      gen = sprintf("G%02d", 1:8), rep = 1:3, trial = sprintf("T%d", 1:4),
      stringsAsFactors = FALSE, KEEP.OUT.ATTRS = FALSE
    )
    g$yield <- round(stats::rnorm(nrow(g), 4, 0.5), 2)
    g$rain <- c(312.4, 287.9, 401.2, 355.6)[match(g$trial, sprintf("T%d", 1:4))]
    g$soil <- c("clay", "loam", "sand", "clay")[match(g$trial, sprintf("T%d", 1:4))]
    g
  })
}

.old_roles <- function(df, mode) {
  r <- suppressWarnings(propose_roles(df, mode = mode, detect = FALSE))
  r <- set_role(r, c("trial", "rep"), role = "design", action = "keep")
  r <- set_role(r, "gen", role = "treatment",
                action = if (mode == "collaborate") "alias" else "keep")
  r <- set_role(r, "yield", role = "outcome", action = "scramble")
  r <- set_role(r, "rain", role = "covariate", action = "scramble")
  set_role(r, "soil", role = "covariate", action = "alias")
}

test_that("a 0.15.0 recipe prints, applies, unmasks, audits and reads back", {
  df <- .old_fixture()
  for (mode in c("local", "collaborate")) {
    m <- suppressWarnings(mask(df, .old_roles(df, mode), mode = mode, seed = 4L))
    rec <- recipe(m)
    expect_true(length(rec@grain) > 0L)
    old <- .age_recipe(rec)
    expect_false(S7::prop_exists(old, "grain"))

    expect_no_error(utils::capture.output(print(old), type = "message"))
    expect_no_error(format(old))
    expect_no_error(utils::capture.output(utils::str(old)))
    expect_identical(apply_recipe(df, old), apply_recipe(df, rec))
    s <- synthetic(m)
    expect_identical(unmask(s, old), unmask(s, rec))

    m_old <- m
    attr(m_old, "recipe") <- old
    expect_no_error(
      a_old <- audit_mask(m_old, original = df, print = FALSE)
    )
    expect_identical(
      a_old$leakage_class,
      audit_mask(m, original = df, print = FALSE)$leakage_class
    )

    path <- withr::local_tempfile(fileext = ".rds")
    saveRDS(old, path)
    back <- read_recipe(path)
    expect_identical(apply_recipe(df, back), apply_recipe(df, rec))
  }
})

test_that("a 0.15.0 recipe bundle prints, applies, unmasks, audits and reads back", {
  df <- .old_fixture()
  sites <- data.frame(
    trial = sprintf("T%d", 1:6), lat_band = rep(c("n", "s"), 3L),
    elev = c(120, 340, 95, 410, 220, 180), stringsAsFactors = FALSE
  )
  tables <- list(plots = df, sites = sites)
  roles <- list(
    plots = .old_roles(df, "collaborate"),
    sites = set_role(
      set_role(propose_roles(sites, mode = "collaborate", detect = FALSE),
               "trial", role = "design", action = "keep"),
      "elev", role = "covariate", action = "scramble"
    )
  )
  ms <- suppressWarnings(
    mask_set(tables, roles = roles, mode = "collaborate", seed = 5L, quiet = TRUE)
  )
  rs <- recipe(ms)
  old <- .age_s7(rs, "info")
  old@recipes <- lapply(rs@recipes, .age_recipe)
  expect_false(S7::prop_exists(old, "info"))

  expect_no_error(utils::capture.output(print(old), type = "message"))
  expect_no_error(format(old))
  expect_identical(apply_recipe(tables, old), apply_recipe(tables, rs))
  syn <- synthetic(ms)
  expect_identical(unmask(syn, old), unmask(syn, rs))

  ms_old <- ms
  attr(ms_old, "recipe") <- old
  expect_no_error(utils::capture.output(print(ms_old), type = "message"))
  expect_no_error(audit_mask(ms_old, print = FALSE))

  path <- withr::local_tempfile(fileext = ".rds")
  saveRDS(old, path)
  expect_identical(apply_recipe(tables, read_recipe(path)),
                   apply_recipe(tables, rs))
})
