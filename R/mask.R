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
#' @param mode Either `"local"` or `"collaborate"`. When omitted, inherit
#'   `attr(roles, "mode")`, falling back to `"local"` for a roles table with
#'   no mode provenance. An explicit collaborate-to-local downgrade raises a
#'   classed `masque_mode_downgrade` warning.
#' @param seed Optional integer for reproducibility.
#' @param clean Label and column-name hygiene before masking, passed to
#'   [clean_table()]: one of `"auto"` (default - trim whitespace and
#'   report near-duplicate labels), `"report"` (report only), or `"off"`
#'   (skip). Invalid column names are legalised in **every** mode -- an
#'   invalid name silently rewritten during synthesis corrupts the clone --
#'   and the repair is raised as a `masque_name_repaired` warning. The
#'   `roles` table's column references are remapped to the legalised names,
#'   the fixes are recorded in the recipe, and [apply_recipe()] /
#'   [unmask()] reverse them on the round-trip.
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
#'   are recorded on the recipe.
#'
#'   The stratum is chosen by a **coarsening ladder**. Treatment crossed
#'   with every retained design column is the finest rung, but on a
#'   replicated factorial that rung holds one row per cell, which is too
#'   thin to synthesise. The ladder then drops design columns, finest
#'   first, until the cells hold at least five rows; treatment columns are
#'   never dropped. Whatever remains below that floor is pooled into a
#'   global fallback. The rung reached is recorded on the recipe as
#'   `conditioning_used`, the pooled share as `fallback_frac`, and any
#'   coarsening or residual pooling raises a classed
#'   `masque_conditional_degraded` warning -- including the case where no
#'   treatment or design column survives at all, in which case the clone is
#'   the pooled copula.
#' @param coords Optional geographic-coordinate declaration. Supply one or more
#'   latitude/longitude pairs and each is coarsened in place by an on-land
#'   jitter (see [jitter_coordinates()]) instead of being copula-scrambled into
#'   implausible locations. A pair is a named vector `c(lat = "lat_col",
#'   lon = "lon_col")` or a named list that also carries jitter parameters
#'   (`by`, `method`, `min_km`, `max_km`, `sd_km`, `on_land`); pass several
#'   pairs as a list. Defaults to a donut of 5-20 km on land. One displacement
#'   is drawn per **site** and broadcast to that site's rows: `by` names the
#'   columns of `df` that identify a site, and is omitted when rows sharing an
#'   identical input coordinate already identify one. A declared pair always
#'   survives masking, coarsened; the recipe records the parameters and the site
#'   grouping it was coarsened under, and [apply_recipe()] retargets to the real
#'   coordinates.
#' @param allow_unmasked_coords Single logical. A masked table must not carry
#'   a real coordinate, so by default `mask()` **stops** when a column whose
#'   name says coordinate (`gps`, `lat`, `lon`, `easting`, ...) would be
#'   written through unmasked, and warns when a column detected only by the
#'   shape of its values would be. State otherwise by declaring the pair to
#'   `coords` (coarsened), giving the column a masking action (`drop` or
#'   `scramble`), or -- having decided the coordinate is not sensitive --
#'   setting this to `TRUE`, which is recorded on the recipe.
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
                 coords = NULL,
                 allow_unmasked_coords = FALSE,
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
  if (missing(mode)) {
    roles_mode <- attr(roles, "mode")
    if (is.null(roles_mode)) {
      cli::cli_warn(c(
        "No {.arg mode} was supplied and {.arg roles} carries no mode provenance.",
        "i" = paste0(
          "Defaulting to {.val local}. If this table was prepared for ",
          "{.val collaborate} or lost its attributes (for example via ",
          "{.fn data.table} or {.fn saveRDS}), pass {.code mode =} explicitly."
        )
      ), class = "masque_mode_unset")
      mode <- "local"
    } else {
      mode <- roles_mode
    }
  }
  mode <- match.arg(mode, c("local", "collaborate"))
  clean <- match.arg(clean)
  warnings_acc <- character()

  # Hygiene first. Column-name legalisation is applied in EVERY clean mode
  # (an invalid name silently rewritten during synthesis corrupts the clone
  # and breaks the round-trip), so `cl$data` always carries legal names and
  # the roles table's column references are remapped to match. Whitespace
  # trimming stays governed by the mode. clean_table() raises the
  # `masque_name_repaired` warning; the repair is also recorded here so it
  # lands in `recipe@warnings`.
  cl <- clean_table(df, clean = clean, quiet = TRUE)
  df <- cl$data
  roles <- .remap_roles_cols(roles, cl$name_map)
  cleaning_rec <- if (length(cl$name_map) || length(cl$level_fixes) ||
    nrow(cl$near_duplicates)) {
    .cleaning_record(cl)
  } else {
    NULL
  }
  if (length(cl$name_map)) {
    warnings_acc <- c(warnings_acc, .name_repair_message(cl$name_map))
  }

  roles <- roles_validate(roles, df, mode = mode)
  roles <- roles[match(names(df), roles$col), , drop = FALSE]

  # Coordinate columns declared in `coords` are coarsened by an on-land jitter
  # after synthesis, so they must survive it: force them to `keep` (bypassing
  # the copula, which would smear a lat/lon pair into implausible locations).
  coord_specs <- .normalise_coords(coords, df)
  coord_cols <- .coord_cols(coord_specs)
  if (length(coord_cols)) {
    roles$action[roles$col %in% coord_cols] <- "keep"
  }

  # A masked table must not carry a real coordinate unless the caller has
  # said so. Runs after `coords` is resolved, so a declared pair -- which is
  # coarsened below -- is not caught by its own declaration.
  if (!is.logical(allow_unmasked_coords) ||
    length(allow_unmasked_coords) != 1L) {
    cli::cli_abort("`allow_unmasked_coords` must be a single logical.")
  }
  .guard_unmasked_coords(df, roles, coord_cols, allow_unmasked_coords)

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
  if (isTRUE(conditional) && !length(conditioning_cols)) {
    msg <- paste0(
      "conditional = TRUE but no treatment or design column survives to ",
      "condition on; numeric synthesis falls back to the global copula."
    )
    # Classed, like every other degradation in the package, so a caller
    # (or an orchestration node) can catch the loss of conditional
    # fidelity instead of matching on the message text. The ladder's own
    # degradation below carries the same class.
    warning(warningCondition(msg, class = "masque_conditional_degraded"))
    warnings_acc <- c(warnings_acc, msg)
  }

  result <- with_rng_state(
    seed,
    .mask_orchestrate(df, roles, mode, opts, .shared_maps, conditional)
  )
  synth <- result$synth
  level_maps <- result$level_maps
  warnings_acc <- c(warnings_acc, result$warnings)

  # Conditional clone: report what the conditioning ladder actually
  # reached. A dropped rung or a residual pooled fraction means the clone
  # is less conditional than the call asked for, and that has to be said
  # out loud -- the recipe would otherwise assert `conditional = TRUE`
  # over a pooled copula.
  cond_report <- result$conditional
  conditioning_used <- if (is.null(cond_report)) {
    conditioning_cols
  } else {
    cond_report$used
  }
  fallback_frac <- if (is.null(cond_report)) {
    if (isTRUE(conditional)) 0 else NA_real_
  } else {
    cond_report$fallback_frac
  }
  if (!is.null(cond_report)) {
    deg_msg <- .conditional_degrade_message(cond_report)
    if (!is.null(deg_msg)) {
      warning(warningCondition(
        deg_msg,
        class = "masque_conditional_degraded"
      ))
      warnings_acc <- c(warnings_acc, deg_msg)
    }
  }

  # NA-mask preservation cell-by-cell (only over columns retained)
  retained <- intersect(names(df), names(synth))
  for (col in retained) {
    nm <- is.na(df[[col]])
    if (any(nm)) {
      synth[[col]][nm] <- NA
    }
  }

  # Coarsen declared coordinate columns in place, before the audit sees them
  # and before any column-name aliasing. The jitter is irreversible by design;
  # the recipe records that it happened (in `warnings`), and `apply_recipe()`
  # retargets a pipeline to the real coordinates.
  coord_reports <- list()
  if (length(coord_specs)) {
    coord_out <- .apply_coord_jitter(synth, coord_specs, seed, original = df)
    synth <- coord_out$df
    coord_reports <- coord_out$reports
    warnings_acc <- c(warnings_acc, sprintf(
      "coordinates coarsened in place by an on-land jitter: %s.",
      paste(coord_cols, collapse = ", ")
    ))
    warnings_acc <- c(warnings_acc, vapply(
      coord_reports, .coord_report_line, character(1)
    ))
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
      coords          = coord_reports,
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
    conditioning_used = conditioning_used,
    fallback_frac     = fallback_frac,
    column_name_map   = column_name_map,
    level_maps        = level_maps,
    storage_classes   = storage_classes,
    factor_meta       = factor_meta,
    cleaning          = cleaning_rec,
    coords            = coord_reports,
    allow_unmasked_coords = isTRUE(allow_unmasked_coords),
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

# Internal: the advisory for a conditional clone that did not get the
# stratum it asked for. Returns NULL when the finest conditioning set was
# used and no row fell into the pooled fallback -- the only case in which
# `conditional = TRUE` means exactly what it says.
.conditional_degrade_message <- function(report) {
  dropped <- report$dropped
  frac <- report$fallback_frac
  if (!length(dropped) && (!is.finite(frac) || frac <= 0)) {
    return(NULL)
  }
  parts <- character()
  if (length(dropped)) {
    parts <- c(parts, sprintf(
      paste0(
        "conditional = TRUE: cells of the finest conditioning stratum held ",
        "fewer than %d rows, so the ladder coarsened it by dropping %s. ",
        "Conditioning on: %s."
      ),
      report$min_stratum,
      paste(dropped, collapse = ", "),
      if (length(report$used)) {
        paste(report$used, collapse = " x ")
      } else {
        "nothing (pooled copula)"
      }
    ))
  }
  if (is.finite(frac) && frac > 0) {
    parts <- c(parts, sprintf(
      paste0(
        "%.1f%% of rows still sit in strata below %d rows and are pooled ",
        "into the global fallback; their conditional fidelity degrades ",
        "toward the marginal clone."
      ),
      100 * frac, report$min_stratum
    ))
  }
  paste(parts, collapse = " ")
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
  conditional_report <- NULL
  if (length(num_idx) >= 1L) {
    x_num <- df[, num_idx, drop = FALSE]
    if (isTRUE(conditional)) {
      conditional_report <- .conditioning_ladder(
        df,
        cond_cols    = .conditioning_cols(roles),
        protect_cols = roles$col[role == "treatment" & action != "drop"],
        min_stratum  = .MIN_STRATUM
      )
      x_num_new <- synthesise_numeric_conditional(
        x_num, conditional_report$groups,
        min_stratum = .MIN_STRATUM
      )
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

  list(
    synth       = synth,
    level_maps  = level_maps,
    warnings    = warnings,
    conditional = conditional_report
  )
}

# Minimum rows a stratum needs before the conditional clone will fit a
# stratum-local copula in it. Four rows cannot support an empirical
# marginal, let alone a joint one; the ladder in
# .conditioning_ladder() coarsens the conditioning set rather than
# accepting cells below this floor.
.MIN_STRATUM <- 5L

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
