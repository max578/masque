#' Internal: verify the recipe's recorded NA-mask and value fingerprints
#' against the candidate `original` data frame.
#'
#' Called from [apply_recipe()] when `check_integrity = TRUE` (the
#' default). Aborts with guidance if the fingerprint does not match.
#'
#' @keywords internal
#' @noRd
.check_recipe_integrity <- function(original, rec) {
  expected <- rec@integrity_fp
  if (!is.character(expected) || length(expected) != 1L || !nzchar(expected)) {
    # Recipe was built without a fingerprint (defensive: should not happen
    # in normal flows). Surface a quiet inform and proceed.
    cli::cli_inform(c(
      i = "Recipe has no integrity fingerprint; skipping NA-mask check."
    ))
    return(invisible(TRUE))
  }
  actual <- digest::digest(is.na(original), algo = "sha256")
  if (!identical(expected, actual)) {
    cli::cli_abort(c(
      paste0(
        "Recipe integrity check failed: the NA mask of {.arg original} ",
        "does not match the recipe's recorded fingerprint."
      ),
      i = paste0(
        "The recipe was built against a data frame with a different ",
        "missingness pattern (or a different schema)."
      ),
      "*" = paste0(
        "If this is intentional (the missingness has legitimately ",
        "changed since the recipe was built), pass ",
        "{.code check_integrity = FALSE} to {.fun apply_recipe}."
      )
    ), class = c("masque_integrity_refusal", "orchestra_refusal"))
  }
  recorded <- .prop_or(rec, "content_fp", list())
  if (length(recorded) && !.content_matches(recorded, .content_fingerprint(original))) {
    cli::cli_abort(c(
      paste0(
        "Recipe integrity check failed: the values of {.arg original} ",
        "do not match the recipe's recorded fingerprint."
      ),
      i = "The recipe was built against a table with the same missingness and different values.",
      "*" = paste0(
        "If this is intentional, pass {.code check_integrity = FALSE} to ",
        "{.fun apply_recipe}. {.fun controls} has no such switch: it runs on ",
        "the table the clone was built on."
      )
    ), class = c("masque_integrity_refusal", "orchestra_refusal"))
  }
  invisible(TRUE)
}

# What the recipe records of the values: two weighted sums per numeric column
# and a digest of the rest. The tolerance covers a file at 15 digits. The sum of
# logs guards small values beside a very large one.
.content_fingerprint <- function(df) {
  cols <- sort(names(df), method = "radix")
  canon <- lapply(cols, function(cl) .content_canonical(df[[cl]]))
  names(canon) <- cols
  numeric_col <- vapply(canon, is.numeric, logical(1L))
  list(
    sums = lapply(canon[numeric_col], function(x) {
      ok <- is.finite(x)
      w <- sin(seq_along(x) * sqrt(2))
      list(
        value = sum(x[ok] * w[ok]),
        scale = sum(abs(x[ok] * w[ok])),
        log_value = sum(sign(x[ok]) * log1p(abs(x[ok])) * w[ok]),
        log_scale = sum(log1p(abs(x[ok])) * abs(w[ok])),
        other = digest::digest(list(which(!ok & !is.na(x)), x[!ok & !is.na(x)]), algo = "sha256")
      )
    }),
    text = digest::digest(canon[!numeric_col], algo = "sha256")
  )
}

# One form for a column whatever a file reader made of it: a number, where every
# value reads as one, and otherwise text. Logical values count as 0 and 1.
.content_canonical <- function(x) {
  if (is.numeric(x) && !is.object(x) || inherits(x, "integer64")) {
    return(as.double(x))
  }
  if (is.logical(x)) {
    return(as.double(x))
  }
  # c() drops the growable bit data.table may set, which serialize() would hash.
  text <- c(enc2utf8(as.character(x)))
  if (all(text[!is.na(text)] %in% c("TRUE", "FALSE"))) {
    return(as.double(text == "TRUE"))
  }
  num <- suppressWarnings(as.numeric(text))
  if (any(is.na(num) & !is.na(text))) text else num
}

.content_matches <- function(recorded, actual) {
  if (!identical(recorded$text, actual$text) ||
    !setequal(names(recorded$sums), names(actual$sums))) {
    return(FALSE)
  }
  all(vapply(names(recorded$sums), function(cl) {
    a <- recorded$sums[[cl]]
    b <- actual$sums[[cl]]
    identical(a$other, b$other) &&
      abs(a$value - b$value) <= 1e-14 * max(a$scale, b$scale) &&
      abs(a$log_value - b$log_value) <= 1e-14 * max(a$log_scale, b$log_scale)
  }, logical(1L)))
}
