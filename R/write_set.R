#' Write a masked set to disk, mirroring the input format
#'
#' Writes the synthetic tables of a [mask_set()] result to disk. The
#' output format mirrors the request: a `.xlsx` path produces one
#' workbook with one sheet per table; a folder path produces one `.csv`
#' per table. The private recipe bundle is **never** written by this
#' function - persist it separately with [save_recipe()] and protect it
#' at the same security class as the original data.
#'
#' @param m A `masque_set` object from [mask_set()].
#' @param path Output location. A path ending in `.xlsx` writes a
#'   workbook (needs the Suggested `writexl` package); any other path is
#'   treated as a folder, created if necessary, and receives one
#'   `<table>.csv` per table.
#' @param overwrite Logical. When `FALSE` (default), writing over an
#'   existing file or a non-empty folder errors.
#'
#' @return `path`, invisibly.
#'
#' @examples
#' tables <- list(
#'   plots = data.frame(site = c("A", "B"), yield = c(3.1, 4.2)),
#'   sites = data.frame(site = c("A", "B"), rain = c(420, 560))
#' )
#' m <- mask_set(tables, seed = 1, quiet = TRUE)
#' dir <- file.path(tempdir(), "masked_set")
#' write_set(m, dir)
#' list.files(dir)
#'
#' @seealso [mask_set()], [read_set()], [save_recipe()].
#' @export
write_set <- function(m, path, overwrite = FALSE) {
  if (!S7::S7_inherits(m, masque_set)) {
    cli::cli_abort(
      "`m` must be a {.cls masque_set} object; got {.cls {class(m)[1]}}."
    )
  }
  if (!is.character(path) || length(path) != 1L || !nzchar(path)) {
    cli::cli_abort("`path` must be a single non-empty string.")
  }
  tables <- m@synthetic

  if (grepl("\\.xlsx$", path, ignore.case = TRUE)) {
    .write_set_excel(tables, path, overwrite)
  } else {
    .write_set_folder(tables, path, overwrite)
  }
  invisible(path)
}

.write_set_excel <- function(tables, path, overwrite) {
  if (!requireNamespace("writexl", quietly = TRUE)) {
    cli::cli_abort(c(
      "Writing {.file {path}} needs the {.pkg writexl} package.",
      i = "Install it, or write to a folder of CSVs instead."
    ))
  }
  if (file.exists(path) && !overwrite) {
    cli::cli_abort(c(
      "{.file {path}} already exists.",
      i = "Pass {.code overwrite = TRUE} to replace it."
    ))
  }
  writexl::write_xlsx(tables, path = path)
}

.write_set_folder <- function(tables, dir, overwrite) {
  if (dir.exists(dir)) {
    existing <- list.files(dir, pattern = "\\.csv$", ignore.case = TRUE)
    if (length(existing) && !overwrite) {
      cli::cli_abort(c(
        "{.file {dir}} already contains CSV file(s).",
        i = "Pass {.code overwrite = TRUE} to replace them."
      ))
    }
  } else {
    dir.create(dir, recursive = TRUE)
  }
  for (nm in names(tables)) {
    file <- file.path(dir, paste0(nm, ".csv"))
    data.table::fwrite(tables[[nm]], file)
  }
}
