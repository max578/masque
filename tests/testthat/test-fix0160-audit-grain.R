# Grained and whole-valued numeric columns are graded on excess over chance.

# 8 trials; sowing day and rain per trial, a narrow whole-valued age per row.
.fx_ag <- function() {
  withr::with_seed(3L, {
    trials <- sprintf("T%d", 1:8)
    g <- expand.grid(
      gen = sprintf("G%02d", 1:10), rep = 1:3, trial = trials,
      stringsAsFactors = FALSE, KEEP.OUT.ATTRS = FALSE
    )
    g$yield <- round(stats::rnorm(nrow(g), 3, 0.5), 2)
    g$sow_day <- c(120, 124, 120, 131, 124, 118, 131, 120)[
      match(g$trial, trials)
    ]
    g$rain <- c(312.4, 287.9, 401.2, 355.6, 298.1, 376.5, 330.2, 344.4)[
      match(g$trial, trials)
    ]
    g$age <- sample(18:26, nrow(g), replace = TRUE)
    g
  })
}

.fx_ag_roles <- function(df) {
  r <- suppressWarnings(propose_roles(df, mode = "collaborate", detect = FALSE))
  r <- set_role(r, c("trial", "rep"), role = "design", action = "keep")
  r <- set_role(r, "gen", role = "treatment", action = "alias")
  r <- set_role(r, "yield", role = "outcome", action = "scramble")
  set_role(r, c("sow_day", "rain", "age"), role = "covariate",
           action = "scramble")
}

test_that("ordinary clones of grained and whole-valued columns audit low", {
  df <- .fx_ag()
  r <- .fx_ag_roles(df)
  for (s in 1:5) {
    m <- suppressWarnings(mask(df, r, mode = "collaborate", seed = s))
    a <- m@audit
    for (cl in c("sow_day", "rain", "age")) {
      expect_identical(a$leakage_class[a$col == cl], "low", label = cl)
      expect_false(is.na(a$excess_pct[a$col == cl]))
    }
  }
})

test_that("a leaky grained or whole-valued column is still flagged", {
  df <- .fx_ag()
  m <- suppressWarnings(mask(df, .fx_ag_roles(df), mode = "collaborate",
                             seed = 1))
  for (cl in c("sow_day", "age")) {
    leak <- synthetic(m)
    leak[[cl]] <- df[[cl]]
    a <- masque:::.compute_audit(
      data.table::as.data.table(df), leak, recipe(m), "collaborate"
    )
    expect_identical(a$leakage_class[a$col == cl], "medium", label = cl)
  }

  # As the only content column, the leak is a table-level HIGH.
  df2 <- df[, c("trial", "rep", "gen", "sow_day")]
  r2 <- .fx_ag_roles(df)[c(1:3, 5), ]
  m2 <- suppressWarnings(mask(df2, r2, mode = "collaborate", seed = 1))
  leak <- synthetic(m2)
  leak$sow_day <- df2$sow_day
  a2 <- masque:::.compute_audit(
    data.table::as.data.table(df2), leak, recipe(m2), "collaborate"
  )
  expect_identical(a2$leakage_class[a2$col == "sow_day"], "medium")
  expect_true("high" %in% attr(a2, "joint")$leakage_class)
})

test_that("a grain that fell back to row synthesis is noted in the audit", {
  df <- .fx_ag()
  df <- df[df$trial %in% c("T1", "T2", "T3", "T4"), ]
  r <- .fx_ag_roles(df)
  m <- suppressWarnings(mask(df, r, mode = "collaborate", seed = 1))
  expect_identical(recipe(m)@grain[[1]]$synthesised, "row")
  a <- m@audit
  for (cl in recipe(m)@grain[[1]]$cols) {
    expect_match(
      a$notes[a$col == cl], "synthesised row by row", label = cl
    )
  }
  expect_false(grepl("row by row", a$notes[a$col == "yield"]))
})
