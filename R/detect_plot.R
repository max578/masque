# plot() method for the S7 design_summary class.
#
# Sanity-check visualisations in base graphics. Four atoms — replication
# tile, spatial layout tile, factor-nesting tree, frequency + NA-pattern
# tile — composed differently per design class. Borrowing the desplot
# `out1` outline idiom and dae's structure-formula nesting view, but
# implemented from scratch in base graphics to keep `Imports:` lean.
# `ggplot2`, if installed, is offered as an alternative engine.

#' Sanity-check visualisation for a detected design
#'
#' Plots the structure that drove the [detect_design()] verdict. The
#' panel layout depends on the detected class:
#'
#' \itemize{
#'   \item `CRD`, `factorial`, `none` -> frequency-of-treatment + NA-pattern.
#'   \item `RCBD`, `IBD/alpha-lattice` -> treatment x block replication tile.
#'   \item `row-column` -> spatial layout tile (row x col, fill =
#'     treatment).
#'   \item `split-plot` -> factor-nesting tree + within-block replication.
#' }
#'
#' Output is purely diagnostic; do not use it as a publication figure
#' (use `desplot::desplot()` or `ggplot2`-based packages for that).
#'
#' @param x A `design_summary` object from [detect_design()].
#' @param df The data frame that was passed to [detect_design()] — used
#'   to draw replication tiles, spatial layouts, and the NA-pattern.
#'   Required for every class except `"none"` with no factors.
#' @param engine `"base"` (default) or `"ggplot2"`. The latter requires
#'   ggplot2; falls back to `"base"` with a warning if unavailable.
#' @param ... Ignored.
#'
#' @return The input `x`, invisibly. Called for the plot side-effect.
#'
#' @examples
#' if (requireNamespace("agridat", quietly = TRUE)) {
#'   d  <- agridat::john.alpha
#'   ds <- detect_design(d)
#'   plot(ds, df = d)
#' }
#'
#' @export
plot_design_summary <- function(x, df, engine = c("base", "ggplot2"), ...) {
  engine <- match.arg(engine)
  if (!inherits(x, "masque::design_summary")) {
    cli::cli_abort("`x` must be a {.cls design_summary}.")
  }
  if (missing(df) || !is.data.frame(df)) {
    cli::cli_abort("`df` must be the data frame that was passed to detect_design().")
  }
  if (engine == "ggplot2" && !requireNamespace("ggplot2", quietly = TRUE)) {
    cli::cli_warn("ggplot2 not installed; falling back to base graphics.")
    engine <- "base"
  }

  switch(x@class_label,
    "CRD"               = .plot_freq_and_na(x, df, engine),
    "factorial"         = .plot_factorial(x, df, engine),
    "RCBD"              = .plot_replication_tile(x, df, engine),
    "IBD/alpha-lattice" = .plot_replication_tile(x, df, engine),
    "row-column"        = .plot_spatial(x, df, engine),
    "split-plot"        = .plot_split_plot(x, df, engine),
    "none"              = .plot_freq_and_na(x, df, engine),
    .plot_freq_and_na(x, df, engine)
  )

  invisible(x)
}

S7::method(plot, design_summary) <- function(x, df, engine = c("base", "ggplot2"), ...) {
  plot_design_summary(x, df = df, engine = engine, ...)
}

# --- panel: replication tile ---------------------------------------------

