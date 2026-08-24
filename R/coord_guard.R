#' Internal: refuse to emit an unmasked coordinate
#'
#' A masked table must not carry a real coordinate. Coordinates are among the
#' most re-identifying columns a table holds -- a paddock position is close to
#' an identity -- so the burden is on the caller to say what should happen to
#' them, and the default when nothing is said is to stop.
#'
#' Two confidence tiers, because the cost of being wrong differs:
#'
#' - A column whose **name** says coordinate (`gps`, `lat`, `lon`, ...) is
#'   high confidence. Kept, undeclared and unaliased, it aborts.
#' - A column detected only by the **shape of its values** -- a numeric pair
#'   inside plausible latitude / longitude ranges, carrying real decimal
#'   precision -- is lower confidence. It warns rather than aborts, because a
#'   false positive would block a legitimate mask.
#'
#' Either way the caller can state otherwise, three ways: declare the pair to
#' `coords` so it is coarsened, give the column a masking action (`drop` or
#' `scramble`), or pass `allow_unmasked_coords = TRUE` deliberately.
#'
#' @keywords internal
#' @noRd
.guard_unmasked_coords <- function(df, roles, coord_cols, allow) {
  if (!"action" %in% names(roles)) {
    return(invisible(NULL))
  }
  kept <- roles$col[roles$action == "keep"]
  kept <- setdiff(kept, coord_cols) # declared to `coords`: already coarsened
  if (!length(kept)) {
    return(invisible(NULL))
  }

  named <- kept[matches_pattern(kept, COORD_NAME_PATTERN)]
  shaped <- setdiff(.coordinate_shaped_pairs(df, kept), named)

  if (length(named) && !isTRUE(allow)) {
    cli::cli_abort(c(
      paste0(
        "{cli::qty(length(named))}Coordinate column{?s} {.field {named}} ",
        "would be written unmasked."
      ),
      x = paste0(
        "A real coordinate in a masked table is a re-identifying value: a ",
        "position locates the site, and often the operator with it."
      ),
      i = paste0(
        "{cli::qty(length(named))}Coarsen {?it/them}: ",
        "{.code mask(df, roles, coords = list(c(lat = ",
        "\"...\", lon = \"...\")))}."
      ),
      i = paste0(
        "Or remove: ",
        "{.code set_role(roles, \"{named[1]}\", action = \"drop\")}."
      ),
      i = paste0(
        "Or, having decided the coordinate is not sensitive, say so: ",
        "{.code allow_unmasked_coords = TRUE}."
      )
    ), class = "masque_unmasked_coords")
  }

  if (length(named) && isTRUE(allow)) {
    cli::cli_warn(c(
      paste0(
        "{cli::qty(length(named))}Writing coordinate column{?s} ",
        "{.field {named}} unmasked, as instructed."
      ),
      i = paste0(
        "{.code allow_unmasked_coords = TRUE} was passed; recorded on the ",
        "recipe."
      )
    ), class = "masque_unmasked_coords_allowed")
  }

  if (length(shaped) && !isTRUE(allow)) {
    cli::cli_warn(c(
      paste0(
        "{cli::qty(length(shaped))}Column{?s} {.field {shaped}} ",
        "hold{?s/} values ",
        "shaped like geographic coordinates and {?is/are} being kept unmasked."
      ),
      i = paste0(
        "Detected from the values, not the name, so this may be a false ",
        "alarm. If {cli::qty(length(shaped))}{?it is/they are} coordinates, ",
        "declare {?it/them} to ",
        "{.arg coords} or give {?it/them} a masking action."
      )
    ), class = "masque_coords_suspected")
  }
  invisible(NULL)
}

# Column names that assert a coordinate. Narrower than PII_PATTERN, which also
# catches contact and identity fields that are not positions.
COORD_NAME_PATTERN <- paste0(
  "(gps|latitude|longitude|\\blat\\b|\\blon(g)?\\b|easting|northing|",
  "\\butm\\b|wgs ?84|decimal_?(lat|lon))"
)

# Numeric columns that look like a coordinate pair by value alone.
#
# Deliberately strict, because a false positive interrupts a legitimate mask.
# A candidate must be a real-valued (not whole-number) numeric, inside the
# plausible range for its axis, carrying at least four decimal places on some
# value -- coordinates are recorded to metres, whereas a temperature or a yield
# is not -- and there must be at least two such columns, since a coordinate
# travels as a pair.
.coordinate_shaped_pairs <- function(df, cols) {
  cand <- character()
  for (cn in cols) {
    x <- df[[cn]]
    if (!is.numeric(x)) next
    v <- x[is.finite(x)]
    if (length(v) < 3L || length(unique(v)) < 3L) next
    if (all(v == round(v))) next            # whole numbers: not a position
    if (max(abs(v)) > 180) next                      # outside any axis
    if (max(abs(v)) < 1) next                        # proportions, indices
    if (!.has_decimal_precision(v, 4L)) next         # metre-scale precision
    cand <- c(cand, cn)
  }
  if (length(cand) < 2L) character() else cand
}

# TRUE when some value needs at least `k` decimal places to be written down.
# A value with k-1 decimals is a whole number once scaled by 10^(k-1); one that
# needs more is not. The tolerance is relative, because 18.3 * 1000 is not
# exactly 18300 in double precision and must still read as two decimals.
.has_decimal_precision <- function(v, k) {
  z <- v * 10^(k - 1L)
  any(abs(z - round(z)) > 1e-6 * pmax(1, abs(z)))
}
