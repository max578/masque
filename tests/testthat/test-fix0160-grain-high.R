# A grained or whole-valued column that leaks grades HIGH on its own row.

# 8 trials x 3 reps x 10 genotypes; sow_day and rain per trial, count per row.
.fx_gh <- function() {
  withr::with_seed(3L, {
    trials <- sprintf("T%d", 1:8)
    g <- expand.grid(
      gen = sprintf("G%02d", 1:10), rep = 1:3, trial = trials,
      stringsAsFactors = FALSE, KEEP.OUT.ATTRS = FALSE
    )
    g$yield <- round(stats::rnorm(nrow(g), 3, 0.5), 2)
    g$count <- stats::rpois(nrow(g), 4)
    g$sow_day <- c(120, 124, 120, 131, 124, 118, 131, 120)[
      match(g$trial, trials)
    ]
    g$rain <- c(312.4, 287.9, 401.2, 355.6, 298.1, 376.5, 330.2, 344.4)[
      match(g$trial, trials)
    ]
    g
  })
}

.fx_gh_mask <- function(df, seed = 1L) {
  r <- suppressWarnings(propose_roles(df, mode = "collaborate", detect = FALSE))
  r <- set_role(r, c("trial", "rep"), role = "design", action = "keep")
  r <- set_role(r, "gen", role = "treatment", action = "alias")
  r <- set_role(r, c("yield", "count"), role = "outcome", action = "scramble")
  r <- set_role(r, c("sow_day", "rain"), role = "covariate",
                action = "scramble")
  suppressWarnings(mask(df, r, mode = "collaborate", seed = seed))
}

.gh_audit <- function(df, clone, m) {
  masque:::.compute_audit(
    data.table::as.data.table(df), clone, recipe(m), "collaborate"
  )
}

.gh_class <- function(a, col) a$leakage_class[a$col == col]

test_that("ordinary clones never grade a grained or count column HIGH", {
  df <- .fx_gh()
  for (s in 1:10) {
    a <- .fx_gh_mask(df, s)@audit
    for (cl in c("sow_day", "rain", "count")) {
      expect_identical(.gh_class(a, cl), "low", label = paste(cl, s))
      expect_false(is.na(a$excess_pct[a$col == cl]))
    }
  }
})

test_that("a grained column copied from the real units is HIGH", {
  df <- .fx_gh()
  m <- .fx_gh_mask(df)
  for (cl in c("sow_day", "rain")) {
    leak <- data.table::copy(synthetic(m))
    data.table::set(leak, j = cl, value = df[[cl]])
    a <- .gh_audit(df, leak, m)
    expect_identical(.gh_class(a, cl), "high", label = cl)
  }
})

test_that("real unit values moved to other units are HIGH", {
  df <- .fx_gh()
  m <- .fx_gh_mask(df)
  trials <- unique(df$trial)
  real <- df$rain[match(trials, df$trial)]
  moved <- real[c(2:8, 1L)][match(df$trial, trials)]
  leak <- data.table::copy(synthetic(m))
  data.table::set(leak, j = "rain", value = moved)
  a <- .gh_audit(df, leak, m)
  expect_identical(.gh_class(a, "rain"), "high")
  expect_match(a$notes[a$col == "rain"], "8 of 8 unit values are real")
})

test_that("a whole-valued outcome is graded on excess, and a copy is HIGH", {
  df <- .fx_gh()
  m <- .fx_gh_mask(df)
  expect_false(grepl("exact-match", m@audit$notes[m@audit$col == "count"]))
  leak <- data.table::copy(synthetic(m))
  data.table::set(leak, j = "count", value = df$count)
  a <- .gh_audit(df, leak, m)
  expect_identical(.gh_class(a, "count"), "high")
})

test_that("a grained categorical column copied into alias space is HIGH", {
  df <- withr::with_seed(4L, {
    g <- expand.grid(gen = sprintf("G%d", 1:6), rep = 1:2,
                     trial = sprintf("T%02d", 1:20), stringsAsFactors = FALSE,
                     KEEP.OUT.ATTRS = FALSE)
    g$yield <- round(stats::rnorm(nrow(g), 3, 0.5), 2)
    g$soil <- sample(c("clay", "loam", "sand"), 20, TRUE)[
      match(g$trial, unique(g$trial))
    ]
    g
  })
  r <- suppressWarnings(propose_roles(df, mode = "collaborate", detect = FALSE))
  r <- set_role(r, c("trial", "rep"), role = "design", action = "keep")
  r <- set_role(r, "gen", role = "treatment", action = "alias")
  r <- set_role(r, "yield", role = "outcome", action = "scramble")
  r <- set_role(r, "soil", role = "covariate", action = "alias")
  for (s in 1:5) {
    m <- suppressWarnings(mask(df, r, mode = "collaborate", seed = s))
    expect_false(.gh_class(m@audit, "soil") == "high")
  }
  map <- recipe(m)@level_maps$soil
  leak <- data.table::copy(synthetic(m))
  data.table::set(leak, j = "soil", value = unname(map[df$soil]))
  expect_identical(.gh_class(.gh_audit(df, leak, m), "soil"), "high")
})
