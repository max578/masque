# The guided review's edit path. utils::edit() needs the X11 dataentry
# widget on macOS terminal R (XQuartz); when it cannot start, the guided
# session must survive - the console fallback takes over, and every edit
# flows through set_role().

# A readline stub serving a fixed queue of answers.
queue_readline <- function(answers) {
  i <- 0L
  function(prompt) {
    i <<- i + 1L
    if (i > length(answers)) {
      stop("console editor asked for more input than the test scripted")
    }
    answers[[i]]
  }
}

test_that("editor failure falls back to the console editor, session intact", {
  r <- propose_roles(iris)
  # Column "Species" by name; keep role (blank); action 3 = alias; done.
  local_mocked_bindings(
    .masque_edit_gui = function(roles) stop("X11 library is missing"),
    .masque_readline = queue_readline(c("Species", "", "3", ""))
  )
  msgs <- testthat::capture_messages(
    r2 <- masque:::.masque_edit(r)
  )
  expect_true(any(grepl("spreadsheet editor is unavailable", msgs)))
  expect_true(any(grepl("console editor", msgs)))
  expect_identical(r2$action[r2$col == "Species"], "alias")
  # Untouched columns unchanged; provenance attributes survive.
  expect_identical(r2$role, r$role)
  expect_identical(attr(r2, "mode"), attr(r, "mode"))
})

test_that("console editor: re-roling re-resolves the action via set_role()", {
  r <- propose_roles(iris)
  # Row number 5 = Species; role 3 = outcome; keep action (blank); done.
  local_mocked_bindings(
    .masque_readline = queue_readline(c("5", "3", "", ""))
  )
  r2 <- suppressMessages(masque:::.masque_edit_console(r))
  expect_identical(r2$role[r2$col == "Species"], "outcome")
  ref <- set_role(r, "Species", role = "outcome")
  expect_identical(r2$action, ref$action)
})

test_that("console editor: blank input returns the table unchanged", {
  r <- propose_roles(iris)
  local_mocked_bindings(.masque_readline = queue_readline(""))
  r2 <- suppressMessages(masque:::.masque_edit_console(r))
  expect_identical(r2, r)
})

test_that("console editor: unknown column warns and re-prompts", {
  r <- propose_roles(iris)
  local_mocked_bindings(
    .masque_readline = queue_readline(c("nope", "99", ""))
  )
  msgs <- testthat::capture_messages(
    r2 <- masque:::.masque_edit_console(r)
  )
  expect_length(grep("enter a listed name or its row number", msgs), 2L)
  expect_identical(r2, r)
})

test_that("console editor: invalid role entry keeps the current value", {
  r <- propose_roles(iris)
  # Species; invalid role; blank action; done -> unchanged.
  local_mocked_bindings(
    .masque_readline = queue_readline(c("Species", "widget", "", ""))
  )
  msgs <- testthat::capture_messages(
    r2 <- masque:::.masque_edit_console(r)
  )
  expect_true(any(grepl("not a valid role", msgs)))
  expect_identical(r2$role, r$role)
  expect_identical(r2$action, r$action)
})

test_that("a working spreadsheet editor still round-trips attributes", {
  r <- propose_roles(iris)
  local_mocked_bindings(
    # Simulate utils::edit(): returns an edited plain data.frame with
    # the provenance attributes dropped.
    .masque_edit_gui = function(roles) {
      out <- as.data.frame(roles)
      out$role[out$col == "Sepal.Length"] <- "outcome"
      out
    }
  )
  r2 <- masque:::.masque_edit(r)
  expect_identical(r2$role[r2$col == "Sepal.Length"], "outcome")
  expect_identical(attr(r2, "mode"), attr(r, "mode"))
  expect_s3_class(r2, "tbl_df")
})
