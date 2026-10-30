# Below five rows a re-simulated column is the original resampled (F20).

.fx_small <- function(n) {
  set.seed(20)
  data.frame(
    site = sprintf("S%d", seq_len(n)),
    genotype = rep(c("G1", "G2"), length.out = n),
    yield = round(stats::rnorm(n, 4, 0.5), 2),
    stringsAsFactors = FALSE
  )
}

.fx_small_roles <- function(df, mode) {
  r <- suppressWarnings(propose_roles(df, mode = mode, detect = FALSE))
  r <- set_role(r, "site", role = "design", action = "keep")
  r <- set_role(r, "genotype", role = "treatment",
                action = if (mode == "collaborate") "alias" else "keep")
  r <- set_role(r, "yield", role = "outcome", action = "scramble")
  r
}

test_that("collaborate mode refuses a re-simulated column below five rows", {
  for (n in c(1L, 3L, 4L)) {
    df <- .fx_small(n)
    err <- tryCatch(
      suppressWarnings(mask(
        df, .fx_small_roles(df, "collaborate"), mode = "collaborate", seed = 1
      )),
      masque_too_few_rows_refusal = function(e) e
    )
    expect_s3_class(err, "orchestra_refusal")
    expect_match(conditionMessage(err), "yield")
  }
})

test_that("collaborate mode masks five rows", {
  df <- .fx_small(5L)
  expect_no_error(suppressWarnings(mask(
    df, .fx_small_roles(df, "collaborate"), mode = "collaborate", seed = 1
  )))
})

test_that("local mode warns below five rows and masks", {
  for (n in c(1L, 3L, 4L)) {
    df <- .fx_small(n)
    expect_warning(
      m <- mask(df, .fx_small_roles(df, "local"), mode = "local", seed = 1),
      class = "masque_too_few_rows"
    )
    expect_identical(nrow(synthetic(m)), n)
  }
  df <- .fx_small(5L)
  expect_no_warning(
    mask(df, .fx_small_roles(df, "local"), mode = "local", seed = 1),
    class = "masque_too_few_rows"
  )
})

test_that("a small lookup table with nothing re-simulated is not refused", {
  sites <- data.frame(
    site = c("Loxton", "Minnipa", "Roseworthy", "Turretfield"),
    region = c("Riverland", "Eyre", "Mid North", "Mid North"),
    station_id = c(24024L, 18052L, 23122L, 23001L),
    stringsAsFactors = FALSE
  )
  r <- suppressWarnings(propose_roles(sites, mode = "collaborate",
                                      detect = FALSE))
  r <- set_role(r, "site", role = "design", action = "alias")
  r <- set_role(r, "region", role = "covariate", action = "alias")
  r <- set_role(r, "station_id", role = "id", action = "alias")
  m <- suppressWarnings(mask(sites, r, mode = "collaborate", seed = 1))
  expect_identical(nrow(synthetic(m)), 4L)
  expect_false(any(synthetic(m)$site %in% sites$site))
})

test_that("an event spec below five rows is refused in collaborate mode", {
  df <- data.frame(
    arm = c("A", "B", "A", "B"),
    t_ev = c(2.5, 4.1, 3.3, 6.0),
    ev = c(1L, 0L, 1L, 1L)
  )
  r <- suppressWarnings(propose_roles(df, mode = "collaborate", detect = FALSE))
  r <- set_role(r, "arm", role = "treatment", action = "alias")
  r <- set_role(r, c("t_ev", "ev"), role = "outcome", action = "scramble")
  expect_error(
    suppressWarnings(mask(
      df, r, mode = "collaborate", seed = 1,
      events = list(time = "t_ev", status = "ev")
    )),
    class = "masque_too_few_rows_refusal"
  )
})
