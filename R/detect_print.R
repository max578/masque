# print() method for the S7 design_summary class.
#
# Compact, cli-styled. Always shows: header (class + treatment),
# alternates (top-3 rule scores so the user can see runners-up), and
# recommended roles. Long evidence lists are summarised.

S7::method(print, design_summary) <- function(x, ...) {
  if (is.na(x@is_met)) {
    .print_scope_uncertainty(x)
  } else if (isTRUE(x@is_met)) {
    .print_met_scope(x)
  } else if (identical(x@scope_label, "single_environment")) {
    cli::cli_rule(left = "Environment scope  <single_environment>")
    cli::cli_bullets(c(
      "*" = sprintf(
        "Basis: {.field %s} | method: {.field %s}",
        paste(x@env_cols, collapse = " + "), x@env_method
      ),
      "i" = "The supplied basis contains one observed environment."
    ))
  }

  pooled_label <- if (isTRUE(x@is_met)) {
    sprintf("Pooled legacy verdict  <%s>", x@class_label)
  } else {
    sprintf("design_summary  <%s>", x@class_label)
  }
  cli::cli_rule(left = pooled_label)

  if (x@class_label == "none") {
    cli::cli_bullets(c(
      "i" = "No experimental design detected above threshold.",
      "*" = "Top rule scores all below 0.5. Treat as observational."
    ))
  } else {
    bullets <- character(0L)
    if (length(x@treatment_col) > 0L) {
      bullets <- c(bullets,
        "*" = sprintf(
          "Treatment: {.field %s}",
          paste(x@treatment_col, collapse = " + ")
        )
      )
    }
    if (length(x@block_cols) > 0L) {
      bullets <- c(bullets,
        "*" = sprintf(
          "Blocks: {.field %s}",
          paste(x@block_cols, collapse = " : ")
        )
      )
    }
    if (length(x@whole_plot_col) > 0L) {
      bullets <- c(bullets,
        "*" = sprintf(
          "Whole-plot: {.field %s} | Sub-plot: {.field %s}",
          x@whole_plot_col, x@sub_plot_col
        )
      )
    }
    if (length(x@spatial_cols) > 0L) {
      bullets <- c(bullets,
        "*" = sprintf(
          "Spatial: {.field %s} x {.field %s}",
          x@spatial_cols[1L], x@spatial_cols[2L]
        )
      )
    }
    cli::cli_bullets(bullets)
  }

  # Alternates.
  if (length(x@scores) > 0L) {
    cli::cli_rule(left = "Alternates (top rule scores)")
    ord <- order(x@scores, decreasing = TRUE)
    top_n <- min(3L, length(x@scores))
    top_idx <- ord[seq_len(top_n)]
    for (i in top_idx) {
      mark <- if (names(x@scores)[i] == x@class_label) "x" else " "
      cli::cli_text(sprintf(
        "  %s {.cls %-20s} score = %.2f",
        mark, names(x@scores)[i], x@scores[i]
      ))
    }
  }

  # Recommended roles, briefly.
  if (nrow(x@recommended_roles) > 0L) {
    cli::cli_rule(left = "Recommended role hints")
    shown <- seq_len(min(8L, nrow(x@recommended_roles)))
    has_actions <- all(c(
      "action_local", "action_collaborate", "auto_apply"
    ) %in% names(x@recommended_roles))
    for (i in shown) {
      text <- if (has_actions) {
        sprintf(
          "  = {.field %s} -> {.field %s} [local=%s; collaborate=%s; %s]",
          x@recommended_roles$col[i],
          x@recommended_roles$role[i],
          x@recommended_roles$action_local[i],
          x@recommended_roles$action_collaborate[i],
          if (isTRUE(x@recommended_roles$auto_apply[i])) "auto" else "review"
        )
      } else {
        sprintf(
          "  = {.field %s} -> {.field %s}",
          x@recommended_roles$col[i],
          x@recommended_roles$role[i]
        )
      }
      cli::cli_text(text)
    }
    if (nrow(x@recommended_roles) > length(shown)) {
      cli::cli_text(sprintf(
        "  ... %d additional recommendation(s)",
        nrow(x@recommended_roles) - length(shown)
      ))
    }
    if (has_actions && "source" %in% names(x@recommended_roles)) {
      retained <- x@recommended_roles$col[
        x@recommended_roles$source == "environment_auto" &
          x@recommended_roles$auto_apply &
          x@recommended_roles$action_collaborate == "keep"
      ]
      if (length(retained) > 0L) {
        cli::cli_alert_warning(paste0(
          "Collaborate mode retains environment value(s) for: ",
          paste(retained, collapse = ", "),
          "; review disclosure."
        ))
      }
    }
  }

  # Warnings.
  if (length(x@warnings) > 0L) {
    cli::cli_rule(left = "Warnings")
    for (w in x@warnings) cli::cli_alert_warning(w)
  }

  cli::cli_alert_info(
    paste0(
      "Use {.code plot(x)} for a sanity-check visualisation; pass to ",
      "{.code propose_roles(df, detect = TRUE)} to seed role hints."
    )
  )

  invisible(x)
}

