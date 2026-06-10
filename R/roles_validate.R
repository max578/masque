#' Validate a roles table
#'
#' Fail-closed validation of a two-axis `roles` table before [mask()]
#' consumes it. Returns the validated table - with any `NA` actions
#' resolved to their (role, kind, mode) defaults - so callers can use
#' the return value directly.
#'
#' Tables produced by masque 0.5.0 and earlier (no `action` column;
#' v1 vocabulary with `keep` / `ignore` roles and the optional
#' `mask_levels` column) are upgraded in place with a deprecation
#' warning. The upgrade preserves the v1 semantics exactly: v1 `keep`
#' becomes action `keep`; v1 `ignore` becomes role `id` / `text` /
#' `other` with action `keep` in local mode and `drop` in collaborate
#' mode; v1 treatment `mask_levels = "permute"` becomes action
#' `scramble`.
#'
#' Hard errors:
#'
#' \itemize{
#'   \item missing required columns (`col`, `role`, `action`, `kind`);
#'   \item unknown role (not in `design`, `treatment`, `outcome`,
#'     `covariate`, `date`, `id`, `text`, `other`) or unknown action
#'     (not in `keep`, `scramble`, `alias`, `drop`);
#'   \item any `NA` role (an `NA` *action* is allowed - it resolves to
#'     the default for the row's role and kind);
#'   \item an incompatible (role, action, kind) combination, e.g.
#'     `design` + `scramble`, numeric + `alias`, `id` + `scramble`,
#'     `other` + anything but keep / drop;
#'   \item duplicate `col` entries;
#'   \item if `df` supplied: any `df` column missing from `roles`, or
#'     any `roles` column missing from `df`.
#' }
#'
#' Loud advisories (warnings, not errors):
#'
#' \itemize{
#'   \item every action is `keep` - the "synthetic" would equal the
#'     original byte-for-byte;
#'   \item the table was proposed for one mode but is being validated
#'     for another (actions are taken as-is; defaults are not
#'     re-resolved).
#' }
#'
#' @param roles A roles table from [propose_roles()] (possibly edited),
#'   or a v1 roles tibble (deprecated, upgraded with a warning).
#' @param df Optional data frame. If supplied, `roles` is checked for
#'   one-to-one column-name correspondence with `df`.
#' @param mode Optional mode (`"local"` or `"collaborate"`) used to
#'   resolve `NA` actions and to upgrade v1 tables. Defaults to
#'   `attr(roles, "mode")`, falling back to `"local"`.
#'
#' @return The validated (and possibly upgraded / resolved) roles
#'   table, invisibly.
#'
#' @examples
#' r <- propose_roles(iris)
#' r <- set_role(r, "Sepal.Length", role = "outcome")
#' roles_validate(r, iris)
#'
#' @seealso [propose_roles()], [set_role()].
#'
#' @export
roles_validate <- function(roles, df = NULL, mode = NULL) {
  if (!is.data.frame(roles)) {
    cli::cli_abort(
      "`roles` must be a data frame / tibble; got {.cls {class(roles)[1]}}."
    )
  }
  if (is.null(mode)) {
    mode <- attr(roles, "mode") %||% "local"
  }
  if (!(mode %in% c("local", "collaborate"))) {
    cli::cli_abort("`mode` must be {.val local} or {.val collaborate}.")
  }

  required <- c("col", "role")
  missing <- setdiff(required, names(roles))
  if (length(missing)) {
    cli::cli_abort("`roles` is missing required column(s): {.field {missing}}.")
  }

  if (any(is.na(roles$role))) {
    cli::cli_abort(
      paste0(
        "`roles$role` has NA value(s) for: ",
        "{.field {roles$col[is.na(roles$role)]}}."
      )
    )
  }

  # v1 tables (masque <= 0.5.0): no action column, keep/ignore vocabulary.
  if (!("action" %in% names(roles))) {
    if (!("kind" %in% names(roles))) {
      cli::cli_abort(
        "`roles` is missing required column(s): {.field {c('action', 'kind')}}."
      )
    }
    v1_vocab <- c(
      "design", "keep", "treatment", "outcome", "covariate", "ignore"
    )
    role_vocab <- .roles_vocab()
    bad_v1 <- setdiff(unique(roles$role), v1_vocab)
    if (length(bad_v1)) {
      cli::cli_abort(c(
        "Unknown role(s) in `roles$role`: {.val {bad_v1}}.",
        i = "Valid roles: {.val {role_vocab}}."
      ))
    }
    cli::cli_warn(c(
      paste0(
        "`roles` has no {.field action} column (masque <= 0.5.0 ",
        "format); upgrading to the two-axis schema for mode ",
        "{.val {mode}}."
      ),
      i = "Re-run {.fun propose_roles} to silence this warning."
    ))
    roles <- .roles_upgrade(roles, mode)
  }

  if (!("kind" %in% names(roles))) {
    cli::cli_abort("`roles` is missing required column(s): {.field kind}.")
  }

  role_vocab <- .roles_vocab()
  action_vocab <- .actions_vocab()

  bad_role <- setdiff(unique(roles$role), role_vocab)
  if (length(bad_role)) {
    hint <- if (any(bad_role %in% c("keep", "ignore"))) {
      paste0(
        "{.val keep} and {.val ignore} are masque <= 0.5.0 roles: use ",
        "{.code action = \"keep\"} / {.code action = \"drop\"} instead."
      )
    } else {
      "Valid roles: {.val {role_vocab}}."
    }
    cli::cli_abort(c(
      "Unknown role(s) in `roles$role`: {.val {bad_role}}.",
      i = hint
    ))
  }

  bad_action <- setdiff(
    unique(roles$action[!is.na(roles$action)]), action_vocab
  )
  if (length(bad_action)) {
    cli::cli_abort(c(
      "Unknown action(s) in `roles$action`: {.val {bad_action}}.",
      i = "Valid actions: {.val {action_vocab}}."
    ))
  }

  roles <- .resolve_na_actions(roles, mode)
  roles <- .reresolve_for_mode(roles, mode)

  if (anyDuplicated(roles$col)) {
    dups <- roles$col[duplicated(roles$col)]
    cli::cli_abort("Duplicate column name(s) in `roles$col`: {.field {dups}}.")
  }

  if (!is.null(df)) {
    if (!is.data.frame(df)) {
      cli::cli_abort("`df` must be a data frame; got {.cls {class(df)[1]}}.")
    }
    missing_in_roles <- setdiff(names(df), roles$col)
    extra_in_roles <- setdiff(roles$col, names(df))
    if (length(missing_in_roles)) {
      cli::cli_abort(
        "`df` column(s) not in `roles`: {.field {missing_in_roles}}."
      )
    }
    if (length(extra_in_roles)) {
      cli::cli_abort(
        "`roles` column(s) not in `df`: {.field {extra_in_roles}}."
      )
    }
  }

  # (role, action, kind) compatibility - collect every problem, then
  # fail once with the full list.
  problems <- character(0L)
  for (i in seq_len(nrow(roles))) {
    p <- .action_problem(roles$role[i], roles$action[i], roles$kind[i])
    if (!is.na(p)) {
      problems <- c(
        problems,
        sprintf("%s (%s + %s): %s",
          roles$col[i], roles$role[i], roles$action[i], p
        )
      )
    }
  }
  if (length(problems)) {
    names(problems) <- rep("x", length(problems))
    cli::cli_abort(c(
      "Incompatible role / action / kind combination(s):",
      problems
    ))
  }

  if (nrow(roles) > 0L && all(roles$action == "keep")) {
    cli::cli_warn(c(
      "Every action is {.val keep}: nothing will be masked.",
      i = "The synthetic output will equal the original byte-for-byte."
    ))
  }

  invisible(roles)
}

