# Release gate ---------------------------------------------------------------
#
# The package's safety contract: generation never implies release. A
# collaborate-mode object carries the mask-time audit; any unresolved
# HIGH finding blocks every package-managed writer unless the caller
# passes an explicit, recorded `allow_high = TRUE` override. Local mode
# is the owner-only path and is never gated.

# Columns flagged HIGH by the mask-time audit. For a masque_set the
# audit is a named list of per-table tibbles; flagged columns are
# reported as "<table>$<col>" so the remedy is unambiguous.
.audit_high_cols <- function(m) {
  audit <- m@audit
  if (is.null(audit)) {
    return(character())
  }
  if (S7::S7_inherits(m, masque_set)) {
    out <- character()
    for (nm in names(audit)) {
      tbl <- audit[[nm]]
      if (is.null(tbl)) next
      hits <- tbl$col[tbl$leakage_class == "high"]
      if (length(hits)) {
        out <- c(out, paste0(nm, "$", hits))
      }
    }
    return(out)
  }
  audit$col[audit$leakage_class == "high"]
}

# HIGH / medium / low counts across the whole object (summed over tables
# for a set). NULL when no audit was run (local mode).
.audit_tally <- function(m) {
  audit <- m@audit
  if (is.null(audit)) {
    return(NULL)
  }
  tbls <- if (S7::S7_inherits(m, masque_set)) audit else list(audit)
  cls <- unlist(lapply(tbls, function(tbl) {
    if (is.null(tbl)) character() else tbl$leakage_class
  }), use.names = FALSE)
  c(
    high   = sum(cls == "high"),
    medium = sum(cls == "medium"),
    low    = sum(cls == "low")
  )
}

# Release status derived from the mask-time audit. `"local"` for
# local-mode objects (owner-only, never gated); otherwise `"blocked"`,
# `"review"`, or `"clear"`.
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

# Gate a package-managed write. Aborts (class "masque_blocked_write",
# nothing written) when a collaborate-mode object carries unresolved
# HIGH findings and no override was given. With `allow_high = TRUE` the
# write proceeds, but the override is signalled as a classed warning
# ("masque_high_override") so it is visible and catchable. Returns the
# flagged columns invisibly (empty when nothing was gated) so callers
# can record the override on the recipe.
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
          "{length(high)} column{?s}."
        ),
        x = "Flagged: {flagged}.",
        i = "Re-role, alias, or drop the flagged column(s), then mask again.",
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
      "allow_high = TRUE: writing despite HIGH leakage on column(s): %s.",
      flagged
    ),
    class = "masque_high_override"
  ))
  invisible(high)
}

# Record an allow_high override on the recipe's warnings so the
# exception survives with the private artefact. Returns the updated
# object (R copy semantics - callers must use the return value).
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
