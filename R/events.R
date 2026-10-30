# Linked events for mask(events =): gaps re-simulated per status pattern.

# Normalise and validate mask()'s `events` against the original table and the
# validated roles. Returns a list of `list(time =, status =)`.
.normalise_events <- function(events, df, roles) {
  if (is.null(events)) {
    return(list())
  }
  if (!is.list(events) || !length(events)) {
    .events_refuse(
      "`events` must be a list of `list(time =, status =)` specs."
    )
  }
  if (!is.null(events$time) || !is.null(events$status)) {
    events <- list(events)
  }
  specs <- lapply(events, .check_event_spec, df = df, roles = roles)

  used <- unlist(lapply(specs, function(s) c(s$time, s$status)))
  dup <- unique(used[duplicated(used)])
  if (length(dup)) {
    .events_refuse(
      "Column{?s} {.field {dup}} appear{?s/} in more than one `events` spec."
    )
  }
  specs
}

# Validate one spec: columns present, outcome role, whole-numbered statuses,
# no missing values, and times in order in the original.
.check_event_spec <- function(spec, df, roles) {
  if (!is.list(spec) || is.null(spec$time) || is.null(spec$status)) {
    .events_refuse("Each `events` spec needs `time` and `status` column names.")
  }
  time <- as.character(spec$time)
  status <- as.character(spec$status)
  if (length(time) != length(status) || !length(time)) {
    .events_refuse(
      "An `events` spec needs one `status` column per `time` column."
    )
  }

  cols <- c(time, status)
  missing <- setdiff(cols, names(df))
  if (length(missing)) {
    .events_refuse("Event column{?s} {.field {missing}} not found in `df`.")
  }
  role_of <- roles$role[match(cols, roles$col)]
  action_of <- roles$action[match(cols, roles$col)]
  bad_role <- cols[role_of != "outcome" | action_of != "scramble"]
  if (length(bad_role)) {
    .events_refuse(c(
      paste0(
        "Event column{?s} {.field {bad_role}} must have role ",
        "{.val outcome} and action {.val scramble}."
      ),
      i = "Set them with {.fn set_role}."
    ))
  }

  # roles_validate() has already refused a non-numeric outcome.
  not_whole <- status[!vapply(.cols(df, status), .is_whole_valued, logical(1))]
  if (length(not_whole)) {
    .events_refuse(
      "Event status{?es} {.field {not_whole}} must be whole-numbered codes."
    )
  }
  has_na <- cols[vapply(.cols(df, cols), anyNA, logical(1))]
  if (length(has_na)) {
    .events_refuse(c(
      "Event column{?s} {.field {has_na}} contain{?s/} missing values.",
      i = paste0(
        "Gaps cannot be rebuilt across a missing time; complete or drop ",
        "those rows first."
      )
    ))
  }

  if (length(time) > 1L) {
    tm <- as.matrix(.cols(df, time))
    back <- which(apply(tm, 1L, function(r) any(diff(r) < 0)))
    if (length(back)) {
      .events_refuse(c(
        paste0(
          "Event times {.field {time}} are out of order in ",
          "{length(back)} row{?s} of the original table."
        ),
        i = paste0(
          "List the times in the order the events occur; each must be at ",
          "least the one before it."
        )
      ))
    }
  }
  list(time = time, status = status)
}

.events_refuse <- function(msg) {
  cli::cli_abort(
    msg,
    class = c("masque_bad_events_refusal", "orchestra_refusal"),
    .envir = parent.frame()
  )
}

