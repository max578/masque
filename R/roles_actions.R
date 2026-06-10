#' Set the role and action of one or more columns in a roles table
#'
#' Ergonomic editor for the two-axis roles table returned by
#' [propose_roles()]. Setting a `role` without an explicit `action`
#' re-resolves the action to the default for the new role, the column's
#' kind, and the mode the table was proposed for — so a re-roled column
#' never silently carries a stale action from its previous role.
#'
#' Direct edits (`roles$role[roles$col == "x"] <- "outcome"`) remain
#' fully supported; this helper exists because a direct role edit leaves
#' `roles$action` untouched, which is occasionally what you want and
#' frequently not.
#'
#' @param roles A roles table from [propose_roles()] (possibly edited).
#' @param cols Character vector of column names to edit. Every entry
#'   must be present in `roles$col`.
#' @param role Optional single role to assign to all of `cols`. One of
#'   `"design"`, `"treatment"`, `"outcome"`, `"covariate"`, `"date"`,
#'   `"id"`, `"text"`, `"other"`.
#' @param action Optional single action to assign to all of `cols`. One
#'   of `"keep"`, `"scramble"`, `"alias"`, `"drop"`. When `NULL` (the
#'   default) and `role` was supplied, the action is re-resolved to the
#'   default for the new role.
#'
#' @return The edited roles table.
#'
#' @examples
#' r <- propose_roles(iris)
#' r <- set_role(r, "Sepal.Length", role = "outcome")
#' r <- set_role(r, "Species", action = "keep")
#' r[, c("col", "role", "action")]
#'
#' @seealso [propose_roles()], [roles_validate()].
#' @export
set_role <- function(roles, cols, role = NULL, action = NULL) {
  if (!is.data.frame(roles) || !all(c("col", "role") %in% names(roles))) {
    cli::cli_abort(
      "`roles` must be a roles table from {.fun propose_roles}."
    )
  }
  if (!is.character(cols) || length(cols) == 0L) {
    cli::cli_abort("`cols` must be a non-empty character vector.")
  }
  unknown <- setdiff(cols, roles$col)
  if (length(unknown)) {
    cli::cli_abort("Column(s) not in `roles`: {.field {unknown}}.")
  }
  if (is.null(role) && is.null(action)) {
    cli::cli_abort("Supply at least one of `role` or `action`.")
  }
  role_vocab <- .roles_vocab()
  action_vocab <- .actions_vocab()
  if (!is.null(role)) {
    if (!is.character(role) || length(role) != 1L ||
      !(role %in% role_vocab)) {
      cli::cli_abort(c(
        "`role` must be one of {.val {role_vocab}}.",
        i = "Got {.val {role}}."
      ))
    }
  }
  if (!is.null(action)) {
    if (!is.character(action) || length(action) != 1L ||
      !(action %in% action_vocab)) {
      cli::cli_abort(c(
        "`action` must be one of {.val {action_vocab}}.",
        i = "Got {.val {action}}."
      ))
    }
  }

  mode <- attr(roles, "mode") %||% "local"
  pa <- attr(roles, "proposed_actions")
  idx <- match(cols, roles$col)
  if (!is.null(role)) {
    roles$role[idx] <- role
  }
  if (!is.null(action)) {
    if (!("action" %in% names(roles))) roles$action <- NA_character_
    roles$action[idx] <- action
    # An explicit action pins the column: it no longer follows the
    # mode's defaults if the table is later used with the other mode.
    if (!is.null(pa)) {
      attr(roles, "proposed_actions") <- pa[setdiff(names(pa), cols)]
    }
  } else if (!is.null(role) && "action" %in% names(roles)) {
    kind <- if ("kind" %in% names(roles)) roles$kind[idx] else
      rep("other", length(idx))
    new_actions <- vapply(
      kind, function(k) .default_action(role, k, mode), character(1L)
    )
    roles$action[idx] <- new_actions
    # A re-roled column keeps tracking its (new) default.
    if (!is.null(pa)) {
      pa[cols] <- new_actions
      attr(roles, "proposed_actions") <- pa
    }
  }
  roles
}

