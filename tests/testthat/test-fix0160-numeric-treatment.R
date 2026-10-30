# A numeric treatment can be aliased or permuted; collaborate aliases it.

# Split plot after agridat::yates.oats, nitrogen 0-0.6, two missing doses.
.fx_dose <- function() {
  withr::with_seed(11L, {
    g <- expand.grid(
      nitro = c(0, 0.2, 0.4, 0.6), gen = c("Golden", "Marvel", "Victory"),
      block = sprintf("B%d", 1:6),
      stringsAsFactors = FALSE, KEEP.OUT.ATTRS = FALSE
    )
    g$yield <- round(80 + 70 * g$nitro + stats::rnorm(nrow(g), 0, 12), 1)
    g$nitro[c(5L, 40L)] <- NA
    g[, c("block", "gen", "nitro", "yield")]
  })
}

.fx_dose_roles <- function(df, mode, nitro_action = NULL) {
  r <- suppressWarnings(propose_roles(df, mode = mode, detect = FALSE))
  r <- set_role(r, "block", role = "design", action = "keep")
  r <- set_role(r, "gen", role = "treatment")
  r <- set_role(r, "nitro", role = "treatment", action = nitro_action)
  set_role(r, "yield", role = "outcome", action = "scramble")
}

.fx_same_partition <- function(a, b) {
  identical(
    masque:::.row_group_id(list(a)), masque:::.row_group_id(list(b))
  )
}

test_that("a numeric treatment accepts alias and scramble", {
  df <- .fx_dose()
  for (a in c("alias", "scramble")) {
    r <- .fx_dose_roles(df, "collaborate", nitro_action = a)
    expect_no_error(roles_validate(r, df, mode = "collaborate"))
  }
  opts <- role_options(kind = "numeric")
  expect_true(all(
    c("keep", "scramble", "alias", "drop") %in%
      opts$action[opts$role == "treatment"]
  ))
})

test_that("collaborate aliases a numeric treatment by default, local keeps", {
  expect_identical(
    masque:::.default_action("treatment", "numeric", "collaborate"), "alias"
  )
  expect_identical(
    masque:::.default_action("treatment", "integer", "collaborate"), "alias"
  )
  expect_identical(
    masque:::.default_action("treatment", "numeric", "local"), "keep"
  )
  df <- .fx_dose()
  expect_identical(
    .fx_dose_roles(df, "collaborate")$action[3L], "alias"
  )
  expect_identical(.fx_dose_roles(df, "local")$action[3L], "keep")
})

test_that("the default collaborate clone of a dose trial is not blocked", {
  df <- .fx_dose()
  r <- .fx_dose_roles(df, "collaborate")
  expect_no_warning(
    m <- mask(df, r, mode = "collaborate", seed = 3),
    class = "masque_high_leakage"
  )
  a <- m@audit
  expect_identical(a$leakage_class[a$col == "nitro"], "low")
  expect_identical(a$alias_status[a$col == "nitro"], "aliased")

  s <- synthetic(m)
  expect_type(s$nitro, "character")
  expect_true(all(grepl("^nitro_trt_[0-9]{3}$", s$nitro[!is.na(s$nitro)])))
  expect_false(any(stats::na.omit(s$nitro) %in% as.character(df$nitro)))
  expect_identical(is.na(s$nitro), is.na(df$nitro))
  expect_true(.fx_same_partition(s$nitro, df$nitro))
  expect_true(.fx_same_partition(
    paste(s$block, s$nitro), paste(df$block, df$nitro)
  ))
  expect_identical(s$block, df$block)
})

test_that("an aliased numeric treatment round-trips to its type and values", {
  df <- .fx_dose()
  m <- mask(df, .fx_dose_roles(df, "collaborate"), mode = "collaborate",
            seed = 3)
  back <- unmask(synthetic(m), recipe(m))
  expect_type(back$nitro, "double")
  expect_identical(back$nitro, df$nitro)
  fwd <- apply_recipe(df, recipe(m))
  expect_identical(fwd$nitro, synthetic(m)$nitro)
  expect_identical(
    unmask(synthetic(m)$nitro, recipe(m), column = "nitro"), df$nitro
  )
})

test_that("integer and binary-inexact doses round-trip exactly", {
  df <- .fx_dose()
  df$nrate <- as.integer(round(df$nitro * 100))
  df$frac <- df$nitro + 0.1 + 0.2
  r <- .fx_dose_roles(df, "collaborate")
  r <- set_role(r, c("nrate", "frac"), role = "treatment")
  m <- mask(df, r, mode = "collaborate", seed = 5)
  back <- unmask(synthetic(m), recipe(m))
  expect_type(back$nrate, "integer")
  expect_identical(back$nrate, df$nrate)
  expect_identical(back$frac, df$frac)
  expect_identical(apply_recipe(df, recipe(m))$frac, synthetic(m)$frac)
})

test_that("a permuted numeric treatment stays numeric and round-trips", {
  df <- .fx_dose()
  r <- .fx_dose_roles(df, "local", nitro_action = "scramble")
  m <- mask(df, r, mode = "local", seed = 7)
  s <- synthetic(m)
  expect_type(s$nitro, "double")
  expect_setequal(unique(stats::na.omit(s$nitro)), c(0, 0.2, 0.4, 0.6))
  expect_false(identical(s$nitro, df$nitro))
  expect_identical(is.na(s$nitro), is.na(df$nitro))
  expect_true(.fx_same_partition(s$nitro, df$nitro))
  expect_identical(unmask(s, recipe(m))$nitro, df$nitro)
  expect_identical(apply_recipe(df, recipe(m))$nitro, s$nitro)
})

test_that("a kept numeric treatment in collaborate still audits HIGH", {
  df <- .fx_dose()
  r <- .fx_dose_roles(df, "collaborate", nitro_action = "keep")
  expect_warning(
    m <- mask(df, r, mode = "collaborate", seed = 3),
    class = "masque_high_leakage"
  )
  expect_identical(m@audit$leakage_class[m@audit$col == "nitro"], "high")
})
