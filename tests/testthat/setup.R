# Shared test setup helpers for masque.

# Capture both stdout AND stderr (cli writes to stderr via message()).
# Returns the combined output as a single character scalar.
capture_full <- function(expr) {
  e <- substitute(expr)
  parent <- parent.frame()
  out <- utils::capture.output(eval(e, parent))
  msg <- utils::capture.output(eval(e, parent), type = "message")
  paste(c(out, msg), collapse = "\n")
}