.roles_vocab <- function() {
  c(
    "design", "treatment", "outcome", "covariate",
    "date", "id", "text", "other"
  )
}

.actions_vocab <- function() {
  c("keep", "scramble", "alias", "drop")
}

.categorical_kinds <- function() c("factor", "character", "logical")
.numeric_kinds <- function() c("numeric", "integer")
.date_kinds <- function() c("date", "datetime")

# Per-mode default action for a (role, kind) pair. This is the single
# source of truth that propose_roles(), set_role(), the v1 upgrade, and
# NA-action resolution all consult.
.default_action <- function(role, kind, mode) {
  collab <- identical(mode, "collaborate")
  switch(role,
    design = "keep",
    treatment = {
      if (collab && kind %in% .categorical_kinds()) "alias" else "keep"
    },
    outcome = {
      if (kind %in% .numeric_kinds()) "scramble" else "keep"
    },
    covariate = {
      if (kind %in% .numeric_kinds()) {
        "scramble"
      } else if (collab && kind %in% .categorical_kinds()) {
        "alias"
      } else {
        "scramble"
      }
    },
    date = "scramble",
    id = if (collab) "drop" else "keep",
    text = if (collab) "drop" else "keep",
    other = "keep",
    cli::cli_abort("Unknown role {.val {role}} (internal).")
  )
}

# Compatibility check for one (role, action, kind) triple. Returns
# NA_character_ when the combination is workable, otherwise a short
# explanation for the validation error. `keep` and `drop` are always
# workable; only the synthesising actions are constrained.
.action_problem <- function(role, action, kind) {
  if (action %in% c("keep", "drop")) {
    return(NA_character_)
  }

  # Columns of an unsupported class can only be kept or dropped, whatever
  # role they carry - masque has no synthesiser for them.
  if (kind == "other") {
    return(paste0(
      "columns of an unsupported class can only be kept or dropped; ",
      "masque does not know how to synthesise them"
    ))
  }

  if (role == "design") {
    if (action == "scramble") {
      return(paste0(
        "design columns are structure, not content - they cannot be ",
        "scrambled; use keep, alias (labels hidden, structure intact), ",
        "or drop"
      ))
    }
    if (!(kind %in% .categorical_kinds())) {
      return(paste0(
        "design label aliasing requires a factor / character / logical ",
        "column; numeric design columns can only be kept or dropped"
      ))
    }
  }

  if (role == "treatment" && !(kind %in% .categorical_kinds())) {
    return(paste0(
      "treatment scramble / alias requires a factor / character / ",
      "logical column; a numeric treatment (e.g. a dose) can only be ",
      "kept or dropped"
    ))
  }

  if (role == "outcome") {
    if (action == "alias") {
      return("outcomes carry no label vocabulary to alias; use scramble")
    }
    if (!(kind %in% .numeric_kinds())) {
      return(paste0(
        "only numeric / integer outcomes can be scrambled; re-role a ",
        "categorical outcome as treatment or covariate"
      ))
    }
  }

  if (role == "covariate" && action == "alias" &&
    !(kind %in% .categorical_kinds())) {
    return(paste0(
      "covariate aliasing requires a factor / character / logical ",
      "column; numeric covariates use scramble"
    ))
  }

  if (role == "date") {
    if (action == "alias") {
      return(paste0(
        "date/time columns carry no label vocabulary to alias; use ",
        "scramble (row permutation), keep, or drop"
      ))
    }
    if (!(kind %in% .date_kinds())) {
      return(paste0(
        "role \"date\" with scramble requires a Date / POSIX column; ",
        "parse the column to a date class first, or use role ",
        "\"covariate\""
      ))
    }
  }

  if (role == "id") {
    if (action == "scramble") {
      return(paste0(
        "ids cannot be scrambled - permuting identifiers silently ",
        "breaks row linkage; use alias, keep, or drop"
      ))
    }
    if (!(kind %in% c("factor", "character", "integer", "numeric"))) {
      return("id aliasing requires a character, factor, or integer column")
    }
  }

  if (role == "text" && action == "alias" &&
    !(kind %in% c("factor", "character"))) {
    return("text aliasing requires a character or factor column")
  }

  if (role == "other") {
    return(paste0(
      "columns of unsupported classes can only be kept or dropped; ",
      "masque does not know how to synthesise them"
    ))
  }

  NA_character_
}

