# Release gate ---------------------------------------------------------------
#
# Generation never implies release: package writers refuse a collaborate-mode
# object with unresolved HIGH findings unless `allow_high = TRUE`.

# Findings flagged HIGH at mask time: columns, then table-level checks named
# "[<check>]". For a masque_set, each is prefixed "<table>$".
.audit_high_cols <- function(m) {
  audit <- m@audit
  if (is.null(audit)) {
    return(character())
  }
  if (S7::S7_inherits(m, masque_set)) {
    out <- character()
    for (nm in names(audit)) {
      hits <- .audit_high_findings(audit[[nm]])
      if (length(hits)) {
        out <- c(out, paste0(nm, "$", hits))
      }
    }
    return(out)
  }
  .audit_high_findings(audit)
}

# HIGH findings of one audit table.
.audit_high_findings <- function(audit) {
  if (is.null(audit)) {
    return(character())
  }
  joint <- attr(audit, "joint")
  checks <- if (is.null(joint)) {
    character()
  } else {
    high <- joint$check[joint$leakage_class == "high"]
    if (length(high)) sprintf("[%s]", .joint_check_label(high)) else character()
  }
  c(audit$col[audit$leakage_class == "high"], checks)
}

# Reader-facing names of the table-level checks.
.joint_check_label <- function(check) {
  labels <- c(
    same_row_joint = "same-row joint match",
    whole_row = "whole-row match",
    rare_cross = "rare category cross",
    unit_sizes = "unit sizes"
  )
  unname(labels[check])
}

# HIGH / medium / low counts across the whole object (summed over tables
# for a set). Graded table-level checks add to the high and medium counts.
# NULL when no audit was run (local mode).
.audit_tally <- function(m) {
  audit <- m@audit
  if (is.null(audit)) {
    return(NULL)
  }
  tbls <- if (S7::S7_inherits(m, masque_set)) audit else list(audit)
  cls <- unlist(lapply(tbls, function(tbl) {
    if (is.null(tbl)) character() else tbl$leakage_class
  }), use.names = FALSE)
  joint <- unlist(lapply(tbls, function(tbl) {
    attr(tbl, "joint")$leakage_class
  }), use.names = FALSE)
  c(
    high   = sum(cls == "high") + sum(joint == "high"),
    medium = sum(cls == "medium") + sum(joint == "medium"),
    low    = sum(cls == "low")
  )
}

# Release status from the mask-time audit: "local" (never gated), "blocked",
# "review" or "clear".
.release_status <- function(m) {
  if (!identical(m@mode, "collaborate")) {
    return("local")
  }
  tally <- .audit_tally(m)
  if (is.null(tally)) {
    return("clear")
  }
  if (tally[["high"]] > 0L) {
    return("blocked")
  }
  if (tally[["medium"]] > 0L) {
    return("review")
  }
  "clear"
}

# Gate a package-managed write: abort ("masque_blocked_write") on unresolved
# HIGH findings, or warn ("masque_high_override") under `allow_high = TRUE`.
.gate_release <- function(m, allow_high = FALSE) {
  high <- if (identical(m@mode, "collaborate")) {
    .audit_high_cols(m)
  } else {
    character()
  }
  if (!length(high)) {
    return(invisible(character()))
  }
  flagged <- paste(high, collapse = ", ")
  if (!isTRUE(allow_high)) {
    cli::cli_abort(
      c(
        paste0(
          "Write blocked: the audit flagged HIGH leakage on ",
          "{length(high)} finding{?s}."
        ),
        x = "Flagged: {flagged}.",
        i = "Re-role, alias, or drop each flagged column, then mask again.",
        i = paste0(
          "Or pass `allow_high = TRUE` to write anyway after your own ",
          "review - the override is recorded."
        )
      ),
      class = "masque_blocked_write"
    )
  }
  warning(warningCondition(
    sprintf(
      "allow_high = TRUE: writing despite HIGH leakage on %s: %s.",
      ngettext(length(high), "finding", "findings"), flagged
    ),
    class = "masque_high_override"
  ))
  invisible(high)
}

# Record an allow_high override in the recipe's warnings; returns the updated
# object.
.record_override <- function(m, high) {
  if (!length(high)) {
    return(m)
  }
  note <- sprintf(
    paste0(
      "%s: HIGH leakage gate overridden at write time ",
      "(allow_high = TRUE) for: %s"
    ),
    format(Sys.time(), "%Y-%m-%d %H:%M:%S", tz = "UTC"),
    paste(high, collapse = ", ")
  )
  if (S7::S7_inherits(m, masque_set)) {
    recs <- m@recipe@recipes
    for (nm in names(recs)) {
      recs[[nm]]@warnings <- c(recs[[nm]]@warnings, note)
    }
    m@recipe@recipes <- recs
  } else {
    m@recipe@warnings <- c(m@recipe@warnings, note)
  }
  m
}