# Treatment x block(s) matrix, fill = replication count.
.plot_replication_tile <- function(x, df, engine) {
  trt   <- x@treatment_col[1L]
  block <- x@block_cols[1L]
  if (is.null(trt) || is.na(trt) || length(block) == 0L) {
    cli::cli_warn("Replication tile needs treatment + block; skipping.")
    return(invisible())
  }
  # If block is a pairwise basis (e.g. rep + block), build interaction.
  if (length(x@block_cols) >= 2L) {
    block_vec <- interaction(df[[x@block_cols[1L]]], df[[x@block_cols[2L]]],
                             drop = TRUE, sep = ":")
    block_label <- paste(x@block_cols[1:2], collapse = ":")
  } else {
    block_vec   <- df[[block]]
    block_label <- block
  }
  m <- as.matrix(table(block_vec, df[[trt]], useNA = "no"))

  if (engine == "ggplot2") return(.gg_replication_tile(m, trt, block_label, x@class_label))

  op <- graphics::par(mar = c(5, 6, 4, 2) + 0.1)
  on.exit(graphics::par(op), add = TRUE)

  col_palette <- grDevices::hcl.colors(max(m) + 1L, palette = "YlGnBu", rev = TRUE)
  graphics::image(
    seq_len(ncol(m)), seq_len(nrow(m)),
    t(m[nrow(m):1L, , drop = FALSE]),
    axes  = FALSE, xlab = "", ylab = "",
    col   = col_palette,
    main  = sprintf("Replication: %s x %s  [%s]",
                    trt, block_label, x@class_label)
  )
  graphics::axis(1, at = seq_len(ncol(m)), labels = colnames(m), las = 2)
  graphics::axis(2, at = seq_len(nrow(m)), labels = rev(rownames(m)), las = 2)
  # Cell counts overlaid.
  for (i in seq_len(nrow(m))) {
    for (j in seq_len(ncol(m))) {
      graphics::text(j, nrow(m) - i + 1L, labels = m[i, j], cex = 0.7)
    }
  }
  graphics::mtext(trt,         side = 1, line = 3.5)
  graphics::mtext(block_label, side = 2, line = 4)
}

.gg_replication_tile <- function(m, trt, block_label, class_label) {
  long <- expand.grid(
    block     = rownames(m),
    treatment = colnames(m),
    stringsAsFactors = FALSE
  )
  long$n <- as.integer(m[cbind(long$block, long$treatment)])
  ggplot2::ggplot(long, ggplot2::aes(.data$treatment, .data$block, fill = .data$n)) +
    ggplot2::geom_tile(colour = "white") +
    ggplot2::geom_text(ggplot2::aes(label = .data$n), size = 3) +
    ggplot2::scale_fill_distiller(palette = "YlGnBu", direction = 1) +
    ggplot2::labs(title = sprintf("Replication: %s x %s  [%s]",
                                   trt, block_label, class_label),
                  x = trt, y = block_label) +
    ggplot2::theme_minimal() +
    ggplot2::theme(axis.text.x = ggplot2::element_text(angle = 45, hjust = 1))
}

# --- panel: spatial layout -----------------------------------------------

# row x col grid, fill = treatment, outlined by block if known.
.plot_spatial <- function(x, df, engine) {
  if (length(x@spatial_cols) < 2L) {
    cli::cli_warn("Spatial plot needs row + col; skipping.")
    return(invisible())
  }
  row_nm <- x@spatial_cols[1L]
  col_nm <- x@spatial_cols[2L]
  trt    <- if (length(x@treatment_col) > 0L) x@treatment_col[1L] else NA_character_

  rv <- df[[row_nm]]; cv <- df[[col_nm]]
  fill_vec <- if (!is.na(trt)) as.factor(df[[trt]]) else factor(rep("plot", nrow(df)))
  palette  <- grDevices::hcl.colors(nlevels(fill_vec), palette = "Spectral")
  fill_cols <- palette[as.integer(fill_vec)]

  if (engine == "ggplot2") return(.gg_spatial(df, row_nm, col_nm, trt, x@block_cols, x@class_label))

  op <- graphics::par(mar = c(4, 4, 4, 2) + 0.1)
  on.exit(graphics::par(op), add = TRUE)

  graphics::plot(
    cv, rv, type = "n",
    xlim = c(min(cv) - 0.5, max(cv) + 0.5),
    ylim = c(min(rv) - 0.5, max(rv) + 0.5),
    xlab = col_nm, ylab = row_nm, asp = 1,
    main = sprintf("Spatial layout: fill = %s  [%s]",
                   if (is.na(trt)) "plot" else trt, x@class_label)
  )
  graphics::rect(cv - 0.5, rv - 0.5, cv + 0.5, rv + 0.5,
                 col = fill_cols, border = "white", lwd = 0.5)

  # Outline blocks if a block factor exists.
  if (length(x@block_cols) > 0L && x@block_cols[1L] %in% names(df)) {
    .outline_blocks(df, row_nm, col_nm, x@block_cols[1L])
  }

  if (!is.na(trt) && nlevels(fill_vec) <= 12L) {
    graphics::legend("topright", legend = levels(fill_vec),
                     fill = palette, bty = "n", cex = 0.7)
  }
}

