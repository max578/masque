if (requireNamespace("spelling", quietly = TRUE)) {
  # en_AU Hunspell is missing on some CI images: skip rather than fail.
  tryCatch(
    spelling::spell_check_test(
      vignettes    = TRUE,
      error        = FALSE,
      skip_on_cran = TRUE
    ),
    error = function(e) {
      if (grepl("Dictionary file not found", conditionMessage(e),
        fixed = TRUE
      )) {
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
