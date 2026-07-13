#' Mask a tabular dataset into a structurally faithful development surrogate
#'
#' Takes one data frame and a user-edited `roles` table (from
#' [propose_roles()], possibly adjusted with [set_role()]) and produces
#' a synthetic clone according to each column's `action`. Returns a
#' `masque` S7 object holding the synthetic data and a private
#' `masque_recipe`.
#'
#' `mode = "local"` marks the synthetic for owner development only; the
#' reminder is recorded on the recipe and shown when the object prints.
#' `mode = "collaborate"` additionally jitters re-simulated numerics
#' within their measurement resolution (stochastically rounding
#' integers) and runs [audit_mask()] automatically; a HIGH finding is
#' raised as a classed warning (`masque_high_leakage`) and blocks the
#' package-managed writers ([masque()]'s `out`, [write_set()]) until it
#' is resolved or explicitly overridden. Which columns are aliased,
#' kept, or dropped is decided by the `action` column of `roles` -
#' [propose_roles()] resolves mode-appropriate defaults, so the table
#' you reviewed is the plan that runs.
#'
#' Collaborate mode adjusts the transformations and runs the audit; it
#' does not model where the output will go. Whether a synthetic table is
#' appropriate for a given collaborator, environment, or jurisdiction is
#' a release decision that stays with the data custodian - masque
#' informs that decision, it does not make it.
#'
#' @section Behaviour by action:
#'
#' \describe{
#'   \item{`keep`}{Byte-identical pass-through, both modes.}
#'   \item{`scramble`}{Numeric outcome / covariate columns are
#'     re-simulated jointly via a Gaussian copula on the global Pearson
#'     covariance, with empirical-quantile marginals. Categorical, date,
#'     and text columns are row-permuted within non-NA positions, class
#'     preserved. Treatment columns get a seeded label permutation -
#'     the assignment structure never moves.}
#'   \item{`alias`}{As `scramble` where applicable, plus opaque label
#'     substitution: treatments become `trt_NNN` (`<col>_trt_NNN` when
#'     two or more treatment factors are aliased), categorical
#'     covariates `<col>_LNNN`, design labels `<col>_DNNN` (in place -
#'     structure intact), ids `<col>_INNN` (in place - row linkage
#'     intact), text values `<col>_TNNN`.}
#'   \item{`drop`}{Column excluded from the synthetic, both modes.}
#' }
#'
#' The NA mask of every retained column is preserved cell-by-cell. RNG
#' state is preserved across the call.
#'
#' @param df A data frame.
#' @param roles A roles table from [propose_roles()] (possibly edited).
#'   Tables from masque <= 0.5.0 are upgraded with a deprecation
#'   warning; see [roles_validate()].
#' @param mode Either `"local"` (default) or `"collaborate"`.
#' @param seed Optional integer for reproducibility.
#' @param clean Column-name and label hygiene before masking, passed to
#'   [clean_table()]: one of `"auto"` (default - legalise names, trim
#'   whitespace, report near-duplicates), `"report"`, or `"off"`. When
#'   names are legalised, the `roles` table's column references are
#'   remapped to match, so a `roles` table built against the dirty names
#'   still applies. The fixes are recorded in the recipe and re-applied
#'   by [apply_recipe()].
#' @param alias_names Hide the column names themselves. `FALSE` (the
#'   default) keeps them. `TRUE` replaces every retained column name with
#'   an opaque alias (`col_001`, `col_002`, ... in column order). A
#'   character vector names just the columns to alias. The
#'   original-to-alias map is stored in the recipe and inverted by
#'   [apply_recipe()] / [unmask()], so a pipeline written against the
#'   aliased synthetic round-trips. Column names are the last identifying
#'   surface a kept or design column exposes; alias them when even the
#'   schema is sensitive.
#' @param conditional Logical scalar (default `FALSE`). The
#'   *collaborate-grade conditional clone*. When `FALSE`, scrambled
#'   numeric columns are re-simulated from one global Gaussian copula -
#'   marginals and global covariance survive, but the treatment-to-outcome
#'   relationship does not, so a causal model fitted on the clone recovers
#'   a null effect. When `TRUE`, the numeric block is re-simulated *within
#'   each treatment-by-design stratum*, so a row's synthetic outcome
#'   inherits the location of the treatment that row carries. A causal
#'   model fitted on the conditional clone recovers the real treatment
#'   effect within sampling tolerance - the data-side analogue of
#'   preserving a conditional mean embedding rather than a pooled
#'   marginal. The conditioning columns (treatment plus retained design)
#'   are recorded on the recipe. With no treatment or design column to
#'   condition on, the path degrades cleanly to the global copula and a
#'   note is emitted.
#' @param .shared_maps Internal. A named list of pre-computed
#'   `original -> alias` level maps for cross-table linked columns, set
#'   by [mask_set()]. Not for direct use.
#' @param ... Must be empty. An unused argument (for example a
#'   misspelled name) errors rather than being silently ignored.
#'
#' @return A `masque` S7 object. Use [synthetic()] and [recipe()] to
#'   extract the components.
#'
#' @examples
#' r <- propose_roles(iris)
#' r <- set_role(r, "Sepal.Length", role = "outcome")
#' m <- mask(iris, r, seed = 1)
#' head(synthetic(m))
#'
#' @seealso [propose_roles()], [set_role()], [roles_validate()],
#'   [synthetic()], [recipe()], [reveal_maps()].
#'
#' @export
mask <- function(df,
                 roles,
                 mode = c("local", "collaborate"),
                 seed = NULL,
                 clean = c("auto", "report", "off"),
                 alias_names = FALSE,
                 conditional = FALSE,
                 .shared_maps = list(),
                 ...) {
  # A misspelled argument silently swallowed by `...` looks like success;
  # error on anything unused.
  if (...length() > 0L) {
    dot_names <- names(list(...))
    dot_names <- dot_names[nzchar(dot_names)]
    unused <- if (length(dot_names)) {
      paste0(" ", paste0("`", dot_names, "`", collapse = ", "))
    } else {
      ""
    }
    label <- if (...length() == 1L) "argument" else "arguments"
    cli::cli_abort(c(
      paste0("Unused ", label, unused, " passed to `mask()`."),
      i = "Check for misspelled argument names."
    ))
  }

  # Belt-and-braces RNG hygiene: any RNG perturbation inside mask() is
  # rolled back when the function exits, regardless of which path produced
  # it. The inner with_rng_state still controls per-step reproducibility.
  withr::local_preserve_seed()

  if (!is.data.frame(df)) {
    cli::cli_abort("`df` must be a data frame; got {.cls {class(df)[1]}}.")
  }
  if (!is.logical(conditional) || length(conditional) != 1L ||
    is.na(conditional)) {
    cli::cli_abort("`conditional` must be a single `TRUE` or `FALSE`.")
  }
  mode <- match.arg(mode)
  clean <- match.arg(clean)

  # Hygiene first: legalise names + trim whitespace, then remap the roles
  # table's column references so a roles table built against the dirty
  # names still applies. `report` / `off` leave df and roles untouched.
  cl <- clean_table(df, clean = clean, quiet = TRUE)
  cleaning_rec <- NULL
  if (identical(clean, "auto") &&
    (length(cl$name_map) || length(cl$level_fixes))) {
    df <- cl$data
    roles <- .remap_roles_cols(roles, cl$name_map)
    cleaning_rec <- .cleaning_record(cl)
  } else if (nrow(cl$near_duplicates) || length(cl$name_map) ||
    length(cl$level_fixes)) {
    # report mode (or auto with nothing applied): still note what was seen.
    cleaning_rec <- .cleaning_record(cl)
  }

  roles <- roles_validate(roles, df, mode = mode)
  roles <- roles[match(names(df), roles$col), , drop = FALSE]

  opts <- mode_defaults(mode)

  # Conditional clone bookkeeping: resolve the conditioning columns once
  # so they can be recorded on the recipe, and warn early if a conditional
  # clone was requested but nothing is available to condition on (it then
  # degrades to the global copula, which is the non-conditional default).
  conditioning_cols <- if (isTRUE(conditional)) {
    .conditioning_cols(roles)
  } else {
    character()
  }
  warnings_acc <- character()
  if (isTRUE(conditional) && !length(conditioning_cols)) {
    msg <- paste0(
      "conditional = TRUE but no treatment or design column survives to ",
      "condition on; numeric synthesis falls back to the global copula."
    )
    cli::cli_warn(msg)
    warnings_acc <- c(warnings_acc, msg)
  }

  result <- with_rng_state(
    seed,
    .mask_orchestrate(df, roles, mode, opts, .shared_maps, conditional)
  )
  synth <- result$synth
  level_maps <- result$level_maps
  warnings_acc <- c(warnings_acc, result$warnings)

  # NA-mask preservation cell-by-cell (only over columns retained)
  retained <- intersect(names(df), names(synth))
  for (col in retained) {
    nm <- is.na(df[[col]])
    if (any(nm)) {
      synth[[col]][nm] <- NA
    }
  }

  # Local mode: the owner-development reminder is recorded on the recipe
  # and shown when the object prints / summarises. It is deliberately NOT
  # a warning() - an unconditional advisory on every call trains callers
  # to blanket-suppress, which then also swallows the genuine
  # HIGH-leakage warning below (the v0.7.x guided-flow defect).
  if (identical(mode, "local")) {
    warnings_acc <- c(warnings_acc, paste0(
      "local mode: synthetic data is for owner development only, ",
      "not external sharing."
    ))
  }

  # Collaborate mode: auto-run audit and propagate high-leakage warnings
  audit_tbl <- NULL
  if (identical(mode, "collaborate")) {
    # Audit needs a temporary synth-as-tibble + a temporary recipe with the
    # level_maps we collected so far.
    .tmp_rec <- masque_recipe(
      masque_version  = as.character(utils::packageVersion("masque")),
      created_at      = Sys.time(),
      mode            = mode,
      seed            = if (is.null(seed)) NULL else as.integer(seed),
      roles           = .strip_roles_provenance(as.data.frame(roles)),
      column_name_map = NULL,
      level_maps      = level_maps,
      storage_classes = list(),
      factor_meta     = list(),
      warnings        = character(),
      integrity_fp    = ""
    )
    audit_tbl <- .compute_audit(df, synth, .tmp_rec, mode)
    high_leaks <- audit_tbl$col[audit_tbl$leakage_class == "high"]
    if (length(high_leaks)) {
      msg <- sprintf(
        "audit_mask() flagged HIGH leakage on column(s): %s",
        paste(high_leaks, collapse = ", ")
      )
      # Classed so callers can handle it programmatically; safety
      # findings are never suppressed by package code.
      warning(warningCondition(msg, class = "masque_high_leakage"))
      warnings_acc <- c(warnings_acc, msg)
    }
  }

  # Column-name aliasing (after the audit, which is keyed on the real
  # column names). Renames the synthetic's columns to opaque aliases and
  # records the map so apply_recipe() / unmask() invert it.
  column_name_map <- .build_column_name_map(names(synth), alias_names)
  if (!is.null(column_name_map)) {
    nm <- names(synth)
    hits <- nm %in% names(column_name_map)
    nm[hits] <- unname(unlist(column_name_map[nm[hits]]))
    names(synth) <- nm
  }

  # Build the recipe.
  storage_classes <- lapply(df, function(col) class(col))

  factor_meta <- list()
  for (col in names(df)) {
    if (is.factor(df[[col]])) {
      factor_meta[[col]] <- list(
        levels  = levels(df[[col]]),
        ordered = is.ordered(df[[col]])
      )
    }
  }

  rec <- masque_recipe(
    masque_version    = as.character(utils::packageVersion("masque")),
    created_at        = Sys.time(),
    mode              = mode,
    seed              = if (is.null(seed)) NULL else as.integer(seed),
    roles             = .strip_roles_provenance(as.data.frame(roles)),
    conditional       = conditional,
    conditioning_cols = conditioning_cols,
    column_name_map   = column_name_map,
    level_maps        = level_maps,
    storage_classes   = storage_classes,
    factor_meta       = factor_meta,
    cleaning          = cleaning_rec,
    warnings          = warnings_acc,
    integrity_fp      = digest::digest(is.na(df), algo = "sha256")
  )

  masque_obj(
    synthetic = tibble::as_tibble(synth),
    recipe    = rec,
    mode      = mode,
    audit     = audit_tbl
  )
}