.outline_blocks <- function(df, row_nm, col_nm, block_nm) {
  by_block <- split(df, df[[block_nm]])
  for (nm in names(by_block)) {
    sub <- by_block[[nm]]
    if (nrow(sub) < 1L) next
    r0 <- min(sub[[row_nm]]) - 0.5; r1 <- max(sub[[row_nm]]) + 0.5
    c0 <- min(sub[[col_nm]]) - 0.5; c1 <- max(sub[[col_nm]]) + 0.5
    graphics::rect(c0, r0, c1, r1, border = "black", lwd = 1.6, lty = 1)
  }
}

.gg_spatial <- function(df, row_nm, col_nm, trt, block_cols, class_label) {
  fill_aes <- if (!is.null(trt) && !is.na(trt)) trt else NULL
  p <- ggplot2::ggplot(df, ggplot2::aes(x = .data[[col_nm]], y = .data[[row_nm]]))
  if (!is.null(fill_aes)) {
    p <- p + ggplot2::geom_tile(ggplot2::aes(fill = .data[[fill_aes]]),
                                colour = "white")
  } else {
    p <- p + ggplot2::geom_tile(fill = "grey60", colour = "white")
  }
  if (length(block_cols) > 0L && block_cols[1L] %in% names(df)) {
    p <- p + ggplot2::stat_summary(
      ggplot2::aes(group = .data[[block_cols[1L]]]),
      geom = "rect", fun.data = function(d) {
        data.frame(xmin = min(d) - 0.5, xmax = max(d) + 0.5,
                   ymin = min(d) - 0.5, ymax = max(d) + 0.5)
      }, fill = NA, colour = "black", linewidth = 0.6
    )
  }
  p + ggplot2::coord_equal() +
    ggplot2::labs(title = sprintf("Spatial layout  [%s]", class_label)) +
    ggplot2::theme_minimal()
}

# --- panel: split-plot tree + replication --------------------------------

.plot_split_plot <- function(x, df, engine) {
  op <- graphics::par(mfrow = c(1, 2))
  on.exit(graphics::par(op), add = TRUE)

  # 1) Nesting tree.
  .plot_nesting_tree(c(x@block_cols, x@whole_plot_col, x@sub_plot_col), df)

  # 2) Replication tile of whole x sub within the first block.
  if (length(x@whole_plot_col) > 0L && length(x@sub_plot_col) > 0L) {
    m <- as.matrix(table(df[[x@whole_plot_col]], df[[x@sub_plot_col]],
                          useNA = "no"))
    col_palette <- grDevices::hcl.colors(max(m) + 1L, palette = "YlGnBu", rev = TRUE)
    graphics::image(seq_len(ncol(m)), seq_len(nrow(m)),
                    t(m[nrow(m):1L, , drop = FALSE]),
                    axes = FALSE, xlab = "", ylab = "",
                    col = col_palette,
                    main = sprintf("%s x %s coverage", x@whole_plot_col, x@sub_plot_col))
    graphics::axis(1, at = seq_len(ncol(m)), labels = colnames(m), las = 2)
    graphics::axis(2, at = seq_len(nrow(m)), labels = rev(rownames(m)), las = 2)
    for (i in seq_len(nrow(m))) for (j in seq_len(ncol(m))) {
      graphics::text(j, nrow(m) - i + 1L, labels = m[i, j], cex = 0.7)
    }
  }
}

