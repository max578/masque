#' Read a set of tables from a folder, an Excel workbook, or a list
#'
#' Ingests a multi-table dataset into a named list of data frames, ready
#' for [mask_set()]. Three input shapes are accepted:
#'
#' \describe{
#'   \item{a folder path}{Every `.csv`, `.tsv`, and `.fst` file in the
#'     folder becomes one table, named by its file name (without
#'     extension). CSV / TSV are read with `data.table::fread()`; `.fst`
#'     needs the Suggested `fst` package.}
#'   \item{an Excel workbook (`.xlsx` / `.xls`)}{Every sheet becomes one
#'     table, named by its sheet name. Needs the Suggested `readxl`
#'     package.}
#'   \item{a named list of data frames}{Returned as-is after validation.}
#' }
#'
#' Only clean rectangular tables are supported. A sheet or file that does
#' not read as a rectangle - missing header row (auto-named `...1`
#' columns), zero rows, or zero columns - fails with an explanatory error
#' naming the offending table. `masque` does not attempt to recover
#' merged cells, multi-row headers, or junk rows; tidy the source first.
#'
#' @param input A folder path, an `.xlsx` / `.xls` path, or a named list
#'   of data frames.
#' @param sheets For an Excel workbook, an optional character vector of
#'   sheet names to read (default: all sheets).
#' @param pattern For a folder, an optional regular expression to select
#'   files (default: all `.csv` / `.tsv` / `.fst`).
#'
#' @return A named list of data frames.
#'
#' @examples
#' tables <- list(
#'   plots = data.frame(site = c("A", "B"), yield = c(3.1, 4.2)),
#'   sites = data.frame(site = c("A", "B"), rainfall = c(400, 550))
#' )
#' read_set(tables)
#'
#' @seealso [mask_set()], [write_set()].
#' @export
read_set <- function(input, sheets = NULL, pattern = NULL) {
  if (is.list(input) && !is.data.frame(input)) {
    return(.validate_table_list(input))
  }
  if (!is.character(input) || length(input) != 1L) {
    cli::cli_abort(paste0(
      "`input` must be a folder path, an Excel-workbook path, or a ",
      "named list of data frames."
    ))
  }

  if (dir.exists(input)) {
    return(.read_set_folder(input, pattern))
  }
  if (file.exists(input)) {
    ext <- tolower(tools::file_ext(input))
    if (ext %in% c("xlsx", "xls")) {
      return(.read_set_excel(input, sheets))
    }
    cli::cli_abort(c(
      "{.file {input}} is a single {.val {ext}} file, not a set.",
      i = "Use {.fun mask} for one table, or point at a folder / workbook."
    ))
  }
  cli::cli_abort("No file or folder at {.file {input}}.")
}

.read_set_folder <- function(dir, pattern) {
  pat <- pattern %||% "\\.(csv|tsv|fst)$"
  files <- list.files(dir, pattern = pat, full.names = TRUE, ignore.case = TRUE)
  if (!length(files)) {
    cli::cli_abort(c(
      "No .csv / .tsv / .fst files in {.file {dir}}.",
      i = "Pass a {.arg pattern} to match other extensions."
    ))
  }
  nms <- tools::file_path_sans_ext(basename(files))
  if (anyDuplicated(nms)) {
    dup <- nms[duplicated(nms)]
    cli::cli_abort(
      "Duplicate table name(s) from differing extensions: {.val {dup}}."
    )
  }
  tables <- lapply(files, .read_one_file)
  names(tables) <- nms
  .validate_table_list(tables)
}

.read_one_file <- function(path) {
  ext <- tolower(tools::file_ext(path))
  if (ext == "fst") {
    if (!requireNamespace("fst", quietly = TRUE)) {
      cli::cli_abort(c(
        "Reading {.file {path}} needs the {.pkg fst} package.",
        i = "Install it, or export the table to CSV first."
      ))
    }
    return(as.data.frame(fst::read_fst(path)))
  }
  # data.table::fread handles CSV / TSV, delimiter sniffing, and is fast.
  as.data.frame(
    data.table::fread(path, data.table = FALSE, na.strings = c("", "NA"))
  )
}

.read_set_excel <- function(path, sheets) {
  if (!requireNamespace("readxl", quietly = TRUE)) {
    cli::cli_abort(c(
      "Reading {.file {path}} needs the {.pkg readxl} package.",
      i = "Install it, or export each sheet to CSV first."
    ))
  }
  all_sheets <- readxl::excel_sheets(path)
  use <- sheets %||% all_sheets
  unknown <- setdiff(use, all_sheets)
  if (length(unknown)) {
    cli::cli_abort(c(
      "Sheet(s) not in {.file {path}}: {.val {unknown}}.",
      i = "Available: {.val {all_sheets}}."
    ))
  }
  tables <- lapply(use, function(s) {
    as.data.frame(readxl::read_excel(path, sheet = s))
  })
  names(tables) <- use
  .validate_table_list(tables)
}

# Validate a named list of data frames: names present and unique, each a
# clean non-empty rectangle.
.validate_table_list <- function(tables) {
  if (!length(tables)) {
    cli::cli_abort("The set is empty (no tables).")
  }
  nms <- names(tables)
  if (is.null(nms) || any(!nzchar(nms))) {
    cli::cli_abort("Every table in the set must be named.")
  }
  if (anyDuplicated(nms)) {
    cli::cli_abort("Duplicate table name(s): {.val {nms[duplicated(nms)]}}.")
  }
  for (nm in nms) {
    tab <- tables[[nm]]
    if (!is.data.frame(tab)) {
      cli::cli_abort(
        "Table {.field {nm}} is not a data frame ({.cls {class(tab)[1]}})."
      )
    }
    if (ncol(tab) == 0L) {
      cli::cli_abort("Table {.field {nm}} has no columns.")
    }
    if (nrow(tab) == 0L) {
      cli::cli_abort(c(
        "Table {.field {nm}} has no rows.",
        i = "masque needs at least one row per table."
      ))
    }
    auto <- grep("^\\.{3}[0-9]+$", names(tab), value = TRUE)
    if (length(auto)) {
      cli::cli_abort(c(
        "Table {.field {nm}} has auto-named column(s): {.val {auto}}.",
        i = paste0(
          "This usually means a missing header row or a non-rectangular ",
          "sheet. Tidy the source - masque reads clean rectangles only."
        )
      ))
    }
  }
  tables
}