# Internal: resolve the alias_names argument to an original -> alias
# named list (or NULL when no columns are aliased). Aliases are
# `col_001`, `col_002`, ... in the order the columns appear in `cols`.
.build_column_name_map <- function(cols, alias_names) {
  target <- if (isTRUE(alias_names)) {
    cols
  } else if (is.character(alias_names)) {
    unknown <- setdiff(alias_names, cols)
    if (length(unknown)) {
      cli::cli_abort(c(
        "`alias_names` names column(s) not in the synthetic output: ",
        x = "{.field {unknown}}",
        i = paste0(
          "Dropped columns cannot be aliased. Available: ",
          "{.val {cols}}."
        )
      ))
    }
    alias_names
  } else if (isFALSE(alias_names)) {
    return(NULL)
  } else {
    cli::cli_abort(
      "`alias_names` must be a single logical or a character vector."
    )
  }
  if (!length(target)) {
    return(NULL)
  }

  width <- max(3L, nchar(as.character(length(cols))))
  idx <- match(target, cols)
  aliases <- sprintf(paste0("col_%0", width, "d"), idx)
  as.list(stats::setNames(aliases, target))
}

# Internal: orchestrate the per-action synthesis with the RNG state
# already set. The action column is the authority; mode only modulates
# the numeric-jitter layer (via opts) and downstream audit behaviour.
# `conditional = TRUE` re-routes the numeric block through the stratified
# synthesiser so the treatment -> outcome map survives the clone.
.mask_orchestrate <- function(df, roles, mode, opts, shared_maps = list(),
                              conditional = FALSE) {
  synth <- df
  level_maps <- list()
  warnings <- character()

  action <- roles$action
  role <- roles$role
  kind <- roles$kind

  # Cross-table linked columns carry a pre-computed alias map (shared
  # across every table in the set so joins survive). Apply it in place
  # and exclude these columns from the per-table alias / permute blocks.
  shared_cols <- intersect(roles$col, names(shared_maps))
  for (col in shared_cols) {
    res <- .relabel_with_map(df[[col]], shared_maps[[col]])
    synth[[col]] <- res
    level_maps[[col]] <- shared_maps[[col]]
  }
  is_shared <- roles$col %in% shared_cols

  # Numeric block: every scrambled numeric column jointly via the
  # Gaussian copula. No outcome is required - role only orders the
  # audit's expectations, not the simulation.
  #
  # Conditional clone: when `conditional = TRUE`, fit and sample the
  # copula within each treatment x design stratum instead of pooling.
  # The synthetic outcomes then inherit each stratum's own location, so
  # the treatment -> outcome relationship a causal model reads survives
  # the clone. Plain (pooled) synthesis still runs when no conditioning
  # column is present, so the path degrades cleanly to the global copula.
  num_idx <- which(action == "scramble" & kind %in% .numeric_kinds() &
    !is_shared)
  if (length(num_idx) >= 1L) {
    x_num <- df[, num_idx, drop = FALSE]
    if (isTRUE(conditional)) {
      cond_cols <- .conditioning_cols(roles)
      groups <- .conditioning_groups(df, cond_cols)
      x_num_new <- synthesise_numeric_conditional(x_num, groups)
    } else {
      x_num_new <- synthesise_numeric_local(x_num)
    }
    # Collaborate mode: layer on within-resolution jitter + integer rounding
    if (isTRUE(opts$jitter_numeric)) {
      for (col in names(x_num_new)) {
        x_num_new[[col]] <- synthesise_numeric_collaborate(
          x_obs = df[[col]],
          x_new = x_num_new[[col]]
        )
      }
    }
    for (col in names(x_num_new)) {
      synth[[col]] <- x_num_new[[col]]
    }
  }

  # Row-permutation block: scrambled categorical / date / text columns
  # (treatment label permutation is handled separately - treatment
  # values never move rows).
  perm_idx <- which(
    action == "scramble" &
      kind %in% c(.categorical_kinds(), .date_kinds()) &
      role != "treatment" & !is_shared
  )
  for (j in perm_idx) {
    col <- roles$col[j]
    synth[[col]] <- synthesise_categorical_local(df[[col]])
  }

  # Treatment scramble: seeded label permutation in place.
  trt_perm_idx <- which(role == "treatment" & action == "scramble" &
    !is_shared)
  for (j in trt_perm_idx) {
    col <- roles$col[j]
    res <- permute_levels(df[[col]])
    synth[[col]] <- res$x
    level_maps[[col]] <- res$map
  }

  # Alias block. Treatments and design / id / text columns are aliased
  # in place (assignment, structure, and row linkage never move);
  # categorical covariates are row-permuted first, then aliased.
  #
  # Treatment prefix convention: a single aliased treatment keeps the
  # historical `trt_NNN` prefix for recipe stability; with two or more,
  # the column name is folded in (`<col>_trt_NNN`) so the opaque labels
  # stay distinct and self-documenting.
  trt_alias_idx <- which(role == "treatment" & action == "alias" &
    !is_shared)
  n_trt_alias <- length(trt_alias_idx)
  for (j in trt_alias_idx) {
    col <- roles$col[j]
    prefix <- if (n_trt_alias == 1L) "trt_" else paste0(col, "_trt_")
    res <- alias_levels(df[[col]], prefix = prefix)
    synth[[col]] <- res$x
    level_maps[[col]] <- res$map
  }

  inplace_alias_idx <- which(role %in% c("design", "id", "text") &
    action == "alias" & !is_shared)
  for (j in inplace_alias_idx) {
    col <- roles$col[j]
    tag <- c(design = "_D", id = "_I", text = "_T")[[role[j]]]
    x <- df[[col]]
    if (is.numeric(x)) {
      # Integer-like ids are aliased through their character form; the
      # map records original numerals so unmask() restores them.
      x <- as.character(x)
    }
    res <- alias_levels(x, prefix = paste0(col, tag))
    synth[[col]] <- res$x
    level_maps[[col]] <- res$map
  }

  cov_alias_idx <- which(role == "covariate" & action == "alias" &
    !is_shared)
  for (j in cov_alias_idx) {
    col <- roles$col[j]
    perm <- synthesise_categorical_local(df[[col]])
    res <- alias_levels(perm, prefix = paste0(col, "_L"))
    synth[[col]] <- res$x
    level_maps[[col]] <- res$map
  }

  # Drop block: explicit user intent, honoured in both modes. A linked
  # column (shared across the set) is never dropped here - it was already
  # aliased in place by the shared block so joins survive.
  drop_idx <- which(action == "drop" & !is_shared)
  if (length(drop_idx)) {
    dropped <- roles$col[drop_idx]
    synth <- synth[, setdiff(names(synth), dropped), drop = FALSE]
    warnings <- c(
      warnings,
      sprintf(
        "Dropped %d column(s) with action \"drop\": %s",
        length(dropped), paste(dropped, collapse = ", ")
      )
    )
  }

  list(synth = synth, level_maps = level_maps, warnings = warnings)
}

# Internal: relabel a vector through an explicit `original -> alias` map,
# preserving factor / character / logical type. Used for cross-table
# linked columns, where the map is shared rather than freshly generated.
# Numeric columns are stringified (their original numerals are the map
# keys), matching the in-place id-alias convention.
.relabel_with_map <- function(x, map) {
  if (is.factor(x)) {
    new_chr <- unname(map[as.character(x)])
    return(factor(new_chr, levels = unname(map)))
  }
  x_chr <- if (is.numeric(x)) as.character(x) else as.character(x)
  ifelse(is.na(x_chr), NA_character_, unname(map[x_chr]))
}
