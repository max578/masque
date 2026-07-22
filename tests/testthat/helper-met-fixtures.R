# Deterministic fixtures for the MET-scope detection contract.
#
# These fixtures encode structure only. Outcomes are deterministic and must
# not influence environment resolution.

met_complete_fixture <- function() {
  out <- expand.grid(
    env = factor(c("E1", "E2", "E3")),
    rep = factor(seq_len(2L)),
    gen = factor(paste0("G", seq_len(4L))),
    KEEP.OUT.ATTRS = FALSE
  )
  out$block <- interaction(out$env, out$rep, drop = TRUE)
  out$yield <- seq_len(nrow(out)) / 10
  out[, c("env", "rep", "block", "gen", "yield")]
}

met_county_fixture <- function() {
  out <- expand.grid(
    county = factor(paste0("C", seq_len(6L))),
    rep = factor(seq_len(3L)),
    gen = factor(paste0("G", seq_len(16L))),
    KEEP.OUT.ATTRS = FALSE
  )
  out$block <- factor((as.integer(out$gen) - 1L) %% 4L + 1L)
  out$yield <- seq_len(nrow(out)) / 10
  out[, c("county", "rep", "block", "gen", "yield")]
}

met_site_year_fixture <- function() {
  out <- expand.grid(
    site = factor(c("North", "South")),
    year = c(2024L, 2025L),
    rep = factor(seq_len(2L)),
    gen = factor(paste0("G", seq_len(3L))),
    KEEP.OUT.ATTRS = FALSE
  )
  out$block <- interaction(out$site, out$year, out$rep, drop = TRUE)
  out$yield <- seq_len(nrow(out)) / 10
  out[, c("site", "year", "rep", "block", "gen", "yield")]
}

met_precomposed_fixture <- function() {
  out <- met_site_year_fixture()
  out$site_year <- interaction(out$site, out$year, drop = TRUE)
  out[, c("site_year", "rep", "block", "gen", "yield")]
}

met_disconnected_fixture <- function() {
  group_1 <- expand.grid(
    env = factor(c("E1", "E2"), levels = paste0("E", seq_len(4L))),
    rep = factor(seq_len(2L)),
    gen = factor(paste0("G", seq_len(3L)),
      levels = paste0("G", seq_len(6L))
    ),
    KEEP.OUT.ATTRS = FALSE
  )
  group_1$trial <- factor("T1", levels = c("T1", "T2"))

  group_2 <- expand.grid(
    env = factor(c("E3", "E4"), levels = paste0("E", seq_len(4L))),
    rep = factor(seq_len(2L)),
    gen = factor(paste0("G", 4:6), levels = paste0("G", seq_len(6L))),
    KEEP.OUT.ATTRS = FALSE
  )
  group_2$trial <- factor("T2", levels = c("T1", "T2"))

  out <- rbind(group_1, group_2)
  out$env <- droplevels(out$env)
  out$gen <- droplevels(out$gen)
  out$trial <- droplevels(out$trial)
  out$yield <- seq_len(nrow(out)) / 10
  out[, c("trial", "env", "rep", "gen", "yield")]
}

met_unreplicated_fixture <- function() {
  out <- expand.grid(
    env = factor(c("E1", "E2", "E3")),
    gen = factor(paste0("G", seq_len(5L))),
    KEEP.OUT.ATTRS = FALSE
  )
  out$yield <- seq_len(nrow(out)) / 10
  out
}

met_missing_fixture <- function() {
  out <- met_complete_fixture()
  out$env[c(2L, 11L)] <- NA
  out$gen[7L] <- NA
  out$yield[c(4L, 16L)] <- NA_real_
  out
}

met_multiple_treatment_fixture <- function() {
  out <- expand.grid(
    env = factor(c("E1", "E2", "E3")),
    rep = factor(seq_len(2L)),
    genotype = factor(paste0("G", seq_len(3L))),
    dose = factor(c("low", "high")),
    KEEP.OUT.ATTRS = FALSE
  )
  out$yield <- seq_len(nrow(out)) / 10
  out
}

single_rcbd_fixture <- function() {
  out <- expand.grid(
    block = factor(paste0("B", seq_len(3L))),
    gen = factor(paste0("G", seq_len(4L))),
    KEEP.OUT.ATTRS = FALSE
  )
  out$yield <- seq_len(nrow(out)) / 10
  out
}

repeated_measures_fixture <- function() {
  out <- expand.grid(
    subject_id = paste0("S", sprintf("%02d", seq_len(8L))),
    year = 2023:2025,
    KEEP.OUT.ATTRS = FALSE,
    stringsAsFactors = FALSE
  )
  out$score <- seq_len(nrow(out)) / 10
  out
}

near_unique_site_fixture <- function() {
  out <- data.frame(
    site = factor(paste0("S", sprintf("%02d", seq_len(24L)))),
    gen = factor(rep(paste0("G", seq_len(4L)), times = 6L)),
    yield = seq_len(24L) / 10
  )
  out
}

ambiguous_site_fixture <- function() {
  out <- expand.grid(
    site = factor(c("S1", "S2")),
    location = factor(c("L1", "L2")),
    gen = factor(paste0("G", seq_len(4L))),
    rep = factor(seq_len(2L)),
    KEEP.OUT.ATTRS = FALSE
  )
  out$yield <- seq_len(nrow(out)) / 10
  out
}

legacy_design_fields <- function(x) {
  recommended_roles <- x@recommended_roles
  recommended_roles <- recommended_roles[c("col", "role")]
  list(
    class_label = x@class_label,
    treatment_col = x@treatment_col,
    block_cols = x@block_cols,
    whole_plot_col = x@whole_plot_col,
    sub_plot_col = x@sub_plot_col,
    spatial_cols = x@spatial_cols,
    scores = x@scores,
    evidence = x@evidence,
    recommended_roles = recommended_roles,
    candidates = x@candidates,
    warnings = x@warnings
  )
}

legacy_base_oracle <- function() {
  list(
    iris = list(
      class_label = "CRD",
      treatment_col = "Species",
      block_cols = character(),
      whole_plot_col = character(),
      sub_plot_col = character(),
      spatial_cols = character(),
      scores = c(
        CRD = 1, RCBD = 0, `IBD/alpha-lattice` = 0,
        `row-column` = 0, `split-plot` = 0, factorial = 0
      ),
      recommended_roles = data.frame(
        col = "Species", role = "treatment"
      ),
      warnings = character()
    ),
    tooth = list(
      class_label = "factorial",
      treatment_col = c("supp", "dose"),
      block_cols = character(),
      whole_plot_col = character(),
      sub_plot_col = character(),
      spatial_cols = character(),
      scores = c(
        CRD = 0.4, RCBD = 0, `IBD/alpha-lattice` = 0,
        `row-column` = 0, `split-plot` = 0, factorial = 0.8
      ),
      recommended_roles = data.frame(
        col = c("supp", "dose"),
        role = c("treatment", "treatment")
      ),
      warnings = character()
    ),
    mtcars = list(
      class_label = "none",
      treatment_col = character(),
      block_cols = character(),
      whole_plot_col = character(),
      sub_plot_col = character(),
      spatial_cols = character(),
      scores = c(
        CRD = 0, RCBD = 0, `IBD/alpha-lattice` = 0.3,
        `row-column` = 0, `split-plot` = 0,
        factorial = 0.463048879864784
      ),
      recommended_roles = data.frame(
        col = character(), role = character()
      ),
      warnings = character()
    )
  )
}
