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
#'    stop. Editing opens the roles table in the spreadsheet editor
#'    ([utils::edit()]) where the platform provides one; when it cannot
#'    start (for example macOS without XQuartz, or a headless session), a
#'    console editor takes over - pick a column, then a role and an
#'    action from numbered menus, with every change applied through
#'    [set_role()] so default actions re-resolve exactly as on the
#'    scriptable path. With `ask = FALSE` (the default in
#'    non-interactive use) the proposed plan is used as-is, with a note.
#' 4. **Mask** the data in the chosen `mode`.
#' 5. **Audit** - in `collaborate` mode the leakage audit runs and its
#'    headline is printed. A HIGH finding surfaces as a classed warning
#'    (`masque_high_leakage`) - it is never silenced by the guided flow.
#' 6. **Write** - if `out` is set, the masked data is written there
#'    (mirroring the input format), *unless* the audit left unresolved
#'    HIGH findings: then the write is refused (nothing is written) and
#'    the flagged columns are listed. Resolve them and mask again, or
#'    pass `allow_high = TRUE` after your own review - the override is
#'    warned (`masque_high_override`) and recorded on the recipe. The
#'    private recipe is never written automatically; persist it yourself
#'    with [save_recipe()].
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
#' @param conditional Logical scalar (default `FALSE`). The conditional
#'   clone mode passed through to [mask()] / [mask_set()]: when `TRUE`,
#'   numeric columns are re-simulated within each treatment-by-design
#'   stratum so the treatment-to-outcome relationship survives the clone.
#'   See [mask()] for the full account.
#' @param ask Whether to pause for interactive review when `roles` is not
#'   supplied. Defaults to [interactive()]. Set `FALSE` to proceed with
#'   the proposed plan without prompting.
#' @param overwrite Passed to the writer when `out` is set.
#' @param quiet Suppress progress messages. Warnings - including the
#'   HIGH-leakage finding - are never suppressed.
#' @param allow_high Logical (default `FALSE`). When `out` is set and
#'   the collaborate-mode audit flagged HIGH leakage, the write is
#'   refused. Pass `TRUE` to write anyway after your own review; the
#'   override raises a `masque_high_override` warning and is recorded in
#'   the recipe's warnings, so the exception stays auditable.
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
                   conditional = FALSE,
                   ask = interactive(),
                   overwrite = FALSE,
                   quiet = FALSE,
                   allow_high = FALSE) {
  mode <- match.arg(mode)
  clean <- match.arg(clean)

  is_set <- .masque_is_set(input)

  if (is_set) {
    m <- .masque_guided_set(
      input, roles, mode, seed, clean, alias_names, conditional, ask, quiet
    )
  } else {
    m <- .masque_guided_one(
      input, roles, mode, seed, clean, alias_names, conditional, ask, quiet
    )
  }

  if (!is.null(out)) {
    m <- .masque_write(m, out, overwrite, quiet, allow_high)
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
                               alias_names, conditional, ask, quiet) {
  df <- if (is.data.frame(input)) input else .read_one_file(input)
  if (!is.null(roles)) {
    return(mask(
      df, roles, mode = mode, seed = seed, clean = clean,
      alias_names = alias_names, conditional = conditional
    ))
  }

  proposed <- propose_roles(df, mode = mode)
  proposed <- .masque_review(proposed, ask, quiet, label = NULL)
  mask(
    df, proposed, mode = mode, seed = seed, clean = clean,
    alias_names = alias_names, conditional = conditional
  )
}

.masque_guided_set <- function(input, roles, mode, seed, clean,
                               alias_names, conditional, ask, quiet) {
  if (!is.null(roles)) {
    return(mask_set(
      input, roles = roles, mode = mode, seed = seed, clean = clean,
      alias_names = alias_names, conditional = conditional, quiet = quiet
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
    alias_names = alias_names, conditional = conditional, quiet = quiet
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
    # Accept "[e]" for "e" - the bracketed prompt notation invites it.
    ans <- gsub("^\\[|\\]$", "", ans)
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

# The spreadsheet editor when the platform provides one, else a console
# fallback. utils::edit() on a data frame needs the X11 dataentry widget
# on macOS terminal R (XQuartz) and is unavailable on headless systems;
# an editor failure must return the user to the review loop with their
# proposal intact, never destroy the guided session.
.masque_edit <- function(roles) {
  edited <- tryCatch(.masque_edit_gui(roles), error = function(e) e)
  if (inherits(edited, "error")) {
    cli::cli_alert_warning(
      "The spreadsheet editor is unavailable: {conditionMessage(edited)}"
    )
    cli::cli_alert_info("Switching to the console editor.")
    return(.masque_edit_console(roles))
  }
  # Preserve the provenance attributes utils::edit() drops.
  for (a in c("mode", "proposed_actions", "design")) {
    if (is.null(attr(edited, a))) attr(edited, a) <- attr(roles, a)
  }
  tibble::as_tibble(edited)
}

# Thin indirection so tests can simulate editor failure and edits.
.masque_edit_gui <- function(roles) {
  utils::edit(as.data.frame(roles))
}

# Dependency-free console editor: pick a column, then a role and an
# action from numbered menus. Every change flows through set_role(), so
# validation, vocabulary, and default-action re-resolution match the
# scriptable path exactly (a re-roled column never carries a stale
# action). Blank input finishes; attributes survive because set_role()
# never drops them.
.masque_edit_console <- function(roles) {
  repeat {
    shown <- roles[, intersect(c("col", "role", "action", "kind"),
      names(roles)
    )]
    print(shown)
    ans <- trimws(.masque_readline(
      "Column to edit (name or row number; blank when done): "
    ))
    if (!nzchar(ans)) {
      return(roles)
    }
    col <- .masque_resolve_col(ans, roles$col)
    if (is.null(col)) {
      cli::cli_alert_warning(
        "No column {.val {ans}} - enter a listed name or its row number."
      )
      next
    }
    i <- match(col, roles$col)
    cur_action <- if ("action" %in% names(roles)) roles$action[i] else NA
    role <- .masque_pick("role", roles$role[i], .roles_vocab())
    action <- .masque_pick("action", cur_action, .actions_vocab())
    if (is.null(role) && is.null(action)) {
      cli::cli_alert_info("{.field {col}} unchanged.")
      next
    }
    args <- list(roles = roles, cols = col)
    if (!is.null(role)) args$role <- role
    if (!is.null(action)) args$action <- action
    roles <- do.call(set_role, args)
    cli::cli_alert_success("{.field {col}} updated.")
  }
}

# A column reference typed at the console: a row number or an exact name.
.masque_resolve_col <- function(ans, cols) {
  n <- suppressWarnings(as.integer(ans))
  if (!is.na(n)) {
    if (n >= 1L && n <= length(cols)) {
      return(cols[[n]])
    }
    return(NULL)
  }
  if (ans %in% cols) {
    return(ans)
  }
  NULL
}

# Numbered single-choice prompt; blank (or an invalid entry) keeps the
# current value and returns NULL.
.masque_pick <- function(what, current, vocab) {
  cat(sprintf(
    "  %s: %s\n", what,
    paste(sprintf("[%d] %s", seq_along(vocab), vocab), collapse = "  ")
  ))
  ans <- trimws(.masque_readline(sprintf(
    "New %s (number or name; blank keeps \"%s\"): ", what, current
  )))
  if (!nzchar(ans)) {
    return(NULL)
  }
  n <- suppressWarnings(as.integer(ans))
  if (!is.na(n) && n >= 1L && n <= length(vocab)) {
    return(vocab[[n]])
  }
  if (ans %in% vocab) {
    return(ans)
  }
  cli::cli_alert_warning(
    "{.val {ans}} is not a valid {what}; keeping {.val {current}}."
  )
  NULL
}

# readline() indirection so the console editor is testable.
.masque_readline <- function(prompt) {
  readline(prompt)
}

.masque_write <- function(m, out, overwrite, quiet, allow_high = FALSE) {
  # Safety gate first: aborts on unresolved HIGH findings (nothing
  # written); with allow_high = TRUE the override is warned and recorded
  # on the recipe so the exception survives with the private artefact.
  overridden <- .gate_release(m, allow_high)
  m <- .record_override(m, overridden)
  if (S7::S7_inherits(m, masque_set)) {
    .write_set_dispatch(m@synthetic, out, overwrite)
  } else {
    .write_one(synthetic(m), out, overwrite)
  }
  if (!quiet) cli::cli_alert_success("Wrote masked output to {.file {out}}.")
  m
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
    headline <- "Masked {n} table{?s} in {.val {m@mode}} mode"
  } else {
    headline <- "Masked {ncol(synthetic(m))} column{?s} in {.val {m@mode}} mode"
  }

  status <- .release_status(m)
  tally <- .audit_tally(m)
  if (!is.null(tally)) {
    cli::cli_alert_success(paste0(
      headline,
      sprintf(
        " - audit: %d HIGH, %d medium, %d low.",
        tally[["high"]], tally[["medium"]], tally[["low"]]
      )
    ))
  } else {
    cli::cli_alert_success(paste0(headline, "."))
  }

  if (identical(status, "blocked")) {
    flagged <- paste(.audit_high_cols(m), collapse = ", ")
    cli::cli_alert_danger(
      "BLOCKED: unresolved HIGH leakage on {flagged}."
    )
    cli::cli_alert_info(
      "Next: re-role, alias, or drop the flagged column(s), then mask again."
    )
    return(invisible(m))
  }

  if (identical(m@mode, "collaborate")) {
    cli::cli_alert_info(paste0(
      "Recipe is private - keep it. Review {.code audit_mask(m)} before ",
      "any release decision; masque informs that decision, it does not ",
      "make it."
    ))
  } else {
    cli::cli_alert_info(
      "Local development copy - owner use only, not for external sharing."
    )
  }
  invisible(m)
}
