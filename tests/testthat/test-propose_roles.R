test_that("propose_roles returns a tibble with the expected schema", {
  r <- propose_roles(iris)
  expect_s3_class(r, "tbl_df")
  expect_named(r, c(
    "col", "role", "kind", "freq_or_range", "pii_suspected", "notes"
  ))
  expect_equal(nrow(r), ncol(iris))
  expect_equal(r$col, names(iris))
  expect_true(all(
    r$role %in% c("design", "treatment", "outcome", "covariate", "ignore")
  ))
})

test_that("propose_roles(detect = FALSE) classifies iris by name (v0.2)", {
  r <- propose_roles(iris, detect = FALSE)
  numeric_cols <- c(
    "Sepal.Length", "Sepal.Width", "Petal.Length", "Petal.Width"
  )
  expect_true(all(r$role[r$col %in% numeric_cols] == "covariate"))
  # Species: factor, no treatment name
  expect_true(r$role[r$col == "Species"] == "covariate")
  expect_false(any(r$pii_suspected))
  expect_null(attr(r, "design"))
})

test_that("propose_roles(detect = TRUE) overlays design hints (default)", {
  r <- propose_roles(iris)
  # Species has 3 levels balanced 50/50/50 -> looks like CRD treatment.
  expect_equal(r$role[r$col == "Species"], "treatment")
  expect_match(r$notes[r$col == "Species"], "detect_design")
  ds <- attr(r, "design")
  expect_true(inherits(ds, "masque::design_summary"))
  expect_equal(ds@class_label, "CRD")
})

test_that("propose_roles classifies mtcars (all numeric -> covariate)", {
  r <- propose_roles(mtcars)
  expect_true(all(r$role == "covariate"))
  expect_true(all(r$kind %in% c("numeric", "integer")))
  # mtcars has no design structure -> detect_design returns "none".
  ds <- attr(r, "design")
  expect_equal(ds@class_label, "none")
})

test_that("propose_roles errors on non-data-frame input", {
  expect_error(propose_roles(1:10), "must be a data frame")
  expect_error(propose_roles(list()), "must be a data frame")
})

test_that("propose_roles errors on zero-column data frame", {
  expect_error(propose_roles(data.frame()), "no columns")
})

# Pattern-matching coverage --------------------------------------------------

test_that("PII patterns flag obvious cases and set role = ignore", {
  df <- data.frame(
    contact_name = c("a", "b"),
    email_addr = c("x@y", "z@w"),
    gps_lat = c(1.0, 2.0),
    farmer = c("Alice", "Bob"),
    yield = c(2.3, 4.1),
    stringsAsFactors = FALSE
  )
  r <- propose_roles(df)
  pii_cols <- r$col[r$pii_suspected]
  expect_setequal(
    pii_cols, c("contact_name", "email_addr", "gps_lat", "farmer")
  )
  expect_true(all(r$role[r$pii_suspected] == "ignore"))
  expect_equal(r$role[r$col == "yield"], "covariate")
})

test_that("Design patterns assign role = design (case-insensitive)", {
  df <- data.frame(
    Rep = 1:4,
    BLOCK = 1:4,
    Row = 1:4,
    col = 1:4,
    site = c("A", "B", "A", "B"),
    year = c(2020, 2021, 2020, 2021),
    plot = 1:4,
    yield = c(1, 2, 3, 4),
    stringsAsFactors = FALSE
  )
  # detect = FALSE: this test exercises the name-pattern logic only.
  # With detect on, a 4-row toy frame is too small for design detection
  # to fire meaningfully (and small toys can give surprising structural
  # matches).
  r <- propose_roles(df, detect = FALSE)
  design_cols <- r$col[r$role == "design"]
  expect_setequal(
    design_cols, c("Rep", "BLOCK", "Row", "col", "site", "year", "plot")
  )
  expect_equal(r$role[r$col == "yield"], "covariate")
})

test_that("Treatment patterns assign role = treatment", {
  df <- data.frame(
    Genotype = factor(c("A", "B", "A", "B")),
    variety = factor(c("X", "Y", "X", "Y")),
    cultivar = factor(c("C1", "C2", "C1", "C2")),
    trt_code = factor(c("t1", "t2", "t1", "t2")),
    yield = c(1, 2, 3, 4),
    stringsAsFactors = FALSE
  )
  r <- propose_roles(df)
  treat_cols <- r$col[r$role == "treatment"]
  expect_setequal(treat_cols, c("Genotype", "variety", "cultivar", "trt_code"))
})

test_that("ID patterns assign role = ignore", {
  df <- data.frame(
    id = 1:5,
    plot_id = 1:5,
    id_local = 1:5,
    something = 1:5,
    yield = c(1, 2, 3, 4, 5),
    stringsAsFactors = FALSE
  )
  r <- propose_roles(df)
  expect_equal(r$role[r$col == "id"], "ignore")
  expect_equal(r$role[r$col == "plot_id"], "ignore")
  expect_equal(r$role[r$col == "id_local"], "ignore")
  # `something` is numeric -> covariate; `yield` is covariate too
  expect_equal(r$role[r$col == "something"], "covariate")
})

