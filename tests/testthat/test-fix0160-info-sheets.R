# Documentation sheets and files: `sheets =` chooses what is read, `info =`
# sets tables aside (not masked, not written), and a hint names likely ones.

CONTACT <- "Contact: J. Smith, site agronomist"

info_tables <- function() {
  set.seed(4)
  trial <- data.frame(
    site = rep(c("north", "south", "east", "west"), each = 6),
    genotype = rep(c("Scope", "Compass", "Mace"), 8),
    yield = round(stats::rnorm(24, 3, 0.5), 2),
    stringsAsFactors = FALSE
  )
  dictionary <- data.frame(
    Column = c("site", "genotype", "yield"),
    Description = c(
      CONTACT, "Entry name as sown in the trial plan",
      "Grain yield, tonnes per hectare at 12.5% moisture"
    ),
    stringsAsFactors = FALSE
  )
  list(trial = trial, Dictionary = dictionary)
}

info_roles <- function(tabs, mode = "local") {
  r <- propose_roles(tabs$trial, mode = mode, detect = FALSE)
  r <- set_role(r, "site", role = "design")
  r <- set_role(r, "genotype", role = "treatment")
  list(trial = set_role(r, "yield", role = "outcome"))
}

info_workbook <- function(tabs = info_tables()) {
  path <- file.path(withr::local_tempdir(.local_envir = parent.frame()),
                    "trial.xlsx")
  writexl::write_xlsx(tabs, path = path)
  path
}

info_folder <- function(tabs = info_tables()) {
  d <- withr::local_tempdir(.local_envir = parent.frame())
  for (nm in names(tabs)) {
    data.table::fwrite(tabs[[nm]], file.path(d, paste0(nm, ".csv")))
  }
  d
}

has_contact <- function(tables) {
  any(vapply(tables, function(t) {
    CONTACT %in% unlist(lapply(t, as.character))
  }, logical(1L)))
}

test_that("info = sets a sheet aside on every set path", {
  skip_if_not_installed("writexl")
  skip_if_not_installed("readxl")
  tabs <- info_tables()
  path <- info_workbook(tabs)
  d <- info_folder(tabs)
  for (mode in c("local", "collaborate")) {
    runs <- list(
      masque(path, roles = info_roles(tabs, mode), mode = mode, seed = 1,
        info = "Dictionary", quiet = TRUE
      ),
      masque(d, mode = mode, seed = 1, info = "Dictionary", ask = FALSE,
        quiet = TRUE
      ),
      mask_set(tabs, roles = info_roles(tabs, mode), mode = mode, seed = 1,
        info = "Dictionary", quiet = TRUE
      )
    )
    for (m in runs) {
      expect_named(synthetic(m), "trial")
      expect_false(has_contact(synthetic(m)), info = mode)
      expect_identical(recipe(m)@info, "Dictionary")
      expect_named(recipe(m)@recipes, "trial")
    }
  }
})

test_that("a set-aside sheet is not written, and the raw set still applies", {
  skip_if_not_installed("writexl")
  skip_if_not_installed("readxl")
  tabs <- info_tables()
  path <- info_workbook(tabs)
  out_dir <- file.path(withr::local_tempdir(), "masked")
  m <- masque(path, roles = info_roles(tabs), mode = "local", seed = 1,
    info = "Dictionary", out = out_dir, quiet = TRUE
  )
  expect_identical(list.files(out_dir), "trial.csv")

  out_xl <- file.path(withr::local_tempdir(), "masked.xlsx")
  masque(path, roles = info_roles(tabs), mode = "local", seed = 1,
    info = "Dictionary", out = out_xl, quiet = TRUE
  )
  expect_identical(readxl::excel_sheets(out_xl), "trial")

  fwd <- apply_recipe(read_set(path), recipe(m))
  expect_named(fwd, "trial")
})

test_that("sheets = reads only the named sheets", {
  skip_if_not_installed("writexl")
  skip_if_not_installed("readxl")
  tabs <- info_tables()
  path <- info_workbook(tabs)
  m1 <- masque(path, roles = info_roles(tabs), mode = "local", seed = 1,
    sheets = "trial", quiet = TRUE
  )
  expect_named(synthetic(m1), "trial")
  m2 <- mask_set(path, roles = info_roles(tabs), mode = "local", seed = 1,
    sheets = "trial", quiet = TRUE
  )
  expect_named(synthetic(m2), "trial")
  expect_length(recipe(m2)@info, 0L)
})

test_that("info and sheets refuse what they cannot mean", {
  tabs <- info_tables()
  expect_error(
    mask_set(tabs, info = "Readme", mode = "local", quiet = TRUE),
    class = "masque_bad_info_refusal"
  )
  expect_error(
    mask_set(tabs, info = names(tabs), mode = "local", quiet = TRUE),
    class = "masque_bad_info_refusal"
  )
  expect_error(
    masque(tabs$trial, info = "Dictionary", mode = "local", quiet = TRUE),
    class = "masque_bad_info_refusal"
  )
  expect_error(
    mask_set(info_folder(tabs), sheets = "trial", mode = "local",
      quiet = TRUE
    ),
    class = "masque_bad_sheets_refusal"
  )
})

# The Dictionary masked in local mode keeps every column, which mask() notes.
keep_all_ok <- function(expr) {
  withCallingHandlers(expr, warning = function(w) {
    if (grepl("nothing will be masked", conditionMessage(w), fixed = TRUE)) {
      invokeRestart("muffleWarning")
    }
  })
}

test_that("a sheet that looks like documentation gets a hint, not a decision", {
  tabs <- info_tables()
  expect_message(
    m <- keep_all_ok(mask_set(tabs, mode = "local", seed = 1)),
    class = "masque_info_hint"
  )
  # The hint decides nothing: the sheet was still masked.
  expect_true("Dictionary" %in% names(synthetic(m)))

  # Named like documentation.
  notes <- list(trial = tabs$trial, notes = data.frame(a = 1:6, b = 6:1))
  expect_message(
    keep_all_ok(mask_set(notes, mode = "local", seed = 1)),
    class = "masque_info_hint"
  )

  # No hint once the sheet is set aside, or for plain data tables.
  msgs <- testthat::capture_messages(
    mask_set(tabs, info = "Dictionary", mode = "local", seed = 1)
  )
  expect_false(any(grepl("documentation", msgs)))
  plain <- list(trial = tabs$trial, lines = data.frame(
    genotype = c("Scope", "Compass", "Mace", "Trojan", "Spartacus"),
    height = c(80, 95, 102, 88, 91)
  ))
  msgs <- testthat::capture_messages(
    mask_set(plain, mode = "local", seed = 1)
  )
  expect_false(any(grepl("documentation", msgs)))
})

test_that("the summary names what was set aside", {
  tabs <- info_tables()
  msgs <- testthat::capture_messages(
    masque(tabs, roles = info_roles(tabs), mode = "local", seed = 1,
      info = "Dictionary"
    )
  )
  expect_true(any(grepl("Set aside", msgs) & grepl("Dictionary", msgs)))
})
