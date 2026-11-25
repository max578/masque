# Writes the recipe fixture read by test-fix0160-old-recipe.R.
#
# Run once, by hand, in a library that holds masque 0.16.0 as released on
# CRAN. The test suite never runs this file. It writes two files beside
# itself:
#
#   recipe-0.16.0.rds           a recipe as save_recipe() of 0.16.0 wrote it
#   recipe-0.16.0-expected.rds  the input table and its translated labels
#
# usage: Rscript make-recipe-0.16.0.R <output directory>

out_dir <- commandArgs(trailingOnly = TRUE)[[1L]]
stopifnot(utils::packageVersion("masque") == "0.16.0")

# A small trial table with no random numbers in it.
original <- expand.grid(
  gen = sprintf("G%02d", 1:6), rep = 1:2, trial = c("T1", "T2"),
  stringsAsFactors = FALSE, KEEP.OUT.ATTRS = FALSE
)
original$yield <- round(4 + sin(seq_len(nrow(original))), 2)
original$soil <- c("clay", "loam")[match(original$trial, c("T1", "T2"))]

roles <- suppressWarnings(
  masque::propose_roles(original, mode = "collaborate", detect = FALSE)
)
roles <- masque::set_role(
  roles, c("trial", "rep"), role = "design", action = "keep"
)
roles <- masque::set_role(roles, "gen", role = "treatment", action = "alias")
roles <- masque::set_role(roles, "yield", role = "outcome", action = "scramble")
roles <- masque::set_role(roles, "soil", role = "covariate", action = "alias")

masked <- suppressWarnings(
  masque::mask(original, roles, mode = "collaborate", seed = 4L)
)
rec <- masque::recipe(masked)
suppressMessages(
  masque::save_recipe(rec, file.path(out_dir, "recipe-0.16.0.rds"))
)

translated <- as.data.frame(masque::apply_recipe(original, rec))
saveRDS(
  list(
    original = original,
    translated = list(
      gen = as.character(translated$gen),
      soil = as.character(translated$soil)
    )
  ),
  file.path(out_dir, "recipe-0.16.0-expected.rds")
)
