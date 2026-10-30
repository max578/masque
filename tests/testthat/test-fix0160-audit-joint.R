# F10 and F20: the audit grades re-identification on excess over a
# permutation baseline, per column and jointly, and the joint verdicts feed the
# collaborate HIGH gate.

.joint_roles <- function(df, spec, mode = "collaborate") {
  r <- propose_roles(df, mode = mode)
  for (col in names(spec)) {
    parts <- strsplit(spec[[col]], "/", fixed = TRUE)[[1L]]
    r <- if (length(parts) == 2L) {
      set_role(r, col, role = parts[1L], action = parts[2L])
    } else {
      set_role(r, col, role = parts[1L])
    }
  }
  r
}

.joint_mask <- function(df, spec, mode = "collaborate", ...) {
  mask(df, .joint_roles(df, spec, mode), mode = mode, ...)
}

.alpha_spec <- c(
  plot = "id", rep = "design/keep", block = "design/keep",
  row = "design/keep", col = "design/keep", gen = "treatment",
  yield = "outcome"
)

# Six trials x 20 genotypes x 3 reps, with a trial-level soil and aet.
.joint_met <- function(sizes = NULL) {
  set.seed(1L)
  trials <- sprintf("T%d", 1:6)
  gens <- sprintf("G%02d", 1:20)
  g <- expand.grid(
    genotype = gens, rep = 1:3, trial = trials,
    stringsAsFactors = FALSE, KEEP.OUT.ATTRS = FALSE
  )
  g$block <- sprintf("B%d", (seq_len(nrow(g)) - 1L) %/% 5L %% 4L + 1L)
  g$yield <- round(3 + rnorm(nrow(g), 0, 0.5), 2)
  g$aet <- c(312.456, 287.901, 401.233, 355.678, 298.112, 376.543)[
    match(g$trial, trials)
  ]
  g$plot_cov <- round(rnorm(nrow(g), 50, 8), 2)
  g$soil <- c("clay", "loam", "sand", "clay", "loam", "sand")[
    match(g$trial, trials)
  ]
  if (!is.null(sizes)) {
    keep <- unlist(lapply(seq_along(trials), function(i) {
      utils::head(which(g$trial == trials[i]), sizes[i])
    }))
    g <- g[keep, , drop = FALSE]
  }
  g
}

.met_spec <- c(
  trial = "design/keep", rep = "design/keep", block = "design/keep",
  genotype = "treatment", yield = "outcome", aet = "covariate",
  plot_cov = "covariate", soil = "covariate"
)

.joint_clinical <- function(n = 200L) {
  set.seed(7L)
  data.frame(
    arm = factor(sample(c("A", "B"), n, TRUE)),
    age = round(rnorm(n, 64, 10)),
    sex = factor(sample(c("F", "M"), n, TRUE)),
    diagnosis = factor(sample(c("C50", "C34", "C18", "C61", "C25"), n, TRUE)),
    stage = factor(sample(c("I", "II", "III", "IV"), n, TRUE)),
    biomarker = round(rlnorm(n, 2, 0.6), 2),
    time_to_death = round(rexp(n, 1 / 9), 1),
    progressed = rbinom(n, 1L, 0.65),
    died = rbinom(n, 1L, 0.5)
  )
}

.clinical_spec <- c(
  arm = "treatment", age = "covariate", sex = "covariate",
  diagnosis = "covariate", stage = "covariate", biomarker = "covariate",
  time_to_death = "outcome", progressed = "outcome", died = "outcome"
)

# Two visible categorical covariates with 13 single-row crosses and no
# single-row level.
.rare_table <- function() {
  set.seed(99L)
  n <- 200L
  region <- sprintf("R%02d", rep(1:10, each = 20L))
  occupation <- sprintf("O%02d", rep(1:10, 20L))
  for (k in 1:15) occupation[k * 13L] <- sprintf("O%02d", (k * 7L) %% 10L + 1L)
  data.frame(
    arm = factor(sample(c("A", "B"), n, TRUE)),
    region = region, occupation = occupation,
    score = round(rnorm(n), 2)
  )
}

# Variable names never match a column name: under data.table semantics a
# clash would compare the column with itself.
.joint_row_of <- function(audit, which_check) {
  j <- attr(audit, "joint")
  j[j[["check"]] == which_check, , drop = FALSE]
}

