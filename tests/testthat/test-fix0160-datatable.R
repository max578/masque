test_that("package code can use data.table's [ with by =", {
  expect_true(isTRUE(get(".datatable.aware", envir = asNamespace("masque"))))
  expect_true(.constant_within(c(1L, 1L, 2L, 2L), c(5, 5, NA, 7)))
  expect_false(.constant_within(c(1L, 1L, 2L, 2L), c(5, 6, 7, 7)))
  expect_true(.constant_within(integer(), numeric()))
})

dt_fixture <- function() {
  set.seed(11)
  data.frame(
    block = factor(rep(1:4, each = 6)),
    trt = factor(rep(letters[1:6], 4)),
    y = rnorm(24),
    x = rnorm(24),
    grp = sample(c("u", "v"), 24, TRUE),
    stringsAsFactors = FALSE
  )
}

test_that("data.frame and data.table inputs give the same clone and round trip", {
  df <- dt_fixture()
  dt <- data.table::as.data.table(df)
  for (mode in c("local", "collaborate")) {
    roles <- propose_roles(df, mode = mode)
    m_df <- suppressWarnings(mask(df, roles, seed = 3L, mode = mode))
    m_dt <- suppressWarnings(mask(dt, roles, seed = 3L, mode = mode))
    expect_s3_class(synthetic(m_df), "data.table")
    expect_identical(synthetic(m_df), synthetic(m_dt))

    for (inp in list(df, dt)) {
      back <- apply_recipe(inp, recipe(m_df))
      expect_s3_class(back, "data.table")
      expect_identical(back, apply_recipe(df, recipe(m_df)))
    }
    s <- synthetic(m_df)
    u_dt <- unmask(s, recipe(m_df))
    u_df <- unmask(as.data.frame(s), recipe(m_df))
    expect_s3_class(u_dt, "data.table")
    expect_identical(as.character(u_dt$trt), as.character(u_df$trt))
    expect_setequal(unique(as.character(u_dt$trt)), levels(df$trt))
  }
})

test_that("a version-1 roles table upgrades as a data.table or a data.frame", {
  v1 <- data.frame(
    col = c("a", "b"), role = c("treatment", "keep"),
    kind = c("factor", "numeric"), mask_levels = c("permute", NA),
    stringsAsFactors = FALSE
  )
  up_df <- .roles_upgrade(v1, "local")
  up_dt <- .roles_upgrade(data.table::as.data.table(v1), "local")
  expect_identical(up_dt$action, up_df$action)
  expect_identical(names(up_dt), names(up_df))
  expect_identical(up_dt$action, c("scramble", "keep"))
})
