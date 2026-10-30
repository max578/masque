# The guided front door: mode inheritance, argument forwarding, the summary
# and notices it prints, and input it must refuse.

dup_frame <- function() {
  set.seed(3)
  d <- data.frame(
    a = 1:8, a = round(stats::rnorm(8), 2), b = rep(c("x", "y"), 4),
    check.names = FALSE, stringsAsFactors = FALSE
  )
  d
}

no_rename_then <- function(expr) {
  withCallingHandlers(
    expr,
    masque_name_repaired = function(w) stop("a rename warning was raised")
  )
}

test_that("duplicated input column names give one classed refusal", {
  d <- dup_frame()
  r <- propose_roles(d, mode = "local", detect = FALSE)
  expect_error(
    no_rename_then(clean_table(d, quiet = TRUE)),
    class = "masque_duplicate_names_refusal"
  )
  expect_error(
    no_rename_then(mask(d, r, mode = "local", seed = 1)),
    class = "masque_duplicate_names_refusal"
  )
  expect_error(
    no_rename_then(masque(d, mode = "local", ask = FALSE, quiet = TRUE)),
    class = "masque_duplicate_names_refusal"
  )
  expect_error(
    no_rename_then(mask_set(list(t = d), mode = "local", quiet = TRUE)),
    class = "masque_duplicate_names_refusal"
  )
  # The refusal names the column the user has, not a generated one.
  err <- expect_error(clean_table(d, quiet = TRUE), "\"a\"")
  expect_false(grepl("a_1", conditionMessage(err), fixed = TRUE))
})

door_trial <- function() {
  set.seed(8)
  g <- expand.grid(
    genotype = c("Scope", "Compass", "Spartacus", "Trojan"), rep = 1:3,
    site = c("north", "south", "east", "west"),
    stringsAsFactors = FALSE, KEEP.OUT.ATTRS = FALSE
  )
  g$plot_id <- sprintf("P%03d", seq_len(nrow(g)))
  g$yield <- round(3 + stats::rnorm(nrow(g), 0, 0.4), 2)
  g
}

door_roles <- function(df, mode) {
  r <- propose_roles(df, mode = mode, detect = FALSE)
  r <- set_role(r, "genotype", role = "treatment")
  r <- set_role(r, "rep", role = "design")
  r <- set_role(r, "site", role = "design")
  r <- set_role(r, "plot_id", role = "id", action = "drop")
  set_role(r, "yield", role = "outcome")
}

door_set <- function() {
  df <- door_trial()
  lines <- data.frame(
    genotype = c("Scope", "Compass", "Spartacus", "Trojan"),
    height = c(80, 95, 102, 88), stringsAsFactors = FALSE
  )
  list(trial = df, lines = lines)
}

door_set_roles <- function(tabs, mode) {
  rl <- propose_roles(tabs$lines, mode = mode, detect = FALSE)
  rl <- set_role(rl, "genotype", role = "treatment")
  list(trial = door_roles(tabs$trial, mode), lines = rl)
}

test_that("masque() inherits a collaborate plan's mode without `mode`", {
  df <- door_trial()
  r <- door_roles(df, "collaborate")
  for (q in c(TRUE, FALSE)) {
    expect_no_warning(
      m <- suppressMessages(masque(df, roles = r, seed = 1, quiet = q)),
      class = "masque_mode_downgrade"
    )
    expect_identical(recipe(m)@mode, "collaborate", info = as.character(q))
    expect_false(any(df$genotype %in% as.character(synthetic(m)$genotype)))
  }
})

test_that("masque() on a set inherits the plans' mode without `mode`", {
  tabs <- door_set()
  rl <- door_set_roles(tabs, "collaborate")
  for (q in c(TRUE, FALSE)) {
    expect_no_warning(
      m <- suppressMessages(masque(tabs, roles = rl, seed = 1, quiet = q)),
      class = "masque_mode_downgrade"
    )
    expect_identical(m@mode, "collaborate", info = as.character(q))
    expect_false(any(
      tabs$trial$genotype %in% as.character(synthetic(m)$trial$genotype)
    ))
  }
})

test_that("masque() passes `detect` to propose_roles()", {
  real <- propose_roles
  seen <- logical()
  local_mocked_bindings(propose_roles = function(df, mode = "local",
                                                 detect = TRUE) {
    seen <<- c(seen, detect)
    real(df, mode = mode, detect = detect)
  })
  masque(door_trial(), detect = FALSE, seed = 1, ask = FALSE, quiet = TRUE)
  masque(door_set(), detect = FALSE, seed = 1, ask = FALSE, quiet = TRUE)
  expect_length(seen, 3L)
  expect_false(any(seen))
})

test_that("masque() forwards the verb's arguments and refuses unknown ones", {
  df <- door_trial()
  r <- door_roles(df, "local")
  m <- masque(df, roles = r, mode = "local", seed = 1, quiet = TRUE,
    allow_unmasked_coords = TRUE
  )
  expect_true(recipe(m)@allow_unmasked_coords)

  tabs <- door_set()
  rl <- door_set_roles(tabs, "collaborate")
  linked <- masque(tabs, roles = rl, seed = 1, quiet = TRUE)
  expect_gt(length(recipe(linked)@links), 0L)
  unlinked <- masque(tabs, roles = rl, seed = 1, quiet = TRUE, links = FALSE)
  expect_length(recipe(unlinked)@links, 0L)

  expect_error(
    masque(df, roles = r, mode = "local", quiet = TRUE, bogus = 1),
    class = "masque_unused_arg_refusal"
  )
  expect_error(
    masque(tabs, roles = rl, quiet = TRUE, bogus = 1),
    class = "masque_unused_arg_refusal"
  )
  expect_error(
    mask_set(tabs, roles = rl, quiet = TRUE, bogus = 1),
    class = "masque_unused_arg_refusal"
  )
})

summary_counts <- function(msgs) {
  head_line <- grep("Masked [0-9]+ column", msgs, value = TRUE)
  audit <- regmatches(head_line, regexec(
    "audit: ([0-9]+) HIGH, ([0-9]+) medium, ([0-9]+) low", head_line
  ))[[1L]]
  list(
    masked = as.integer(sub(".*Masked ([0-9]+) column.*", "\\1", head_line)),
    audited = sum(as.integer(audit[-1L]))
  )
}

test_that("the guided summary counts columns as the audit does", {
  df <- door_trial()
  r <- door_roles(df, "collaborate")
  msgs <- testthat::capture_messages(
    masque(df, roles = r, mode = "collaborate", seed = 1)
  )
  n <- summary_counts(msgs)
  expect_identical(n$masked, n$audited)
  expect_identical(n$masked, ncol(df))
  expect_true(any(grepl("dropped", msgs) & grepl("plot_id", msgs)))
})

test_that("the non-interactive notice does not advise the argument passed", {
  skip_if(interactive())
  msgs <- testthat::capture_messages(
    masque(door_trial(), mode = "local", seed = 1, ask = TRUE)
  )
  notice <- grep("proposed masking plan", msgs, value = TRUE)
  expect_length(notice, 1L)
  expect_false(grepl("set `ask = TRUE`", notice, fixed = TRUE))
  expect_match(notice, "interactive")

  msgs_f <- testthat::capture_messages(
    masque(door_trial(), mode = "local", seed = 1, ask = FALSE)
  )
  expect_true(any(grepl("ask = TRUE", msgs_f, fixed = TRUE)))
})
