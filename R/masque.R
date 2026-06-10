#' Mask a dataset end to end with one guided call
#'
#' The front door. `masque()` walks the whole procedure - read the data,
#' propose column roles, (in an interactive session) pause for you to
#' review the plan, mask, audit, and optionally write the result - from a
#' single call. It dispatches on the input: a single file or data frame
#' goes through [mask()]; a folder, an Excel workbook, or a named list of
#' tables goes through [mask_set()].
#'
#' It is also fully scriptable. Pass an edited `roles` table (or named
#' list of them) to skip the interactive review, and an `out` path to
#' write the masked result in one go. The returned object is the same
#' `masque` / `masque_set` you would get from the lower-level verbs, so
#' anything you can do with those you can do with the result here.
#'
#' @section The guided flow:
#'
#' 1. **Read** the input into one or more clean rectangular tables.
#' 2. **Propose roles** for every column (skipped if you pass `roles`).
#' 3. **Review** - in an interactive session with no `roles` supplied,
#'    the proposed plan is printed and you are asked to proceed, edit, or
#'    stop. Editing opens the roles table in [utils::edit()]. With
#'    `ask = FALSE` (the default in non-interactive use) the proposed
#'    plan is used as-is, with a note.
#' 4. **Mask** the data in the chosen `mode`.
#' 5. **Audit** - in `collaborate` mode the leakage audit runs and its
#'    headline is printed.
#' 6. **Write** - if `out` is set, the masked data is written there
#'    (mirroring the input format). The private recipe is never written
#'    automatically; persist it yourself with [save_recipe()].
#'
#' @param input A data frame, a single tabular file (`.csv` / `.tsv` /
#'   `.fst`), a folder of such files, an Excel workbook, or a named list
#'   of data frames.
#' @param roles Optional. A roles table (single-table input) or named
#'   list of roles tables (set input). When supplied, the interactive
#'   review is skipped.
#' @param out Optional output path. For a single table, a `.csv` file (or
#'   `.xlsx` with `writexl`). For a set, a folder (one CSV per table) or
#'   an `.xlsx` workbook. When `NULL` (default) nothing is written.
#' @param mode Either `"local"` (default) or `"collaborate"`.
#' @param seed Optional integer for reproducibility.
#' @param clean Hygiene mode passed to [clean_table()] (`"auto"`,
#'   `"report"`, `"off"`).
#' @param alias_names Hide column names; see [mask()] / [mask_set()].
#' @param ask Whether to pause for interactive review when `roles` is not
#'   supplied. Defaults to [interactive()]. Set `FALSE` to proceed with
#'   the proposed plan without prompting.
#' @param overwrite Passed to the writer when `out` is set.
#' @param quiet Suppress progress messages.
#'
#' @return A `masque` object (single-table input) or a `masque_set`
#'   object (set input), invisibly. Use [synthetic()] and [recipe()].
#'
#' @examples
#' # Scripted single-table use (no prompt because roles are supplied):
#' r <- propose_roles(iris)
#' r <- set_role(r, "Sepal.Length", role = "outcome")
#' m <- masque(iris, roles = r, seed = 1, ask = FALSE, quiet = TRUE)
#' head(synthetic(m))
#'
#' @seealso [mask()], [mask_set()], [propose_roles()], [set_role()],
#'   [write_set()], [save_recipe()].
#' @export
masque <- function(input,
                   roles = NULL,
                   out = NULL,
                   mode = c("local", "collaborate"),
                   seed = NULL,
                   clean = c("auto", "report", "off"),
                   alias_names = FALSE,
                   ask = interactive(),
                   overwrite = FALSE,
                   quiet = FALSE) {
  mode <- match.arg(mode)
  clean <- match.arg(clean)

  is_set <- .masque_is_set(input)

  if (is_set) {
    m <- .masque_guided_set(
      input, roles, mode, seed, clean, alias_names, ask, quiet
    )
  } else {
    m <- .masque_guided_one(
      input, roles, mode, seed, clean, alias_names, ask, quiet
    )
  }

  if (!is.null(out)) {
    .masque_write(m, out, overwrite, quiet)
  }
  if (!quiet) .masque_summary(m)
  invisible(m)
}

# A set is a folder, an Excel workbook, or a named list of data frames.
# A single data frame or a single tabular file is one table.
.masque_is_set <- function(input) {
  if (is.data.frame(input)) {
    return(FALSE)
  }
  if (is.list(input)) {
    return(TRUE)
  }
  if (is.character(input) && length(input) == 1L) {
    if (dir.exists(input)) {
      return(TRUE)
    }
    if (file.exists(input)) {
      return(tolower(tools::file_ext(input)) %in% c("xlsx", "xls"))
    }
    cli::cli_abort("No file or folder at {.file {input}}.")
  }
  cli::cli_abort(paste0(
    "`input` must be a data frame, a tabular file, a folder, an Excel ",
    "workbook, or a named list of data frames."
  ))
}

