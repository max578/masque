#' Validate a roles tibble
#'
#' Fail-closed validation of a `roles` tibble before `mask()` consumes it.
#' Errors are raised for every misuse the v0.2 spec calls out.
#'
#' Hard errors:
#'
#' \itemize{
#'   \item missing required columns (`col`, `role`, `kind`);
#'   \item unknown role string (not in
#'     `c("design","treatment","outcome","covariate","ignore")`);
#'   \item any `NA` role;
#'   \item zero columns flagged `outcome`;
#'   \item more than one column flagged `treatment` (joint-treatment
#'     masking is not yet supported by [mask()]);
#'   \item duplicate `col` entries;
#'   \item if `df` supplied: any `df` column missing from `roles`, or any
#'     `roles` column missing from `df`.
#' }
#'
#' Returns the validated `roles` invisibly (mirrors `stopifnot`-style use).
#'
#' @param roles A tibble produced by [propose_roles()] (possibly edited).
#' @param df Optional data frame. If supplied, `roles` is checked for
#'   one-to-one column-name correspondence with `df`.
#'
#' @return `roles`, invisibly.
#'
#' @examples
#' r <- propose_roles(iris)
#' r$role[r$col == "Sepal.Length"] <- "outcome"
#' roles_validate(r, iris)
#'
#' @seealso [propose_roles()].
#'
#' @export
roles_validate <- function(roles, df = NULL) {
  if (!is.data.frame(roles)) {
    cli::cli_abort("`roles` must be a data frame / tibble; got {.cls {class(roles)[1]}}.")
  }

  required <- c("col", "role", "kind")
  missing  <- setdiff(required, names(roles))
  if (length(missing)) {
    cli::cli_abort("`roles` is missing required column(s): {.field {missing}}.")
  }

  # Structural checks first (NAs, duplicates, df mismatches), then semantic.
  if (any(is.na(roles$role))) {
    cli::cli_abort("`roles$role` has NA value(s) for: {.field {roles$col[is.na(roles$role)]}}.")
  }

  valid <- c("design", "treatment", "outcome", "covariate", "ignore")
  bad   <- setdiff(unique(roles$role), valid)
  if (length(bad)) {
    cli::cli_abort(c(
      "Unknown role(s) in `roles$role`: {.val {bad}}.",
      i = "Valid roles: {.val {valid}}."
    ))
  }

  if (anyDuplicated(roles$col)) {
    dups <- roles$col[duplicated(roles$col)]
    cli::cli_abort("Duplicate column name(s) in `roles$col`: {.field {dups}}.")
  }

  if (!is.null(df)) {
    if (!is.data.frame(df)) {
      cli::cli_abort("`df` must be a data frame; got {.cls {class(df)[1]}}.")
    }
    missing_in_roles <- setdiff(names(df), roles$col)
    extra_in_roles   <- setdiff(roles$col, names(df))
    if (length(missing_in_roles)) {
      cli::cli_abort("`df` column(s) not in `roles`: {.field {missing_in_roles}}.")
    }
    if (length(extra_in_roles)) {
      cli::cli_abort("`roles` column(s) not in `df`: {.field {extra_in_roles}}.")
    }
  }

  # Semantic checks last
  n_outcome   <- sum(roles$role == "outcome")
  n_treatment <- sum(roles$role == "treatment")

  if (n_outcome == 0L) {
    cli::cli_abort(c(
      "No column flagged as {.val outcome}.",
      i = "`mask()` requires at least one outcome column. Edit the roles tibble and try again."
    ))
  }

  if ("kind" %in% names(roles)) {
    non_num_outcome <- roles$col[
      roles$role == "outcome" & !(roles$kind %in% c("numeric", "integer"))
    ]
    if (length(non_num_outcome)) {
      cli::cli_abort(c(
        "Non-numeric column(s) flagged as {.val outcome}: {.field {non_num_outcome}}.",
        i = "{.fun mask} currently supports only numeric / integer outcomes. Re-role categorical outcomes as {.val covariate} or remove."
      ))
    }
  }

  if (n_treatment > 1L) {
    treat_cols <- roles$col[roles$role == "treatment"]
    cli::cli_abort(c(
      "Multiple columns ({n_treatment}) flagged as {.val treatment}: {.field {treat_cols}}.",
      i = "{.fun mask} currently supports at most one treatment column. Joint-treatment masking is on the roadmap.",
      "*" = "Edit the roles tibble to keep exactly one {.val treatment} column (demote the others, commonly to {.val covariate}),",
      "*" = "or call {.code propose_roles(df, detect = FALSE)} to recover the v0.2.x byte-stable proposal before editing."
    ))
  }

  invisible(roles)
}
