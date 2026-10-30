# Clone digests were recorded on macOS arm64; floating-point output is not
# bit-stable across platforms, so the digest checks run only there.
skip_unless_digest_platform <- function() {
  on_it <- identical(Sys.info()[["sysname"]], "Darwin") &&
    identical(R.version$arch, "aarch64")
  testthat::skip_if_not(on_it, "clone digests were recorded on macOS arm64")
}