# When a table proposed for one mode is used with the other, columns
# whose action still equals their proposed default follow the new
# mode's default (with an inform); explicitly edited columns - via
# set_role(action = ) or a direct action edit - are pinned and win.
# Tables without provenance attributes (hand-built) get a warning and
# are taken as-is.
.reresolve_for_mode <- function(roles, mode) {
  proposed_mode <- attr(roles, "mode")
  if (is.null(proposed_mode) || identical(proposed_mode, mode)) {
    return(roles)
  }

  pa <- attr(roles, "proposed_actions")
  if (is.null(pa)) {
    cli::cli_warn(c(
      paste0(
        "`roles` was prepared for mode {.val {proposed_mode}} but is ",
        "being used with mode {.val {mode}}; actions are taken as-is."
      ),
      i = paste0(
        "Re-run {.code propose_roles(df, mode = \"{mode}\")} if you ",
        "want the {.val {mode}} defaults."
      )
    ))
    return(roles)
  }

  changed <- character(0L)
  for (i in seq_len(nrow(roles))) {
    col_i <- roles$col[i]
    if (!(col_i %in% names(pa))) next
    if (!identical(unname(pa[[col_i]]), roles$action[i])) next
    kind_i <- if ("kind" %in% names(roles)) roles$kind[i] else "other"
    new_a <- .default_action(roles$role[i], kind_i, mode)
    if (!identical(new_a, roles$action[i])) {
      changed <- c(
        changed,
        sprintf("%s: %s -> %s", col_i, roles$action[i], new_a)
      )
      roles$action[i] <- new_a
    }
    pa[[col_i]] <- new_a
  }
  attr(roles, "proposed_actions") <- pa
  attr(roles, "mode") <- mode

  if (length(changed)) {
    names(changed) <- rep("*", length(changed))
    cli::cli_inform(c(
      paste0(
        "Re-resolved default actions for mode {.val {mode}} ",
        "(explicit edits always win):"
      ),
      changed
    ))
  }
  roles
}