test_that("Date and POSIXct columns default to ignore", {
  df <- data.frame(
    sowing_date = as.Date(c("2026-01-01", "2026-01-02", "2026-01-03")),
    measured_at = as.POSIXct(c(
      "2026-01-01 10:00", "2026-01-01 11:00", "2026-01-01 12:00"
    )),
    yield = c(1.0, 2.0, 3.0),
    stringsAsFactors = FALSE
  )
  r <- propose_roles(df)
  expect_equal(r$role[r$col == "sowing_date"], "ignore")
  expect_equal(r$role[r$col == "measured_at"], "ignore")
  expect_equal(r$kind[r$col == "sowing_date"], "date")
  expect_equal(r$kind[r$col == "measured_at"], "datetime")
})

test_that("Free-text character columns default to ignore", {
  df <- data.frame(
    notes = paste0("note_", 1:50), # 50 unique values in 50 rows -> 100% unique
    # low cardinality, so a covariate
    region = sample(c("east", "west"), 50, replace = TRUE),
    yield = rnorm(50),
    stringsAsFactors = FALSE
  )
  # detect = FALSE: this test exercises the free-text ignore logic, not
  # structural detection (which might pick `region` as a treatment).
  r <- propose_roles(df, detect = FALSE)
  expect_equal(r$role[r$col == "notes"], "ignore")
  expect_equal(r$role[r$col == "region"], "covariate")
})

# `kind` summary -------------------------------------------------------------

test_that("freq_or_range is informative", {
  df <- data.frame(
    x_num = c(1.1, 2.2, 3.3),
    x_int = 1:3,
    x_fac = factor(c("a", "b", "a")),
    x_chr = c("alpha", "beta", "gamma"),
    x_logi = c(TRUE, FALSE, TRUE),
    x_date = as.Date(c("2026-01-01", "2026-01-02", "2026-01-03")),
    stringsAsFactors = FALSE
  )
  r <- propose_roles(df)
  expect_match(r$freq_or_range[r$col == "x_num"], "^\\[1\\.1, 3\\.3\\]$")
  expect_match(r$freq_or_range[r$col == "x_int"], "^\\[1, 3\\]$")
  expect_equal(r$freq_or_range[r$col == "x_fac"], "n=2 levels")
  expect_match(r$freq_or_range[r$col == "x_chr"], "^n=3 unique$")
  expect_match(r$freq_or_range[r$col == "x_logi"], "TRUE")
  expect_match(r$freq_or_range[r$col == "x_date"], "2026-01-01")
})

# Real MET fixtures (workspace-root .fst files; skipped under R CMD check) ----

test_that("propose_roles handles MET tab_04 (skip if .fst fixture absent)", {
  skip_on_cran()
  skip_if_not_installed("fst")
  fpath <- normalizePath("../../../fst_00_dataset_tab_04.fst", mustWork = FALSE)
  skip_if_not(
    file.exists(fpath),
    sprintf("Local-only MET fixture not at %s", fpath)
  )

  df <- fst::read_fst(fpath, as.data.table = FALSE)
  r <- propose_roles(df)

  expect_equal(nrow(r), ncol(df))
  expect_true("design" %in% r$role)
  expect_true("treatment" %in% r$role)
  expect_true(any(r$pii_suspected))
  expect_equal(r$role[r$col == "M_CONTACT"], "ignore")
  expect_true(r$pii_suspected[r$col == "M_CONTACT"])
  expect_equal(r$role[r$col == "M_GPS_S"], "ignore")
  expect_true(r$pii_suspected[r$col == "M_GPS_S"])
  expect_equal(r$role[r$col == "Sowing_Date"], "ignore")
  expect_equal(r$role[r$col == "Rep"], "design")
  expect_equal(r$role[r$col == "Row"], "design")
  expect_equal(r$role[r$col == "Genotype"], "treatment")
})

test_that("propose_roles handles MET tab_07 (skip if .fst fixture absent)", {
  skip_on_cran()
  skip_if_not_installed("fst")
  fpath <- normalizePath("../../../fst_00_dataset_tab_07.fst", mustWork = FALSE)
  skip_if_not(
    file.exists(fpath),
    sprintf("Local-only MET fixture not at %s", fpath)
  )

  df <- fst::read_fst(fpath, as.data.table = FALSE)
  r <- propose_roles(df)

  expect_equal(nrow(r), ncol(df))
  expect_true("design" %in% r$role)
  expect_true("treatment" %in% r$role)
  expect_equal(r$role[r$col == "VARIETY"], "treatment")
  expect_equal(r$role[r$col == "REP"], "design")
  expect_equal(r$role[r$col == "SITE"], "design")
  expect_equal(r$role[r$col == "YEAR"], "design")
})