test_that("the audit keeps its columns, adds the same-row figures and a joint table", {
  m <- .joint_mask(.joint_clinical(), .clinical_spec, seed = 1L)
  a <- audit_mask(m, print = FALSE)
  expect_identical(names(a)[1:13], c(
    "col", "role", "action", "kind", "leakage_class",
    "n_unique_levels", "freq_min", "exact_match_pct", "comparable_n",
    "na_pct", "na_pattern_uniqueness", "alias_status", "notes"
  ))
  expect_identical(
    names(a)[14:16], c("same_row_pct", "baseline_pct", "excess_pct")
  )
  joint <- attr(a, "joint")
  expect_s3_class(joint, "data.table")
  expect_named(joint, c(
    "check", "cols", "observed", "baseline", "excess", "sd",
    "leakage_class", "notes"
  ))
  expect_true(all(c("same_row_joint", "whole_row") %in% joint$check))
  printed <- capture_full(audit_mask(m))
  expect_match(printed, "Table-level checks", fixed = TRUE)
})

test_that("same-row figures compare in the original label space against sum(p^2)", {
  df <- .joint_clinical()
  m <- .joint_mask(df, .clinical_spec, seed = 2L)
  a <- audit_mask(m, print = FALSE)
  map <- recipe(m)@level_maps$stage
  expect_false(is.null(map))
  back <- names(map)[match(as.character(synthetic(m)$stage), unname(map))]
  row <- a[a$col == "stage", ]
  expect_equal(row$same_row_pct, 100 * mean(back == as.character(df$stage)))
  p <- prop.table(table(df$stage))
  expect_equal(row$baseline_pct, 100 * sum(p^2))
  expect_equal(row$excess_pct, row$same_row_pct - row$baseline_pct)
  # Continuous numerics keep exact_match_pct and carry no same-row figure.
  expect_true(is.na(a$same_row_pct[a$col == "biomarker"]))
})

test_that("a 0/1 outcome is graded on its excess over chance, not its raw match", {
  df <- .joint_clinical()
  for (seed in 1:5) {
    m <- .joint_mask(df, .clinical_spec, seed = seed)
    a <- audit_mask(m, print = FALSE)
    for (column in c("progressed", "died")) {
      row <- a[a[["col"]] == column, ]
      # The raw match sits near one half, as it does for any 0/1 column.
      expect_gt(row$exact_match_pct, 30)
      expect_equal(row$leakage_class, "low", info = paste(column, seed))
      expect_false(grepl("exact-match", row$notes, fixed = TRUE))
    }
  }
})

test_that("ordinary collaborate clones raise no HIGH from the new rules", {
  skip_if_not_installed("agridat")
  alpha <- agridat::john.alpha
  met <- .joint_met()
  clinical <- .joint_clinical()
  visible <- .clinical_spec
  visible[c("sex", "diagnosis", "stage")] <- "covariate/scramble"
  cases <- list(
    list(alpha, .alpha_spec), list(met, .met_spec),
    list(clinical, .clinical_spec), list(clinical, visible)
  )
  for (case in cases) {
    for (conditional in c(FALSE, TRUE)) {
      for (seed in 1:3) {
        expect_no_warning(
          m <- .joint_mask(
            case[[1L]], case[[2L]], seed = seed, conditional = conditional
          ),
          class = "masque_high_leakage"
        )
        joint <- attr(m@audit, "joint")
        expect_false(any(joint$leakage_class == "high"))
        expect_identical(sum(m@audit$leakage_class == "high"), 0L)
      }
    }
  }
})

