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
#'     `c("design","keep","treatment","outcome","covariate","ignore")`);
#'   \item any `NA` role;
#'   \item zero columns flagged `outcome`;
#'   \item unsupported `other` columns flagged as `covariate`;
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
    cli::cli_abort(
      "`roles` must be a data frame / tibble; got {.cls {class(roles)[1]}}."
    )
  }

  required <- c("col", "role", "kind")
  missing <- setdiff(required, names(roles))
  if (length(missing)) {
    cli::cli_abort("`roles` is missing required column(s): {.field {missing}}.")
  }

  # Structural checks first (NAs, duplicates, df mismatches), then semantic.
  if (any(is.na(roles$role))) {
    cli::cli_abort(
      paste0(
        "`roles$role` has NA value(s) for: ",
        "{.field {roles$col[is.na(roles$role)]}}."
      )
    )
  }

  valid <- c("design", "keep", "treatment", "outcome", "covariate", "ignore")
  bad <- setdiff(unique(roles$role), valid)
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

  # Semantic checks last
  n_outcome <- sum(roles$role == "outcome")

  if (n_outcome == 0L) {
    cli::cli_abort(c(
      "No column flagged as {.val outcome}.",
      i = paste0(
        "`mask()` requires at least one outcome column. ",
        "Edit the roles tibble and try again."
      )
    ))
  }

  if ("kind" %in% names(roles)) {
    non_num_outcome <- roles$col[
      roles$role == "outcome" & !(roles$kind %in% c("numeric", "integer"))
    ]
    if (length(non_num_outcome)) {
      cli::cli_abort(c(
        paste0(
          "Non-numeric column(s) flagged as {.val outcome}: ",
          "{.field {non_num_outcome}}."
        ),
        i = paste0(
          "{.fun mask} currently supports only numeric / integer ",
          "outcomes. Re-role categorical outcomes as {.val covariate} ",
          "or remove."
        )
      ))
    }

    unsupported_covariate <- roles$col[
      roles$role == "covariate" & roles$kind == "other"
    ]
    if (length(unsupported_covariate)) {
      cli::cli_abort(c(
        paste0(
          "Unsupported column class(es) flagged as {.val covariate}: ",
          "{.field {unsupported_covariate}}."
        ),
        i = paste0(
          "Use {.val keep} to pass these columns through unchanged, ",
          "or {.val ignore} to drop them in collaborate mode."
        )
      ))
    }
  }

  invisible(roles)
}