# Simple top-down tree: layers is character vector of column names
# (root first). Each layer's nodes = unique levels.
.plot_nesting_tree <- function(layers, df) {
  layers <- layers[layers %in% names(df)]
  if (length(layers) == 0L) {
    graphics::plot.new(); graphics::title("(no nesting)")
    return()
  }
  op <- graphics::par(mar = c(2, 1, 4, 1))
  on.exit(graphics::par(op), add = TRUE)

  nlev <- vapply(layers, function(c) length(unique(stats::na.omit(df[[c]]))),
                 integer(1L))
  max_w <- max(nlev)

  graphics::plot(NA, xlim = c(0, max_w + 1), ylim = c(0, length(layers) + 1),
                 axes = FALSE, xlab = "", ylab = "",
                 main = "Factor nesting")

  for (i in seq_along(layers)) {
    y <- length(layers) - i + 1
    xs <- seq_len(nlev[i]) * (max_w / (nlev[i] + 1))
    graphics::points(xs, rep(y, length(xs)), pch = 21, bg = "grey80", cex = 2.4)
    graphics::text(0.3, y, labels = layers[i], adj = c(0, 0.5), font = 2)
    if (i > 1L) {
      y_above <- y + 1
      xs_above <- seq_len(nlev[i - 1L]) * (max_w / (nlev[i - 1L] + 1))
      # Connect each child to its (uniform) parent: cheap approximation
      # draw a line from every parent to every child.
      for (xp in xs_above) for (xc in xs) {
        graphics::segments(xp, y_above - 0.18, xc, y + 0.18,
                           col = "grey60", lwd = 0.4)
      }
    }
  }
}

# --- panel: frequency + NA-pattern (CRD / none / fallback) ---------------

.plot_freq_and_na <- function(x, df, engine) {
  op <- graphics::par(mfrow = c(1, 2))
  on.exit(graphics::par(op), add = TRUE)

  # 1) Treatment frequency (or "no factor" placeholder).
  if (length(x@treatment_col) > 0L && x@treatment_col[1L] %in% names(df)) {
    trt <- x@treatment_col[1L]
    tbl <- sort(table(df[[trt]], useNA = "no"), decreasing = TRUE)
    graphics::par(mar = c(7, 4, 4, 2) + 0.1)
    graphics::barplot(
      tbl, las = 2, col = grDevices::hcl.colors(length(tbl), "Spectral"),
      main = sprintf("Replication: %s  [%s]", trt, x@class_label),
      ylab = "n observations"
    )
  } else {
    graphics::plot.new()
    graphics::title(sprintf("[%s] no treatment factor", x@class_label))
  }

  # 2) NA pattern (column x NA-rate).
  .plot_na_pattern(df)
}

.plot_na_pattern <- function(df) {
  na_pct <- vapply(df, function(x) mean(is.na(x)) * 100, numeric(1L))
  ord    <- order(na_pct, decreasing = TRUE)
  na_pct <- na_pct[ord]
  graphics::par(mar = c(4, 8, 4, 2) + 0.1)
  graphics::barplot(
    na_pct, horiz = TRUE, las = 1,
    col = ifelse(na_pct > 0, "#d95f02", "grey85"),
    main = "Missingness by column",
    xlab = "% NA", xlim = c(0, max(100, max(na_pct, 0) + 5))
  )
}

# --- panel: factorial ----------------------------------------------------

.plot_factorial <- function(x, df, engine) {
  if (length(x@treatment_col) < 2L) return(.plot_freq_and_na(x, df, engine))
  a <- x@treatment_col[1L]; b <- x@treatment_col[2L]
  m <- as.matrix(table(df[[a]], df[[b]], useNA = "no"))

  if (engine == "ggplot2") return(.gg_replication_tile(m, b, a, x@class_label))

  op <- graphics::par(mar = c(5, 6, 4, 2) + 0.1)
  on.exit(graphics::par(op), add = TRUE)
  col_palette <- grDevices::hcl.colors(max(m) + 1L, palette = "YlGnBu", rev = TRUE)
  graphics::image(
    seq_len(ncol(m)), seq_len(nrow(m)),
    t(m[nrow(m):1L, , drop = FALSE]),
    axes = FALSE, xlab = "", ylab = "",
    col  = col_palette,
    main = sprintf("Factorial: %s x %s  [%s]", a, b, x@class_label)
  )
  graphics::axis(1, at = seq_len(ncol(m)), labels = colnames(m), las = 2)
  graphics::axis(2, at = seq_len(nrow(m)), labels = rev(rownames(m)), las = 2)
  for (i in seq_len(nrow(m))) for (j in seq_len(ncol(m))) {
    graphics::text(j, nrow(m) - i + 1L, labels = m[i, j], cex = 0.7)
  }
  graphics::mtext(b, side = 1, line = 3.5); graphics::mtext(a, side = 2, line = 4)
}
