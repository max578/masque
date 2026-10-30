# A column constant within a design unit is synthesised once per unit.

#' Detect the grain of the columns mask() re-simulates
#'
#' Candidates are scrambled covariate and outcome columns of numeric,
#' categorical or date kind, scrambled date columns, and aliased categorical
#' covariates, less `exclude`. Units are the retained (not dropped) design
#' columns of `df`, singly and in pairs, since a dropped unit broadcast into
#' the clone would publish the grouping the plan removed. A
#' column's grain is the unit with the fewest groups within which every group
#' holds at most one distinct non-missing value, among units with at least two
#' groups and at most `nrow(df) / 2`; ties go to fewer columns, then column
#' order. A column constant over the whole table has no grain.
#'
#' @returns A list with one entry per unit holding grained columns:
#'   `list(unit, cols, n_units, synthesised = "unit", reason = "")`, in the
#'   column order of `df`.
#' @keywords internal
#' @noRd
.detect_grain <- function(df, roles, exclude = character()) {
  role <- roles$role
  action <- roles$action
  kind <- roles$kind
  cand <- roles$col[
    ((role %in% c("covariate", "outcome") & action == "scramble" &
      kind %in% c(.numeric_kinds(), .categorical_kinds(), .date_kinds())) |
      (role == "date" & action == "scramble" & kind %in% .date_kinds()) |
      (role == "covariate" & action == "alias" &
        kind %in% .categorical_kinds())) &
      !roles$col %in% exclude
  ]
  cand <- intersect(names(df), cand)
  design <- intersect(names(df), roles$col[role == "design" & action != "drop"])
  n <- nrow(df)
  if (!length(cand) || !length(design) || n < 4L) {
    return(list())
  }

  varies <- vapply(cand, function(cl) {
    data.table::uniqueN(df[[cl]], na.rm = TRUE) > 1L
  }, logical(1L))
  cand <- cand[varies]
  if (!length(cand)) {
    return(list())
  }

  units <- as.list(design)
  if (length(design) > 1L) {
    units <- c(units, utils::combn(design, 2L, simplify = FALSE))
  }

  # Per unit: its group count and whether each candidate holds at most one
  # distinct non-missing value in every group (an all-missing group counts).
  fits <- lapply(units, function(u) {
    gid <- .unit_id(df, u)
    n_groups <- as.integer(max(gid))
    ok <- n_groups >= 2L && n_groups <= n / 2
    constant <- vapply(cand, function(cl) {
      if (!ok) {
        return(FALSE)
      }
      .constant_within(gid, df[[cl]])
    }, logical(1L))
    list(n_groups = n_groups, constant = constant)
  })
  n_groups <- vapply(fits, `[[`, integer(1L), "n_groups")
  n_cols <- lengths(units)
  ord <- order(n_groups, n_cols, seq_along(units))

  grain_of <- vapply(cand, function(cl) {
    hit <- ord[vapply(ord, function(i) fits[[i]]$constant[[cl]], logical(1L))]
    if (length(hit)) hit[1L] else NA_integer_
  }, integer(1L))
  grain_of <- grain_of[!is.na(grain_of)]
  if (!length(grain_of)) {
    return(list())
  }

  lapply(unique(grain_of), function(i) {
    list(
      unit        = units[[i]],
      cols        = names(grain_of)[grain_of == i],
      n_units     = n_groups[[i]],
      synthesised = "unit",
      reason      = ""
    )
  })
}

