# A data.table that shares no column memory with its input, so a `:=` edit
# on a returned table never reaches the caller's data or the masque object.
.as_owned_dt <- function(x) {
  if (data.table::is.data.table(x)) {
    data.table::copy(x)
  } else {
    data.table::as.data.table(x)
  }
}

# Column subset of a data.frame or data.table that keeps its class.
.cols <- function(x, j) {
  if (data.table::is.data.table(x)) {
    x[, j, with = FALSE]
  } else {
    x[, j, drop = FALSE]
  }
}
