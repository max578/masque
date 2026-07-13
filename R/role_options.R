# role_options.R -- The role x action option grid, rendered as data.
#
# Presentation layer over the compatibility rules roles_validate()
# enforces at mask() time (.action_problem() in roles_actions.R). The
# grid is generated from those rules on every call, so the catalogue a
# user reads and the validator that judges their table cannot drift
# apart.

#' List every role and action combination masque accepts
#'
#' Renders the two-axis vocabulary as a table: every `role` paired with
#' every `action`, the storage kinds the pair works for, and the reason
#' the pair is constrained when it is. The table is generated from the
#' same compatibility rules [roles_validate()] applies at [mask()] time,
#' so what it shows is exactly what a roles table is allowed to say.
#'
#' A column's `kind` is never chosen: [propose_roles()] derives it from
#' the column's class. To move a column to a different kind, convert the
#' column in the data and re-propose.
#'
#' @param kind Optional storage kind to filter for: one of `"numeric"`,
#'   `"integer"`, `"factor"`, `"character"`, `"logical"`, `"date"`,
#'   `"datetime"`, or `"other"`. When supplied, only the combinations
#'   workable for a column of that kind are returned. The default `NULL`
#'   returns the full grid.
#'
#' @returns A tibble with one row per role-action pair and four columns:
#'   `role`, `action`, `kinds` (the storage kinds the pair is valid for:
#'   `"all"`, `"none"`, `"all except other"`, or a comma-separated
#'   list), and `notes` (why the pair is constrained, empty when it is
#'   not).
#'
#' @examples
#' role_options()
#' role_options(kind = "factor")
#' subset(role_options(), role == "design")
#'
#' @seealso [propose_roles()], [set_role()], [roles_validate()].
#'
#' @export
role_options <- function(kind = NULL) {
  kinds <- .kinds_vocab()
  if (!is.null(kind)) {
    if (!is.character(kind) || length(kind) != 1L || !(kind %in% kinds)) {
      cli::cli_abort(c(
        "`kind` must be one of {.val {kinds}}.",
        i = "Got {.val {kind}}."
      ))
    }
  }

  # Evaluate every (role, action) pair against every kind ----------------
  grid <- expand.grid(
    action = .actions_vocab(),
    role = .roles_vocab(),
    stringsAsFactors = FALSE
  )[, c("role", "action")]

  kinds_ok <- vector("list", nrow(grid))
  notes <- character(nrow(grid))
  for (i in seq_len(nrow(grid))) {
    problems <- vapply(
      kinds,
      function(k) .action_problem(grid$role[i], grid$action[i], k),
      character(1L)
    )
    ok <- is.na(problems)
    kinds_ok[[i]] <- kinds[ok]

    # The note is the constraint explanation. Prefer the role-level
    # message over the generic unsupported-class one, which fires for
    # kind "other" under every synthesising action.
    specific <- problems[!ok & kinds != "other"]
    notes[i] <- if (all(ok)) {
      ""
    } else if (length(specific) > 0L) {
      specific[[1L]]
    } else {
      problems[!ok][[1L]]
    }
  }

  out <- tibble::tibble(
    role = grid$role,
    action = grid$action,
    kinds = vapply(
      kinds_ok,
      function(k) {
        if (length(k) == length(kinds)) {
          "all"
        } else if (length(k) == 0L) {
          "none"
        } else if (identical(setdiff(kinds, k), "other")) {
          "all except other"
        } else {
          paste(k, collapse = ", ")
        }
      },
      character(1L)
    ),
    notes = notes
  )

  if (is.null(kind)) {
    return(out)
  }
  out[vapply(kinds_ok, function(k) kind %in% k, logical(1L)), ]
}