# Internal: mark each grain group "unit" or "row" (grain = FALSE, or a small
# collaborate grain, with a warning); returns the groups and recipe lines.
.resolve_grain <- function(groups, grain, mode) {
  lines <- character()
  for (i in seq_along(groups)) {
    g <- groups[[i]]
    cols <- paste(g$cols, collapse = ", ")
    unit <- paste(g$unit, collapse = ":")
    if (!isTRUE(grain)) {
      g$synthesised <- "row"
      g$reason <- "grain = FALSE"
      lines <- c(lines, sprintf(
        paste0(
          "%s %s constant within %s (%d units) but %s synthesised row by row ",
          "(grain = FALSE); the clone does not keep that grain."
        ),
        cols, if (length(g$cols) > 1L) "are" else "is", unit, g$n_units,
        if (length(g$cols) > 1L) "were" else "was"
      ))
    } else if (identical(mode, "collaborate") && g$n_units < .MIN_STRATUM) {
      g$synthesised <- "row"
      g$reason <- sprintf("fewer than %d units", .MIN_STRATUM)
      msg <- sprintf(
        paste0(
          "%s %s constant within %s, which has %d units, fewer than %d: ",
          "resampling that few real values would disclose them, so %s ",
          "synthesised row by row and the clone does not keep that grain."
        ),
        cols, if (length(g$cols) > 1L) "are" else "is", unit, g$n_units,
        .MIN_STRATUM, if (length(g$cols) > 1L) "they were" else "it was"
      )
      warning(warningCondition(msg, class = "masque_grain_small_units"))
      lines <- c(lines, msg)
    } else {
      lines <- c(lines, sprintf(
        paste0(
          "%s synthesised once per %s (%d units); %s correlation with ",
          "row-level columns is not preserved."
        ),
        cols, unit, g$n_units,
        if (length(g$cols) > 1L) "their" else "its"
      ))
    }
    groups[[i]] <- g
  }
  list(groups = groups, lines = lines)
}

# Internal: dense group id (1, 2, ...) of each row over the unit columns; a
# missing design value is a group of its own.
.unit_id <- function(df, unit) {
  data.table::frankv(.cols(df, unit), ties.method = "dense")
}

# Internal: synthesise one grain group on its unit table and broadcast each
# unit's value to its non-missing rows; returns the columns and level maps.
.synthesise_grain_group <- function(df, group, roles, jitter) {
  cols <- group$cols
  row_unit <- .unit_id(df, group$unit)
  n_units <- max(row_unit)
  # One value per unit: its first non-missing value, NA when it has none.
  unit_value <- function(x) {
    o <- which(!is.na(x))
    x[o[match(seq_len(n_units), row_unit[o])]]
  }
  ut <- lapply(.cols(df, cols), unit_value)

  kind <- roles$kind[match(cols, roles$col)]
  action <- roles$action[match(cols, roles$col)]
  new_unit <- list()
  maps <- list()

  num <- cols[kind %in% .numeric_kinds()]
  if (length(num)) {
    x_unit <- as.data.frame(ut[num], stringsAsFactors = FALSE)
    names(x_unit) <- num
    x_new <- synthesise_numeric_local(x_unit)
    for (cl in num) {
      new_unit[[cl]] <- if (isTRUE(jitter)) {
        synthesise_numeric_collaborate(
          x_obs = x_unit[[cl]], x_new = x_new[[cl]]
        )
      } else {
        x_new[[cl]]
      }
    }
  }
  for (cl in setdiff(cols, num)) {
    new_unit[[cl]] <- synthesise_categorical_local(ut[[cl]])
  }

  out <- list()
  for (cl in cols) {
    x <- df[[cl]]
    obs <- !is.na(x)
    x[obs] <- new_unit[[cl]][row_unit[obs]]
    if (identical(action[match(cl, cols)], "alias")) {
      res <- alias_levels(x, prefix = paste0(cl, "_L"))
      x <- res$x
      maps[[cl]] <- res$map
    }
    out[[cl]] <- x
  }
  list(columns = out, level_maps = maps)
}


# TRUE when `x` holds at most one distinct non-missing value per group id.
.constant_within <- function(gid, x) {
  g <- V1 <- NULL
  obs <- !is.na(x)
  pairs <- data.table::data.table(g = gid[obs], x = x[obs])
  pairs[, data.table::uniqueN(x), by = g][, all(V1 <= 1L)]
}

# Unit and column count only; aliased unit names show their alias.
.grain_print_line <- function(g, name_map = NULL) {
  unit <- g$unit
  hits <- unit %in% names(name_map)
  unit[hits] <- unlist(name_map[unit[hits]], use.names = FALSE)
  n <- length(g$cols)
  sprintf(
    "%s: %d column%s, synthesised per %s%s",
    paste(unit, collapse = " : "), n, if (n == 1L) "" else "s",
    g$synthesised, if (nzchar(g$reason)) sprintf(" (%s)", g$reason) else ""
  )
}
