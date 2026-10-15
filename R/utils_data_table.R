# A data.table that shares no column memory with its input, so a `:=` edit
# on a returned table never reaches the caller's data or the masque object.
.as_owned_dt <- function(x) {
  if (data.table::is.data.table(x)) {
    data.table::copy(x)
  } else {
    data.table::as.data.table(x)
  }
}
