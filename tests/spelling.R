if (requireNamespace("spelling", quietly = TRUE)) {
  # DESCRIPTION declares `Language: en-AU`, which routes the spell check
  # through the `en_AU` Hunspell dictionary. That dictionary is not part
  # of every CI image (it is missing from the standard r-lib runners and
  # at least some r-universe images). Degrade gracefully: skip the check
  # with a message rather than fail R CMD check, so the dictionary
  # coverage we *do* get on machines that have it (maintainer's macOS,
  # local dev) is preserved without breaking remote builds.
  tryCatch(
    spelling::spell_check_test(
      vignettes    = TRUE,
      error        = FALSE,
      skip_on_cran = TRUE
    ),
    error = function(e) {
      if (grepl("Dictionary file not found", conditionMessage(e),
                fixed = TRUE)) {
        message(sprintf(
          "Skipping spelling check: %s (dictionary not installed).",
          conditionMessage(e)
        ))
      } else {
        stop(e)
      }
    }
  )
}
