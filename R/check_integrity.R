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

# What the recipe records of the values. Numbers get one weighted sum per
# column, compared within a tolerance, because a table written at 15 digits and
# read back must still match; the weights make it depend on row order. Anything
# else gets a digest of its text, so a factor matches the character column a
# file gives back. Column order does not enter.
.content_fingerprint <- function(df) {
  cols <- sort(names(df), method = "radix")
  numeric_col <- vapply(cols, function(cl) is.numeric(df[[cl]]) && !is.object(df[[cl]]), logical(1L))
  sums <- lapply(cols[numeric_col], function(cl) {
    x <- as.double(df[[cl]])
    ok <- is.finite(x)
    w <- sin(seq_along(x) * sqrt(2))
    list(
      value = sum(x[ok] * w[ok]),
      scale = sum(abs(x[ok] * w[ok])),
      other = digest::digest(list(which(!ok & !is.na(x)), x[!ok & !is.na(x)]), algo = "sha256")
    )
  })
  names(sums) <- cols[numeric_col]
  text <- lapply(cols[!numeric_col], function(cl) enc2utf8(as.character(df[[cl]])))
  names(text) <- cols[!numeric_col]
  list(sums = sums, text = digest::digest(text, algo = "sha256"))
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
      abs(a$value - b$value) <= 1e-8 * max(a$scale, b$scale)
  }, logical(1L)))
}