test_that("an outcome kept as-is trips the joint checks and blocks the write", {
  skip_if_not_installed("agridat")
  spec <- .alpha_spec
  spec["yield"] <- "outcome/keep"
  w <- expect_warning(
    m <- .joint_mask(agridat::john.alpha, spec, seed = 1L),
    class = "masque_high_leakage"
  )
  expect_match(conditionMessage(w), "[same-row joint match]", fixed = TRUE)
  expect_match(conditionMessage(w), "[whole-row match]", fixed = TRUE)
  srj <- .joint_row_of(m@audit, "same_row_joint")
  expect_identical(srj$leakage_class, "high")
  expect_gt(srj$excess, 90)
  expect_identical(.joint_row_of(m@audit, "whole_row")$leakage_class, "high")
  # No column rule reaches HIGH: the joint verdict alone blocks the write.
  expect_false(any(m@audit$leakage_class == "high"))
  expect_gt(masque:::.audit_tally(m)[["high"]], 0L)
  expect_identical(masque:::.release_status(m), "blocked")
  expect_error(masque:::.gate_release(m), class = "masque_blocked_write")

  out <- file.path(tempdir(), "masque-joint-blocked.csv")
  on.exit(unlink(out), add = TRUE)
  expect_error(
    suppressWarnings(masque(
      agridat::john.alpha,
      roles = .joint_roles(agridat::john.alpha, spec), mode = "collaborate",
      seed = 1L, ask = FALSE, quiet = TRUE, out = out
    )),
    class = "masque_blocked_write"
  )
  expect_false(file.exists(out))
})

test_that("a kept 0/1 outcome trips the same-row joint check", {
  df <- .joint_clinical()[, c("arm", "progressed")]
  expect_warning(
    m <- .joint_mask(
      df, c(arm = "treatment", progressed = "outcome/keep"), seed = 1L
    ),
    class = "masque_high_leakage"
  )
  expect_identical(
    .joint_row_of(m@audit, "same_row_joint")$leakage_class, "high"
  )
})

test_that("visible covariates with single-row crosses trip the rarity check", {
  df <- .rare_table()
  # No single level is rare, so the single-column rule cannot see it.
  expect_gt(min(table(df$region)), 1L)
  expect_gt(min(table(df$occupation)), 1L)
  spec <- c(
    arm = "treatment", region = "covariate/keep",
    occupation = "covariate/keep", score = "outcome"
  )
  w <- expect_warning(
    m <- .joint_mask(df, spec, seed = 1L),
    class = "masque_high_leakage"
  )
  expect_match(conditionMessage(w), "[rare category cross]", fixed = TRUE)
  rare <- .joint_row_of(m@audit, "rare_cross")
  expect_identical(rare$leakage_class, "high")
  expect_identical(rare$observed, 13)
  expect_lt(rare$baseline, rare$observed)

  # Scrambled, the same columns sit at chance.
  spec[c("region", "occupation")] <- "covariate/scramble"
  for (seed in 1:3) {
    expect_no_warning(
      m2 <- .joint_mask(df, spec, seed = seed),
      class = "masque_high_leakage"
    )
    expect_false(
      .joint_row_of(m2@audit, "rare_cross")$leakage_class == "high"
    )
  }
  # Aliased labels are not visible and are left out of the cross.
  spec[c("region", "occupation")] <- "covariate/alias"
  m3 <- .joint_mask(df, spec, seed = 1L)
  expect_identical(nrow(.joint_row_of(m3@audit, "rare_cross")), 0L)
})

test_that("local mode reports the joint verdicts without grading them", {
  skip_if_not_installed("agridat")
  spec <- .alpha_spec
  spec["yield"] <- "outcome/keep"
  roles <- .joint_roles(agridat::john.alpha, spec, mode = "local")
  m <- mask(agridat::john.alpha, roles, mode = "local", seed = 1L)
  a <- audit_mask(m, original = agridat::john.alpha, print = FALSE)
  srj <- .joint_row_of(a, "same_row_joint")
  expect_identical(srj$leakage_class, "low")
  expect_gt(srj$excess, 90)
  expect_match(srj$notes, "HIGH in collaborate mode", fixed = TRUE)
  expect_no_error(masque:::.gate_release(m))
})

test_that("unequal unit sizes add a note that is never graded", {
  met <- .joint_met(sizes = c(60L, 60L, 45L, 60L, 30L, 60L))
  m <- .joint_mask(met, .met_spec, seed = 1L)
  note <- .joint_row_of(m@audit, "unit_sizes")
  expect_identical(nrow(note), 1L)
  expect_true("trial" %in% strsplit(note$cols, ", ", fixed = TRUE)[[1L]])
  expect_identical(note$leakage_class, "info")
  expect_match(note$notes, "public trial list", fixed = TRUE)
  expect_identical(masque:::.release_status(m) == "blocked", FALSE)

  balanced <- .joint_mask(.joint_met(), .met_spec, seed = 1L)
  expect_identical(nrow(.joint_row_of(balanced@audit, "unit_sizes")), 0L)
})