.masque_guided_one <- function(input, roles, mode, seed, clean,
                               alias_names, ask, quiet) {
  df <- if (is.data.frame(input)) input else .read_one_file(input)
  if (!is.null(roles)) {
    return(suppressWarnings(mask(
      df, roles, mode = mode, seed = seed, clean = clean,
      alias_names = alias_names
    )))
  }

  proposed <- propose_roles(df, mode = mode)
  proposed <- .masque_review(proposed, ask, quiet, label = NULL)
  suppressWarnings(mask(
    df, proposed, mode = mode, seed = seed, clean = clean,
    alias_names = alias_names
  ))
}

.masque_guided_set <- function(input, roles, mode, seed, clean,
                               alias_names, ask, quiet) {
  if (!is.null(roles)) {
    return(mask_set(
      input, roles = roles, mode = mode, seed = seed, clean = clean,
      alias_names = alias_names, quiet = quiet
    ))
  }

  tables <- read_set(input)
  proposed <- lapply(names(tables), function(nm) {
    r <- propose_roles(tables[[nm]], mode = mode)
    .masque_review(r, ask, quiet, label = nm)
  })
  names(proposed) <- names(tables)

  mask_set(
    tables, roles = proposed, mode = mode, seed = seed, clean = clean,
    alias_names = alias_names, quiet = quiet
  )
}

# Interactive review of one proposed roles table. In a non-interactive
# session, or with ask = FALSE, the plan is used as-is.
.masque_review <- function(roles, ask, quiet, label) {
  if (!isTRUE(ask) || !interactive()) {
    if (!quiet) {
      where <- if (is.null(label)) "" else sprintf(" for {.field {label}}")
      cli::cli_alert_info(paste0(
        "Using the proposed masking plan", where,
        " (pass {.arg roles} or set {.code ask = TRUE} to review)."
      ))
    }
    return(roles)
  }

  hdr <- if (is.null(label)) {
    "Proposed masking plan"
  } else {
    sprintf("Proposed masking plan - table '%s'", label)
  }
  cli::cli_h2(hdr)
  print(roles[, intersect(
    c("col", "role", "action", "kind"), names(roles)
  )])

  repeat {
    ans <- tolower(trimws(readline(
      "Proceed [p], edit roles [e], or quit [q]? "
    )))
    if (ans %in% c("", "p", "proceed", "y", "yes")) {
      return(roles)
    }
    if (ans %in% c("e", "edit")) {
      roles <- .masque_edit(roles)
      cli::cli_alert_success("Roles updated.")
      print(roles[, intersect(
        c("col", "role", "action", "kind"), names(roles)
      )])
      next
    }
    if (ans %in% c("q", "quit")) {
      cli::cli_abort("Stopped at user request.", call = NULL)
    }
    cli::cli_alert_warning("Please answer p, e, or q.")
  }
}

.masque_edit <- function(roles) {
  edited <- utils::edit(as.data.frame(roles))
  # Preserve the provenance attributes utils::edit() drops.
  for (a in c("mode", "proposed_actions", "design")) {
    if (is.null(attr(edited, a))) attr(edited, a) <- attr(roles, a)
  }
  tibble::as_tibble(edited)
}

.masque_write <- function(m, out, overwrite, quiet) {
  if (S7::S7_inherits(m, masque_set)) {
    write_set(m, out, overwrite = overwrite)
  } else {
    .write_one(synthetic(m), out, overwrite)
  }
  if (!quiet) cli::cli_alert_success("Wrote masked output to {.file {out}}.")
}

# Single-table writer: .xlsx via writexl, otherwise a CSV via fwrite.
.write_one <- function(df, out, overwrite) {
  if (file.exists(out) && !overwrite) {
    cli::cli_abort(c(
      "{.file {out}} already exists.",
      i = "Pass {.code overwrite = TRUE} to replace it."
    ))
  }
  if (grepl("\\.xlsx$", out, ignore.case = TRUE)) {
    if (!requireNamespace("writexl", quietly = TRUE)) {
      cli::cli_abort("Writing {.file {out}} needs the {.pkg writexl} package.")
    }
    writexl::write_xlsx(df, path = out)
  } else {
    data.table::fwrite(df, out)
  }
}

.masque_summary <- function(m) {
  if (S7::S7_inherits(m, masque_set)) {
    n <- length(m@synthetic)
    cli::cli_alert_success(
      "Masked {n} table{?s} in {.val {m@mode}} mode."
    )
  } else {
    cli::cli_alert_success(
      "Masked {ncol(synthetic(m))} column{?s} in {.val {m@mode}} mode."
    )
  }
  if (identical(m@mode, "collaborate")) {
    cli::cli_alert_info(
      "Recipe is private - keep it; share only the synthetic output."
    )
  }
}
