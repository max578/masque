# A linked join key that a table's roles mark `drop` is kept, aliased, in the
# synthetic set, so apply_recipe() must keep it too.

link_set <- function() {
  set.seed(21)
  plot_id <- sprintf("P%03d", 1:24)
  agronomy <- data.frame(
    plot_id = plot_id,
    site = rep(c("north", "south", "east", "west"), each = 6),
    genotype = rep(c("Scope", "Compass", "Mace"), 8),
    yield = round(stats::rnorm(24, 3, 0.5), 2),
    stringsAsFactors = FALSE
  )
  keep <- sort(sample(24, 16))
  quality <- data.frame(
    plot_id = plot_id[keep],
    protein = round(stats::rnorm(16, 12, 1), 2),
    stringsAsFactors = FALSE
  )
  list(agronomy = agronomy, quality = quality)
}

link_roles <- function(tabs, mode) {
  ra <- propose_roles(tabs$agronomy, mode = mode, detect = FALSE)
  ra <- set_role(ra, "plot_id", role = "id", action = "drop")
  ra <- set_role(ra, "site", role = "design")
  ra <- set_role(ra, "genotype", role = "treatment")
  ra <- set_role(ra, "yield", role = "outcome")
  rq <- propose_roles(tabs$quality, mode = mode, detect = FALSE)
  rq <- set_role(rq, "plot_id", role = "id", action = "drop")
  rq <- set_role(rq, "protein", role = "outcome")
  list(agronomy = ra, quality = rq)
}

test_that("apply_recipe keeps a linked key the roles mark drop", {
  tabs <- link_set()
  for (mode in c("local", "collaborate")) {
    m <- mask_set(
      tabs, roles = link_roles(tabs, mode), mode = mode, seed = 1,
      quiet = TRUE
    )
    syn <- synthetic(m)
    expect_true("plot_id" %in% names(syn$quality), info = mode)

    fwd <- apply_recipe(tabs, recipe(m))
    for (nm in names(tabs)) {
      expect_true("plot_id" %in% names(fwd[[nm]]), info = paste(mode, nm))
      expect_identical(names(fwd[[nm]]), names(syn[[nm]]), info = mode)
      expect_identical(
        as.character(fwd[[nm]]$plot_id), as.character(syn[[nm]]$plot_id),
        info = paste(mode, nm)
      )
    }

    # A join written on the clone resolves on the retargeted original.
    j <- merge(fwd$agronomy, fwd$quality, by = "plot_id")
    expect_equal(nrow(j), nrow(tabs$quality), info = mode)

    # unmask() and apply_recipe() agree on the key.
    back <- unmask(fwd, recipe(m))
    expect_identical(back$quality$plot_id, tabs$quality$plot_id, info = mode)
  }
})

test_that("the bundle records a linked key as retained", {
  tabs <- link_set()
  m <- mask_set(
    tabs, roles = link_roles(tabs, "collaborate"), mode = "collaborate",
    seed = 1, quiet = TRUE
  )
  for (nm in names(tabs)) {
    r <- recipe(m)@recipes[[nm]]@roles
    expect_false(r$action[r$col == "plot_id"] == "drop", info = nm)
  }
})
