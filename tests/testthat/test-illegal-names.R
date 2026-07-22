# Regression suite for illegal (non-syntactic) column names. They must be
# legalised in every clean mode, warned about with a classed condition,
# recorded on the recipe, masked (never leaked, never duplicated), and
# reversed on the round-trip. Guards the 0.8.x silent-rename / leak defect
# where a "%" name was sanitised inside numeric synthesis with no map, so
# the original column survived un-masked alongside the synthesised copy.

illegal_frame <- function(n = 60L) {
  set.seed(1)
  d <- data.frame(
    block   = factor(rep(1:4, length.out = n)),
    variety = factor(rep(paste0("V", 1:6), length.out = n)),
    check.names = FALSE
  )
  d[["GY_%VARMAX"]]   <- stats::runif(n, 50, 100)   # special character
  d[["Yield (t/ha)"]] <- stats::rnorm(n, 5, 1)      # space + parentheses
  d[["2023_score"]]   <- stats::rnorm(n)            # leading digit
  d[["if"]]           <- stats::rnorm(n)            # reserved word
  d[["a%b"]]          <- stats::rnorm(n)            # collides with a.b
  d[["a.b"]]          <- stats::rnorm(n)            # already legal, bumped
  d
}

illegal_numeric_cols <- c(
  "GY_%VARMAX", "Yield (t/ha)", "2023_score", "if", "a%b"
)

test_that("mask() warns (classed) and records the name repair on the recipe", {
  d <- illegal_frame()
  r <- propose_roles(d, detect = FALSE)
  expect_warning(mask(d, r, seed = 1), class = "masque_name_repaired")
  m <- suppressWarnings(mask(d, r, seed = 1))
  expect_true(any(grepl("not valid R names", recipe(m)@warnings)))
})

test_that("illegal names legalise without duplication or leak, in every mode", {
  d <- illegal_frame()
  for (cm in c("auto", "report", "off")) {
    r <- propose_roles(d, detect = FALSE)
    m <- suppressWarnings(mask(d, r, seed = 1, clean = cm))
    s <- as.data.frame(synthetic(m))
    nm_map <- recipe(m)@cleaning$name_map

    # No column duplicated or lost, and every output name is valid.
    expect_equal(ncol(s), ncol(d), info = cm)
    expect_true(all(make.names(names(s)) == names(s)), info = cm)

    # No illegal column passed through un-masked (the leak).
    for (o in illegal_numeric_cols) {
      ln <- if (o %in% names(nm_map)) unname(nm_map[o]) else o
      expect_false(
        identical(as.numeric(s[[ln]]), as.numeric(d[[o]])),
        info = paste(cm, o)
      )
    }
  }
})

test_that("the name repair round-trips both directions", {
  d <- illegal_frame()
  r <- propose_roles(d, detect = FALSE)
  m <- suppressWarnings(mask(d, r, seed = 1))

  # unmask() restores the original (pre-legalisation) names.
  back <- suppressWarnings(unmask(as.data.frame(synthetic(m)), recipe(m)))
  expect_setequal(names(back), names(d))

  # apply_recipe() lines the original up with the synthetic namespace.
  fwd <- suppressWarnings(apply_recipe(d, recipe(m)))
  expect_setequal(names(fwd), names(synthetic(m)))
})

test_that(
  "a collision with an already-legal name is uniquified and reversible",
  {
  d <- illegal_frame()
  r <- propose_roles(d, detect = FALSE)
  m <- suppressWarnings(mask(d, r, seed = 1))
  s <- synthetic(m)
  nm_map <- recipe(m)@cleaning$name_map

  # a%b -> a.b; the pre-existing a.b is bumped to a.b_1 (both recorded).
  expect_equal(unname(nm_map[["a%b"]]), "a.b")
  expect_equal(unname(nm_map[["a.b"]]), "a.b_1")
  expect_equal(length(unique(names(s))), ncol(d))

  back <- suppressWarnings(unmask(as.data.frame(s), recipe(m)))
  expect_true(all(c("a%b", "a.b") %in% names(back)))
  }
)
