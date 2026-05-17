# print() method for the S7 design_summary class.
#
# Compact, cli-styled. Always shows: header (class + treatment),
# alternates (top-3 rule scores so the user can see runners-up), and
# recommended roles. Long evidence lists are summarised.

S7::method(print, design_summary) <- function(x, ...) {
  cli::cli_rule(left = sprintf("design_summary  <%s>", x@class_label))

  if (x@class_label == "none") {
    cli::cli_bullets(c(
      "i" = "No experimental design detected above threshold.",
      "*" = "Top rule scores all below 0.5. Treat as observational."
    ))
  } else {
    bullets <- character(0L)
    if (length(x@treatment_col) > 0L) {
      bullets <- c(bullets,
                   "*" = sprintf("Treatment: {.field %s}",
                                 paste(x@treatment_col, collapse = " + ")))
    }
    if (length(x@block_cols) > 0L) {
      bullets <- c(bullets,
                   "*" = sprintf("Blocks: {.field %s}",
                                 paste(x@block_cols, collapse = " : ")))
    }
    if (length(x@whole_plot_col) > 0L) {
      bullets <- c(bullets,
                   "*" = sprintf("Whole-plot: {.field %s} | Sub-plot: {.field %s}",
                                 x@whole_plot_col, x@sub_plot_col))
    }
    if (length(x@spatial_cols) > 0L) {
      bullets <- c(bullets,
                   "*" = sprintf("Spatial: {.field %s} x {.field %s}",
                                 x@spatial_cols[1L], x@spatial_cols[2L]))
    }
    cli::cli_bullets(bullets)
  }

  # Alternates.
  if (length(x@scores) > 0L) {
    cli::cli_rule(left = "Alternates (top rule scores)")
    ord     <- order(x@scores, decreasing = TRUE)
    top_n   <- min(3L, length(x@scores))
    top_idx <- ord[seq_len(top_n)]
    for (i in top_idx) {
      mark <- if (names(x@scores)[i] == x@class_label) "x" else " "
      cli::cli_text(sprintf("  %s {.cls %-20s} score = %.2f",
                            mark, names(x@scores)[i], x@scores[i]))
    }
  }

  # Recommended roles, briefly.
  if (nrow(x@recommended_roles) > 0L) {
    cli::cli_rule(left = "Recommended role hints")
    for (i in seq_len(nrow(x@recommended_roles))) {
      cli::cli_text(sprintf("  = {.field %s} -> {.field %s}",
                            x@recommended_roles$col[i],
                            x@recommended_roles$role[i]))
    }
  }

  # Warnings.
  if (length(x@warnings) > 0L) {
    cli::cli_rule(left = "Warnings")
    for (w in x@warnings) cli::cli_alert_warning(w)
  }

  cli::cli_alert_info(
    "Use {.code plot(x)} for a sanity-check visualisation; pass to {.code propose_roles(df, detect = TRUE)} to seed role hints."
  )

  invisible(x)
}
