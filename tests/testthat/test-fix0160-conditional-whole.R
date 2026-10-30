# A conditional clone adds the dropped design terms back as shifts. Whole-valued
# columns must stay whole on the way back, in either storage class (F4).

# 24 genotypes x 6 trials x 3 reps: genotype x trial cells hold 3 rows, so the
# ladder drops rep and trial and carries them as shifts.
.fx_count_met <- function(as_integer = FALSE) {
  set.seed(4)
  trials <- sprintf("T%d", 1:6)
  gens <- sprintf("G%02d", 1:24)
  g <- expand.grid(
    genotype = gens, rep = 1:3, trial = trials,
    stringsAsFactors = FALSE, KEEP.OUT.ATTRS = FALSE
  )
  lam <- 20 + 4 * match(g$trial, trials) + 3 * (match(g$genotype, gens) %% 3)
  cnt <- stats::rpois(nrow(g), lambda = lam)
  g$count <- if (as_integer) as.integer(cnt) else as.numeric(cnt)
  g$height <- round(stats::rnorm(nrow(g), 80, 6), 1)
  g[, c("trial", "rep", "genotype", "count", "height")]
}

.fx_count_roles <- function(df, mode) {
  r <- suppressWarnings(propose_roles(df, mode = mode, detect = FALSE))
  r <- set_role(r, c("trial", "rep"), role = "design", action = "keep")
  r <- set_role(r, "genotype", role = "treatment",
                action = if (mode == "collaborate") "alias" else "keep")
  r <- set_role(r, "count", role = "outcome", action = "scramble")
  r <- set_role(r, "height", role = "covariate", action = "scramble")
  r
}

test_that("a shifted conditional clone keeps whole-valued columns whole", {
  for (storage in c("double", "integer")) {
    df <- .fx_count_met(as_integer = storage == "integer")
    for (mode in c("local", "collaborate")) {
      m <- suppressWarnings(mask(
        df, .fx_count_roles(df, mode), mode = mode, seed = 1,
        conditional = TRUE
      ))
      rec <- recipe(m)
      # The design that shows the defect: rungs dropped, terms shifted.
      expect_true(length(rec@conditioning_shifted) > 0L)
      v <- synthetic(m)$count
      lab <- paste(storage, mode)
      expect_true(all(v == round(v), na.rm = TRUE), label = lab)
      expect_identical(class(v), class(df$count), label = lab)
      # One-decimal covariates are not whole and are not rounded.
      h <- synthetic(m)$height
      expect_true(any(h != round(h)), label = lab)
    }
  }
})
