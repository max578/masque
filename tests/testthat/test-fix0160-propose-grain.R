.pg_met <- function() {
  withr::with_seed(3L, {
    g <- expand.grid(
      genotype = sprintf("G%02d", 1:10), rep = 1:2, trial = sprintf("T%d", 1:6),
      stringsAsFactors = FALSE, KEEP.OUT.ATTRS = FALSE
    )
    g$yield <- round(stats::rnorm(nrow(g), 3, 0.4), 2)
    g$aet <- c(312.4, 287.9, 401.2, 355.6, 298.1, 376.5)[
      match(g$trial, sprintf("T%d", 1:6))
    ]
    g$plot_cov <- round(stats::rnorm(nrow(g), 50, 8), 2)
    g
  })
}

test_that("propose_roles() notes a column that mask() will synthesise per unit", {
  df <- .pg_met()
  for (mode in c("local", "collaborate")) {
    for (detect in c(TRUE, FALSE)) {
      r <- suppressWarnings(propose_roles(df, mode = mode, detect = detect))
      expect_identical(r$role[r$col == "trial"], "design")
      expect_match(
        r$notes[r$col == "aet"], "Constant within trial; synthesised per trial.",
        fixed = TRUE
      )
      expect_false(grepl("synthesised per", r$notes[r$col == "plot_cov"]))
      expect_identical(attr(r, "mode"), mode)
    }
  }
})
