# A copy of composeR's data_card.schema.json (contract C8 v0.1, composeR
# commit 5f75c2e) and a small validator for the JSON Schema keywords it uses.
# The schema is parsed with yaml, which reads this JSON as YAML.

.card_schema <- function() {
  yaml::read_yaml(testthat::test_path("fixtures", "data_card.schema.json"))
}

.schema_type_ok <- function(x, type) {
  switch(type,
    object = is.list(x) && (length(x) == 0L || !is.null(names(x))),
    # yaml reads a sequence of strings as a character vector.
    array = (is.list(x) || is.character(x)) && is.null(names(x)),
    string = is.character(x) && length(x) == 1L,
    integer = (is.integer(x) || (is.numeric(x) && x == round(x))) &&
      length(x) == 1L,
    number = is.numeric(x) && length(x) == 1L,
    FALSE
  )
}

# Returns a character vector of errors, empty when `x` is valid.
.schema_errors <- function(x, node, root, path = "$") {
  if (!is.null(node[["$ref"]])) {
    key <- sub("^#/\\$defs/", "", node[["$ref"]])
    return(.schema_errors(x, root[["$defs"]][[key]], root, path))
  }
  if (!is.null(node$type) && !.schema_type_ok(x, node$type)) {
    return(sprintf("%s: not of type %s", path, node$type))
  }
  errors <- character()
  if (!is.null(node$enum) && !(x %in% node$enum)) {
    errors <- c(errors, sprintf("%s: '%s' not in enum", path, x))
  }
  if (!is.null(node$pattern) && !grepl(node$pattern, x, perl = TRUE)) {
    errors <- c(errors, sprintf("%s: '%s' fails pattern", path, x))
  }
  if (identical(node$type, "object")) {
    missing <- setdiff(node$required, names(x))
    errors <- c(errors, sprintf("%s: missing '%s'", path, missing))
    if (isFALSE(node$additionalProperties)) {
      extra <- setdiff(names(x), names(node$properties))
      errors <- c(errors, sprintf("%s: unexpected '%s'", path, extra))
    }
    for (nm in intersect(names(x), names(node$properties))) {
      errors <- c(errors, .schema_errors(
        x[[nm]], node$properties[[nm]], root, paste0(path, ".", nm)
      ))
    }
  }
  if (identical(node$type, "array") && !is.null(node$items)) {
    for (i in seq_along(x)) {
      errors <- c(errors, .schema_errors(
        x[[i]], node$items, root, sprintf("%s[%d]", path, i)
      ))
    }
  }
  errors
}

# The rules composeR checks beside the schema (composeR R/data_card.R,
# .card_rule_errors): every statistic has a provenance class and every class
# names a statistic, counts fit the table, design columns are listed.
.card_rule_errors <- function(card) {
  errors <- character()
  classed <- function(obj, path, unclassed) {
    stats <- setdiff(names(obj), c(unclassed, "provenance"))
    classes <- names(obj$provenance)
    c(
      sprintf("%s.%s: no provenance class", path, setdiff(stats, classes)),
      sprintf("%s.provenance.%s: names no statistic", path,
              setdiff(classes, stats))
    )
  }
  tab <- card$table
  errors <- c(errors, classed(tab, "$.table", c("name", "source")))
  design <- card$design
  if (!is.null(design)) {
    errors <- c(errors, classed(design, "$.design", character()))
    if (xor(is.null(design$event_time_col), is.null(design$event_status_col))) {
      errors <- c(errors, "$.design: event time and status come together")
    }
    if (!is.null(design$n_events) &&
        (design$n_events < 0 || design$n_events > tab$n_rows)) {
      errors <- c(errors, "$.design.n_events out of range")
    }
    if (!is.null(design$censored_share) &&
        (design$censored_share < 0 || design$censored_share > 1)) {
      errors <- c(errors, "$.design.censored_share out of range")
    }
  }
  cols <- card$columns
  col_names <- vapply(cols, `[[`, character(1L), "name")
  if (anyDuplicated(col_names) > 0L) {
    errors <- c(errors, "$.columns: duplicated name")
  }
  if (length(cols) > tab$n_cols) {
    errors <- c(errors, "$.columns: more columns than n_cols")
  }
  for (i in seq_along(cols)) {
    col <- cols[[i]]
    path <- sprintf("$.columns[%d]", i)
    errors <- c(errors, classed(col, path, c("name", "role")))
    for (f in intersect(c("n_levels", "n_missing"), names(col))) {
      if (col[[f]] < 0 || col[[f]] > tab$n_rows) {
        errors <- c(errors, sprintf("%s.%s out of range", path, f))
      }
    }
    for (f in intersect(c("na_share", "zero_share"), names(col))) {
      if (col[[f]] < 0 || col[[f]] > 1) {
        errors <- c(errors, sprintf("%s.%s out of range", path, f))
      }
    }
  }
  named <- unlist(design[c(
    "treatment_cols", "block_cols", "env_cols", "spatial_cols", "unit_col",
    "event_time_col", "event_status_col", "competing_status_cols"
  )], use.names = FALSE)
  absent <- setdiff(named, col_names)
  c(errors, sprintf("$.design: names '%s', not a listed column", absent))
}

.expect_valid_card <- function(card) {
  errs <- c(.schema_errors(card, .card_schema(), .card_schema()),
            .card_rule_errors(card))
  expect_identical(errs, character(), info = paste(errs, collapse = "; "))
}

# A small MET-shaped table with missing values and a named treatment.
.card_plots <- function() {
  withr::with_seed(3L, {
    n <- 72L
    d <- data.frame(
      site = factor(rep(c("SITEALPHA", "SITEBRAVO", "SITECHARLIE"),
                        each = 24L)),
      rep = rep(rep(1:3, each = 8L), 3L),
      gen = factor(rep(sprintf("GENO%02d", 1:8), 9L)),
      rating = factor(sample(c("low", "mid", "high"), n, replace = TRUE),
                      levels = c("low", "mid", "high"), ordered = TRUE),
      rain = rep(c(410, 395, 520), each = 24L) + stats::rnorm(n),
      weeds = stats::rpois(n, 1),
      yield = round(5 + stats::rnorm(n), 2)
    )
    d$yield[c(3L, 17L, 40L)] <- NA
    d$weeds[c(5L, 9L)] <- NA
    d
  })
}

.card_roles <- function(df, mode = "collaborate") {
  r <- propose_roles(df, mode = mode)
  r <- set_role(r, "site", role = "design", action = "alias")
  r <- set_role(r, "rep", role = "design", action = "keep")
  r <- set_role(r, "gen", role = "treatment", action = "alias")
  r <- set_role(r, "rating", role = "covariate", action = "scramble")
  r <- set_role(r, "rain", role = "covariate", action = "scramble")
  r <- set_role(r, "weeds", role = "covariate", action = "scramble")
  r <- set_role(r, "yield", role = "outcome", action = "scramble")
  r
}
