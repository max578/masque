# Summed gaps may not run past the longest observed follow-up of a status
# pattern; only the final time is capped, so no tie is invented (F12).

# Progression then death, censored at most at 24: 300 rows, two arms.
.fx_pfs <- function() {
  withr::with_seed(7L, {
    n <- 300L
    arm <- sample(rep(c("A", "B"), each = n / 2))
    age <- round(stats::rnorm(n, 60, 10))
    t_d <- stats::rexp(n, rate = ifelse(arm == "A", 0.10, 0.07))
    t_p <- stats::rexp(n, rate = ifelse(arm == "A", 0.15, 0.10))
    cens <- stats::runif(n, 2, 24)
    time_death <- round(pmin(t_d, cens), 2)
    died <- as.integer(t_d <= cens)
    time_prog <- round(pmin(t_p, time_death), 2)
    prog <- as.integer(t_p <= time_death)
    data.frame(
      arm = arm, age = age, time_prog = time_prog, prog = prog,
      time_death = time_death, died = died, stringsAsFactors = FALSE
    )
  })
}

.fx_pfs_roles <- function(df, mode) {
  r <- suppressWarnings(propose_roles(df, mode = mode, detect = FALSE))
  r <- set_role(r, "arm", role = "treatment",
                action = if (mode == "collaborate") "alias" else "keep")
  r <- set_role(r, "age", role = "covariate", action = "scramble")
  r <- set_role(r, c("time_prog", "prog", "time_death", "died"),
                role = "outcome", action = "scramble")
  r
}

.fx_pfs_spec <- list(list(
  time = c("time_prog", "time_death"), status = c("prog", "died")
))

.fx_pfs_runs <- list(
  list(mode = "local", cond = FALSE),
  list(mode = "local", cond = TRUE),
  list(mode = "collaborate", cond = FALSE)
)

test_that("the final time never exceeds the pattern's observed maximum", {
  df <- .fx_pfs()
  pat <- paste(df$prog, df$died, sep = "/")
  obs_max <- tapply(df$time_death, pat, max)
  clipped <- integer()
  for (ru in .fx_pfs_runs) {
    roles <- .fx_pfs_roles(df, ru$mode)
    for (s in 1:15) {
      m <- suppressWarnings(mask(
        df, roles, mode = ru$mode, seed = s, conditional = ru$cond,
        events = .fx_pfs_spec
      ))
      syn <- synthetic(m)
      lab <- sprintf("%s cond=%s seed=%d", ru$mode, ru$cond, s)
      pat_new <- paste(syn$prog, syn$died, sep = "/")
      clone_max <- tapply(syn$time_death, pat_new, max)
      expect_true(all(clone_max <= obs_max[names(clone_max)]), label = lab)
      expect_identical(sum(syn$time_prog > syn$time_death), 0L, label = lab)
      expect_identical(c(table(pat_new)), c(table(pat)), label = lab)
      no_prog <- syn$prog == 0L
      expect_identical(syn$time_prog[no_prog], syn$time_death[no_prog],
                       label = lab)
      clipped <- c(clipped, recipe(m)@events[[1]]$clipped)
    }
  }
  expect_type(clipped, "integer")
  expect_true(all(clipped >= 0L))
  # Every seed ran past the cap before the fix.
  expect_true(sum(clipped > 0L) >= 15L)
})

test_that("a conditional clone caps within each arm", {
  df <- .fx_pfs()
  cell <- paste(df$arm, df$prog, df$died, sep = "/")
  obs_max <- tapply(df$time_death, cell, max)
  roles <- .fx_pfs_roles(df, "local")
  for (s in 1:5) {
    m <- suppressWarnings(mask(
      df, roles, mode = "local", seed = s, conditional = TRUE,
      events = .fx_pfs_spec
    ))
    syn <- synthetic(m)
    cell_new <- paste(syn$arm, syn$prog, syn$died, sep = "/")
    clone_max <- tapply(syn$time_death, cell_new, max)
    expect_true(all(clone_max <= obs_max[names(clone_max)]))
  }
})

test_that("intermediate times are not clipped", {
  # Local draws return observed gaps, so a progression time outside the
  # observed set can only come from a row rescaled as a whole.
  df <- .fx_pfs()
  roles <- .fx_pfs_roles(df, "local")
  for (s in 1:15) {
    m <- suppressWarnings(mask(
      df, roles, mode = "local", seed = s, events = .fx_pfs_spec
    ))
    syn <- synthetic(m)
    ev <- recipe(m)@events[[1]]
    prog_rows <- syn$prog == 1L
    off_set <- sum(!syn$time_prog[prog_rows] %in% df$time_prog[df$prog == 1L])
    expect_lte(off_set, ev$rescaled)
  }
})

test_that("the recipe records how many rows were capped", {
  df <- .fx_pfs()
  m <- suppressWarnings(mask(
    df, .fx_pfs_roles(df, "local"), mode = "local", seed = 1,
    events = .fx_pfs_spec
  ))
  ev <- recipe(m)@events[[1]]
  expect_true(ev$clipped > 0L)
  expect_true(any(grepl("final time capped", recipe(m)@warnings)))
})

test_that("the cap moves the final block, or rescales a row it cannot clip", {
  # Row 1: plain clip of the last time. Row 2: the last two times are tied by a
  # zero gap and move together. Row 3: the second time is already past the
  # cap, so the row is scaled. Row 4: under the cap, untouched.
  gaps <- rbind(c(2, 3, 4), c(2, 5, 0), c(6, 5, 1), c(1, 1, 1))
  times <- t(apply(gaps, 1L, cumsum))
  cap <- c(7, 6, 8, 10)
  out <- .cap_final_time(times, gaps, cap)
  expect_identical(out$clipped, 3L)
  expect_identical(out$rescaled, 1L)
  expect_equal(out$times[1, ], c(2, 5, 7))
  expect_equal(out$times[2, ], c(2, 6, 6))
  expect_equal(out$times[3, ], c(6, 11, 12) * 8 / 12)
  expect_equal(out$times[4, ], c(1, 2, 3))
  expect_true(all(t(apply(out$times, 1L, diff)) >= 0))
  expect_true(all(out$times[, 3] <= cap))
})