# `strata`: NULL (arm-blind) or the row strata patterns are permuted in.
.synthesise_events <- function(df, spec, strata, jitter, min_stratum) {
  n <- nrow(df)
  k <- length(spec$time)

  # Gaps and status patterns ---------------------------------------------------
  tm <- as.matrix(.cols(df, spec$time))
  gaps <- tm
  if (k > 1L) {
    gaps[, -1L] <- tm[, -1L, drop = FALSE] - tm[, -k, drop = FALSE]
  }
  pattern <- do.call(
    paste, c(lapply(.cols(df, spec$status), as.character), sep = "/")
  )

  # Permute whole status rows, within strata when the clone is conditional, so
  # pattern counts (per stratum) are exact and no real row keeps its own.
  grp <- if (is.null(strata)) rep("all", n) else as.character(strata)
  perm <- seq_len(n)
  for (idx in split(seq_len(n), grp)) {
    perm[idx] <- idx[sample.int(length(idx))]
  }
  pattern_new <- pattern[perm]
  cell <- paste(grp, pattern_new, sep = "|")
  cell_obs <- paste(grp, pattern, sep = "|")

  # Re-simulate free gaps within each stratum x pattern cell ------------------
  free_in <- function(rows) colSums(gaps[rows, , drop = FALSE] != 0) > 0L
  gaps_new <- matrix(0, nrow = n, ncol = k)
  # Longest observed final time of the rows each draw came from.
  cap <- rep(Inf, n)
  pooled <- character()
  for (cl in unique(cell)) {
    rows_new <- which(cell == cl)
    rows_obs <- which(cell_obs == cl)
    free <- free_in(rows_obs)
    if (!any(free)) next
    if (length(rows_obs) >= min_stratum) {
      gaps_new[rows_new, free] <- .draw_gaps(
        gaps[rows_obs, free, drop = FALSE], length(rows_new), jitter
      )
      cap[rows_new] <- max(tm[rows_obs, k])
      next
    }
    # Small cell: fall back to the same pattern across strata, then pool each
    # free gap over every pattern in which it is free.
    pat <- pattern_new[rows_new[1L]]
    pat_rows <- which(pattern == pat)
    if (length(pat_rows) >= min_stratum) {
      gaps_new[rows_new, free] <- .draw_gaps(
        gaps[pat_rows, free, drop = FALSE], length(rows_new), jitter
      )
      cap[rows_new] <- max(tm[pat_rows, k])
      next
    }
    # A pooled pattern's own maximum is a real row's time; cap at the
    # table's longest follow-up instead.
    cap[rows_new] <- max(tm[, k])
    pooled <- c(pooled, pat)
    for (j in which(free)) {
      pool <- .gap_pool(gaps, pattern, j)
      if (all(pattern[pool] == pat)) {
        .events_refuse(c(
          paste0(
            "Event gap {j} of {.field {spec$time}} is free only in status ",
            "pattern {.val {pat}}, which has {length(pat_rows)} row{?s} ",
            "(fewer than {min_stratum})."
          ),
          i = paste0(
            "There is no other pattern to pool it with; the clone would ",
            "carry those rows' real times."
          )
        ))
      }
      gaps_new[rows_new, j] <- .draw_gaps(
        gaps[pool, j, drop = FALSE], length(rows_new), jitter
      )
    }
  }

  # Sum gaps back into times and restore storage classes ----------------------
  times_new <- gaps_new
  for (j in seq_len(k)[-1L]) {
    times_new[, j] <- times_new[, j - 1L] + gaps_new[, j]
  }
  capped <- .cap_final_time(times_new, gaps_new, cap)
  times_new <- capped$times
  out <- list()
  for (j in seq_len(k)) {
    v <- times_new[, j]
    out[[spec$time[j]]] <- if (is.integer(df[[spec$time[j]]])) {
      as.integer(round(v))
    } else {
      v
    }
  }
  for (s in spec$status) {
    out[[s]] <- df[[s]][perm]
  }

  pooled <- sort(unique(pooled))
  list(
    columns = out,
    report  = list(
      time     = spec$time,
      status   = spec$status,
      strata   = !is.null(strata),
      patterns = length(unique(pattern)),
      pooled   = pooled,
      clipped  = capped$clipped,
      rescaled = capped$rescaled
    )
  )
}

# A row whose earlier times reach `cap` is scaled, so no gap changes sign.
.cap_final_time <- function(times, gaps, cap) {
  k <- ncol(times)
  over <- which(times[, k] > cap)
  rescaled <- 0L
  for (i in over) {
    pos <- which(gaps[i, -1L] > 0) + 1L
    z <- if (length(pos)) max(pos) else 1L
    if (z == 1L || times[i, z - 1L] < cap[i]) {
      times[i, z:k] <- cap[i]
    } else {
      times[i, ] <- times[i, ] * cap[i] / times[i, k]
      rescaled <- rescaled + 1L
    }
  }
  list(times = times, clipped = length(over), rescaled = rescaled)
}

# Rows of every status pattern in which gap `j` is free.
.gap_pool <- function(gaps, pattern, j) {
  free_pat <- tapply(gaps[, j] != 0, pattern, any)
  which(pattern %in% names(free_pat)[free_pat])
}

# The pool has at least `n` rows; a pool-sized draw is jittered, then cut.
.draw_gaps <- function(obs, n, jitter) {
  x_obs <- as.data.frame(obs)
  x_new <- synthesise_numeric_local(x_obs)
  if (isTRUE(jitter)) {
    for (j in seq_along(x_new)) {
      x_new[[j]] <- synthesise_numeric_collaborate(x_obs[[j]], x_new[[j]])
    }
  }
  as.matrix(x_new)[seq_len(n), , drop = FALSE]
}

# One recipe/print line for an event report.
.event_report_line <- function(er) {
  line <- sprintf(
    "linked events %s re-simulated as gaps within %d status pattern%s%s",
    paste(er$time, collapse = " -> "), er$patterns,
    if (er$patterns == 1L) "" else "s",
    if (isTRUE(er$strata)) ", within treatment" else ", arm-blind"
  )
  if (length(er$pooled)) {
    line <- paste0(
      line, "; pooled small pattern", if (length(er$pooled) > 1L) "s" else "",
      " ", paste(er$pooled, collapse = ", ")
    )
  }
  if (isTRUE(er$clipped > 0L)) {
    line <- paste0(
      line, "; final time capped at the pattern's longest observed ",
      "follow-up in ", er$clipped, " row", if (er$clipped > 1L) "s" else ""
    )
  }
  paste0(line, ".")
}