test_that("the joint baselines leave the caller's RNG alone and repeat exactly", {
  df <- .joint_clinical()
  m <- .joint_mask(df, .clinical_spec, mode = "local", seed = 3L)
  set.seed(42L)
  before <- .Random.seed
  a1 <- audit_mask(m, original = df, print = FALSE)
  expect_identical(.Random.seed, before)
  a2 <- audit_mask(m, original = df, print = FALSE)
  expect_identical(attr(a1, "joint"), attr(a2, "joint"))
})

test_that("a linked column is held fixed like a design column", {
  set.seed(5L)
  tables <- list(
    plots = data.frame(
      site = rep(c("S1", "S2", "S3"), each = 20L),
      gen = rep(sprintf("G%02d", 1:10), 6L),
      yield = round(rnorm(60L, 4, 0.5), 2)
    ),
    soils = data.frame(
      site = rep(c("S1", "S2", "S3"), 10L),
      ph = round(rnorm(30L, 6.5, 0.4), 2)
    )
  )
  roles <- list(
    plots = .joint_roles(tables$plots, c(
      site = "design/alias", gen = "treatment", yield = "outcome"
    )),
    soils = .joint_roles(tables$soils, c(
      site = "covariate/alias", ph = "outcome"
    ))
  )
  expect_no_warning(
    ms <- mask_set(
      tables, roles = roles, mode = "collaborate", seed = 1L, quiet = TRUE
    ),
    class = "masque_high_leakage"
  )
  soils <- ms@audit$soils
  # The shared map relabels in place: the link returns to its row by design.
  expect_identical(soils$same_row_pct[soils[["col"]] == "site"], 100)
  expect_identical(soils$leakage_class[soils[["col"]] == "site"], "low")
  expect_identical(.joint_row_of(soils, "same_row_joint")$cols, "ph")
  local_audit <- audit_mask(
    mask_set(tables, roles = lapply(roles, function(r) {
      attr(r, "mode") <- "local"
      r
    }), mode = "local", seed = 1L, quiet = TRUE),
    original = tables, print = FALSE
  )
  expect_identical(
    .joint_row_of(local_audit$soils, "same_row_joint")$cols, "ph"
  )
})

test_that("observed joint shares equal a brute-force count in label space", {
  skip_if_not_installed("agridat")
  # Row keys pasted from the original labels: an independent route to the
  # same two shares, for a unique design key and for a shared one.
  brute <- function(df, m, fixed, content) {
    syn <- as.data.frame(synthetic(m))
    for (col in names(recipe(m)@level_maps)) {
      map <- recipe(m)@level_maps[[col]]
      syn[[col]] <- names(map)[match(as.character(syn[[col]]), unname(map))]
    }
    key <- function(d, cols) {
      do.call(paste, c(lapply(d[cols], as.character), sep = "\r"))
    }
    all_cols <- c(fixed, content)
    c(
      same_row_joint = 100 * mean(key(syn, content) == key(df, content)),
      whole_row = 100 * mean(key(syn, all_cols) %in% key(df, all_cols))
    )
  }
  spec <- .alpha_spec
  spec["yield"] <- "outcome/keep"
  alpha <- agridat::john.alpha
  m1 <- suppressWarnings(.joint_mask(alpha, spec, seed = 4L))
  visible <- .clinical_spec
  visible[c("sex", "diagnosis", "stage")] <- "covariate/scramble"
  clinical <- .joint_clinical()[, c("arm", "sex", "diagnosis", "stage")]
  m2 <- .joint_mask(clinical, visible[names(clinical)], seed = 4L)
  cases <- list(
    list(alpha, m1, c("rep", "block", "gen", "row", "col"), "yield"),
    list(clinical, m2, "arm", c("sex", "diagnosis", "stage"))
  )
  for (case in cases) {
    expected <- brute(case[[1L]], case[[2L]], case[[3L]], case[[4L]])
    joint <- attr(case[[2L]]@audit, "joint")
    got <- stats::setNames(joint$observed, joint$check)
    expect_equal(got[["same_row_joint"]], expected[["same_row_joint"]])
    expect_equal(got[["whole_row"]], expected[["whole_row"]])
  }
})
