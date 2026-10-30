# roles_accessor.R -- roles(): the public role table of a clone.

#' The role table of a masked clone
#'
#' Returns the role each column of the clone was masked under, in the
#' clone's own vocabulary: one row per column of [synthetic()], in the same
#' order and under the same names. When the column names were aliased
#' (`alias_names` in [mask()]), the rows carry the aliases, so the table can
#' travel with the clone without disclosing the original names. A dropped
#' column is not in the clone and has no row.
#'
#' Only the four public columns are returned. The proposal's notes and its
#' value summaries describe the original table and stay on the private
#' recipe, as does the full role table used on the original
#' (`recipe(m)@roles`).
#'
#' @param m A `masque` object from [mask()], or a `masque_set` from
#'   [mask_set()].
#'
#' @returns For a `masque`, a data.table with columns `col`, `role`,
#'   `action` and `kind`. For a `masque_set`, a named list of such tables,
#'   one per table of the set.
#'
#' @examples
#' r <- propose_roles(iris)
#' r <- set_role(r, "Sepal.Length", role = "outcome")
#' m <- mask(iris, r, seed = 1)
#' roles(m)
#'
#' @seealso [synthetic()], [data_card()], [mask()].
#'
#' @export
roles <- function(m) {
  if (S7::S7_inherits(m, masque_set)) {
    out <- lapply(names(m@synthetic), function(nm) {
      .public_roles(m@recipe@recipes[[nm]], m@synthetic[[nm]])
    })
    return(stats::setNames(out, names(m@synthetic)))
  }
  if (!S7::S7_inherits(m, masque_obj)) {
    cli::cli_abort(
      paste0(
        "`m` must be a {.cls masque} or {.cls masque_set} object; got ",
        "{.cls {class(m)[1]}}."
      ),
      class = c("masque_bad_masque_obj_refusal", "orchestra_refusal")
    )
  }
  .public_roles(m@recipe, m@synthetic)
}

#' @noRd
.public_roles <- function(rec, synth) {
  r <- as.data.frame(rec@roles)
  clone_col <- r$col
  map <- rec@column_name_map
  if (length(map)) {
    hits <- clone_col %in% names(map)
    clone_col[hits] <- unname(unlist(map[clone_col[hits]]))
  }
  idx <- match(names(synth), clone_col)
  data.table::data.table(
    col = names(synth),
    role = r$role[idx],
    action = r$action[idx],
    kind = r$kind[idx]
  )
}