# Upgrade a v1 (<= 0.5.0) roles table - one with no `action` column and
# the v1 vocabulary (design / keep / treatment / outcome / covariate /
# ignore, plus the optional `mask_levels` column) - to the two-axis
# schema, preserving the v1 mode semantics exactly:
#   * v1 keep         -> action keep (role re-derived from kind)
#   * v1 ignore       -> id / text / other role; keep in local, drop in
#                        collaborate
#   * v1 treatment    -> keep in local (scramble when mask_levels was
#                        "permute"), alias in collaborate
#   * everything else -> the v2 default action for the mapped role
.roles_upgrade <- function(roles, mode) {
  kind <- if ("kind" %in% names(roles)) {
    roles$kind
  } else {
    rep("other", nrow(roles))
  }
  role2 <- character(nrow(roles))
  action2 <- character(nrow(roles))
  pinned <- logical(nrow(roles))

  for (i in seq_len(nrow(roles))) {
    r <- roles$role[i]
    k <- kind[i]
    pinned[i] <- r %in% c("keep", "ignore")
    if (r %in% c("design", "treatment", "outcome")) {
      role2[i] <- r
      action2[i] <- .default_action(r, k, mode)
    } else if (r == "covariate") {
      role2[i] <- if (k %in% .date_kinds()) "date" else "covariate"
      action2[i] <- .default_action(role2[i], k, mode)
    } else if (r == "keep") {
      role2[i] <- if (k %in% .date_kinds()) {
        "date"
      } else if (k == "other") {
        "other"
      } else {
        "covariate"
      }
      action2[i] <- "keep"
    } else if (r == "ignore") {
      role2[i] <- if (matches_pattern(roles$col[i], ID_PATTERN)) {
        "id"
      } else if (k %in% c("character", "factor")) {
        "text"
      } else {
        "other"
      }
      action2[i] <- if (identical(mode, "collaborate")) "drop" else "keep"
    } else {
      role2[i] <- r
      action2[i] <- NA_character_
    }
  }

  if ("mask_levels" %in% names(roles)) {
    permuted <- !is.na(roles$mask_levels) & roles$mask_levels == "permute" &
      role2 == "treatment" & action2 == "keep"
    action2[permuted] <- "scramble"
    pinned[permuted] <- TRUE
    roles$mask_levels <- NULL
  }

  roles$role <- role2
  roles$action <- action2
  roles <- roles[, .reorder_roles_cols(names(roles)), drop = FALSE]
  attr(roles, "mode") <- mode
  attr(roles, "proposed_actions") <- stats::setNames(
    action2[!pinned], roles$col[!pinned]
  )
  roles
}

# Canonical column order: col, role, action first, the rest preserved.
.reorder_roles_cols <- function(nms) {
  lead <- intersect(c("col", "role", "action", "kind"), nms)
  c(lead, setdiff(nms, lead))
}

# Resolve NA actions to the (role, kind, mode) default. Users signal
# "use the default for my edited role" by setting action to NA.
.resolve_na_actions <- function(roles, mode) {
  nas <- which(is.na(roles$action))
  for (i in nas) {
    kind <- if ("kind" %in% names(roles)) roles$kind[i] else "other"
    roles$action[i] <- .default_action(roles$role[i], kind, mode)
  }
  roles
}