.print_scope_uncertainty <- function(x) {
  cli::cli_rule(left = "Environment scope  <uncertain>")
  reason <- switch(x@scope_status,
    ambiguous = "Competing environment candidates require explicit review.",
    review_required = sprintf(
      "Possible basis {.field %s} has {.field %s} confidence; review required.",
      paste(x@env_cols, collapse = " + "), x@scope_confidence
    ),
    disabled = "Multi-environment detection was disabled.",
    "No environment candidate passed the conservative validity gates."
  )
  cli::cli_alert_warning(reason)
}

.print_met_scope <- function(x) {
  cli::cli_rule(left = "Environment scope  <multi_environment>")
  bullets <- c(
    "*" = sprintf(
      "Basis: {.field %s} | method: {.field %s} | confidence: {.field %s}",
      paste(x@env_cols, collapse = " + "),
      x@env_method,
      x@scope_confidence
    ),
    "*" = sprintf(
      "Environments: %d | experiment groups: %s",
      x@n_env,
      if (length(x@group_cols) == 0L) "none detected" else
        paste(x@group_cols, collapse = " + ")
    ),
    "*" = sprintf(
      "Connectivity: {.field %s} | components: %s",
      x@connectivity$status,
      if (is.na(x@connectivity$components)) "not computed" else
        as.character(x@connectivity$components)
    )
  )
  if (length(x@treatment_col) > 0L) {
    bullets <- c(bullets,
      "*" = sprintf(
        "Treatment basis: {.field %s}",
        paste(x@treatment_col, collapse = " + ")
      )
    )
  }
  cli::cli_bullets(bullets)

  if (nrow(x@connectivity$component_sizes) > 0L) {
    sizes <- utils::head(x@connectivity$component_sizes, 4L)
    labels <- sprintf(
      "C%d=%d env/%d treatment%s",
      sizes$component,
      sizes$n_env,
      sizes$n_treatments,
      ifelse(sizes$n_treatments == 1L, "", "s")
    )
    if (nrow(x@connectivity$component_sizes) > 4L) {
      labels <- c(labels, "...")
    }
    cli::cli_text("  Component sizes: {paste(labels, collapse = '; ')}")
  }

  if (nrow(x@per_env) > 0L) {
    class_counts <- sort(table(x@per_env$class_label), decreasing = TRUE)
    labels <- sprintf("%s=%d", names(class_counts), as.integer(class_counts))
    row_range <- range(x@per_env$n_rows)
    treatment_range <- range(x@per_env$n_treatments)
    cli::cli_rule(left = "Within-environment advisory (aggregated)")
    cli::cli_bullets(c(
      "*" = sprintf(
        "Verdicts: %s",
        paste(labels, collapse = ", ")
      ),
      "*" = sprintf(
        "Rows/environment: %d--%d | treatments/environment: %d--%d",
        row_range[1L], row_range[2L],
        treatment_range[1L], treatment_range[2L]
      ),
      "i" = paste0(
        "Observed structure is advisory and does not prove the original ",
        "randomisation protocol."
      )
    ))
  }
}
