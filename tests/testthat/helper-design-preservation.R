# One agridat exemplar per design class, with the model whose terms the
# conditional clone must keep (same as vignette("design_preservation")).

design_specs <- function() {
  augmented <- agridat::kling.augmented[, c("block", "gen", "tsw", "row", "col")]
  n_gen <- table(augmented$gen)
  augmented$check <- factor(ifelse(
    n_gen[as.character(augmented$gen)] > 1L, as.character(augmented$gen), "new"
  ))
  rcbd <- agridat::besag.elbatan
  rcbd$block <- factor(rcbd$col)
  list(
    CRD = list(
      data = agridat::cochran.crd, outcome = "inf", treatment = "trt",
      design = c("row", "col"),
      formula = inf ~ trt, terms = c(trt = "treatment")
    ),
    RCBD = list(
      data = rcbd, outcome = "yield", treatment = "gen",
      design = c("block", "row", "col"),
      formula = yield ~ block + gen,
      terms = c(block = "block", gen = "treatment")
    ),
    `Latin square` = list(
      data = agridat::fisher.latin, outcome = "yield", treatment = "trt",
      design = c("row", "col"),
      formula = yield ~ factor(row) + factor(col) + trt,
      terms = c(`factor(row)` = "block", `factor(col)` = "block",
        trt = "treatment")
    ),
    `split-plot` = list(
      data = agridat::yates.oats[, c("block", "row", "col", "gen", "nitro", "yield")],
      outcome = "yield", treatment = c("gen", "nitro"),
      design = c("block", "row", "col"),
      formula = yield ~ block + gen * nitro,
      terms = c(block = "block", gen = "treatment", nitro = "treatment")
    ),
    `alpha lattice` = list(
      data = agridat::john.alpha[, c("rep", "block", "gen", "yield", "row", "col")],
      outcome = "yield", treatment = "gen",
      design = c("rep", "block", "row", "col"),
      formula = yield ~ rep + rep:block + gen,
      terms = c(rep = "block", `rep:block` = "block", gen = "treatment")
    ),
    augmented = list(
      data = augmented, outcome = "tsw", treatment = c("gen", "check"),
      design = c("block", "row", "col"),
      formula = tsw ~ block + check,
      terms = c(block = "block", check = "treatment")
    ),
    MET = list(
      data = agridat::besag.met, outcome = "yield", treatment = "gen",
      design = c("county", "rep", "block", "row", "col"),
      formula = yield ~ county + county:rep + gen,
      terms = c(county = "environment", `county:rep` = "block",
        gen = "treatment")
    ),
    `repeated measures` = list(
      data = agridat::kenward.cattle, outcome = "weight", treatment = "trt",
      design = c("animal", "day"),
      formula = weight ~ trt + animal + factor(day),
      terms = c(trt = "treatment", animal = "block", `factor(day)` = "block")
    )
  )
}

design_roles <- function(spec) {
  r <- propose_roles(spec$data, mode = "local", detect = FALSE)
  r <- set_role(r, spec$outcome, role = "outcome")
  r <- set_role(r, spec$treatment, role = "treatment", action = "keep")
  set_role(r, spec$design, role = "design", action = "keep")
}

# Outcome mean per treatment level, over the levels with two or more rows.
design_level_means <- function(d, col, outcome) {
  tab <- table(d[[col]])
  m <- tapply(d[[outcome]], d[[col]], mean, na.rm = TRUE)
  m[names(tab)[tab >= 2L]]
}

# Mask one design over the seeds and measure what the clone keeps.
design_run <- function(spec, seeds, ladder = "hierarchy") {
  d <- spec$data
  r <- design_roles(spec)
  f_orig <- anova(stats::lm(spec$formula, data = d))
  terms <- names(spec$terms)
  alloc <- c(spec$treatment, spec$design)
  per_seed <- lapply(seeds, function(s) {
    m <- suppressWarnings(
      mask(d, r, mode = "local", seed = s, conditional = TRUE, ladder = ladder)
    )
    sy <- as.data.frame(synthetic(m))
    f_clone <- anova(stats::lm(spec$formula, data = sy))
    trt <- t(vapply(spec$treatment, function(tc) {
      mo <- design_level_means(d, tc, spec$outcome)
      ms <- design_level_means(sy, tc, spec$outcome)[names(mo)]
      c(
        corr = if (length(mo) > 2L) stats::cor(mo, ms) else NA_real_,
        ratio = stats::sd(ms) / stats::sd(mo),
        order = as.numeric(identical(names(which.max(mo)), names(which.max(ms))))
      )
    }, numeric(3)))
    list(
      alloc = all(vapply(alloc, function(cn) identical(sy[[cn]], d[[cn]]), logical(1))),
      na = identical(is.na(sy[[spec$outcome]]), is.na(d[[spec$outcome]])),
      F = stats::setNames(f_clone[terms, "F value"], terms),
      trt = trt,
      used = paste(recipe(m)@conditioning_used, collapse = " x "),
      shifted = paste(recipe(m)@conditioning_shifted, collapse = ", "),
      fallback = recipe(m)@fallback_frac
    )
  })
  F_clone <- do.call(rbind, lapply(per_seed, `[[`, "F"))
  trt <- simplify2array(lapply(per_seed, `[[`, "trt"))
  list(
    n = nrow(d),
    F_orig = stats::setNames(f_orig[terms, "F value"], terms),
    F_clone = apply(F_clone, 2, stats::median),
    alloc = all(vapply(per_seed, `[[`, logical(1), "alloc")),
    na = all(vapply(per_seed, `[[`, logical(1), "na")),
    trt_corr = apply(trt[, "corr", , drop = FALSE], 1, stats::median),
    trt_ratio = apply(trt[, "ratio", , drop = FALSE], 1, stats::median),
    trt_order = apply(trt[, "order", , drop = FALSE], 1, mean),
    used = per_seed[[1]]$used,
    shifted = per_seed[[1]]$shifted,
    fallback = per_seed[[1]]$fallback
  )
}

# Only terms the original detects (F >= 2) are graded. Treatments also keep the
# top level in most seeds (two levels only) and level spread within a factor 2.
design_verdict <- function(spec, res, f_floor = 0.5, corr_floor = 0.7) {
  kind <- spec$terms
  block_terms <- names(kind)[kind != "treatment"]
  block_ok <- vapply(block_terms, function(tm) {
    res$F_orig[[tm]] < 2 || res$F_clone[[tm]] >= f_floor * res$F_orig[[tm]]
  }, logical(1))
  trt_detected <- any(res$F_orig[names(kind)[kind == "treatment"]] >= 2)
  trt_ok <- vapply(seq_along(spec$treatment), function(i) {
    corr <- res$trt_corr[[i]]
    signal <- if (is.na(corr)) res$trt_order[[i]] > 0.5 else corr >= corr_floor
    (signal || !trt_detected) && res$trt_ratio[[i]] >= 0.5 && res$trt_ratio[[i]] <= 2
  }, logical(1))
  c(
    allocation = res$alloc, na_mask = res$na,
    blocking = all(block_ok), treatment = all(trt_ok)
  )
}
