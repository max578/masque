# A recipe compared as data: class names and properties, recursively.
# Comparing whole S7 objects lets waldo walk into the class object's closures
# and S7's namespace, which fails under R-devel (2026-11) on S7's lazy-load
# database during R CMD check. Uses S7's exported functions only.
recipe_as_data <- function(x) {
  if (S7::S7_inherits(x)) {
    return(list(class = class(x), props = lapply(S7::props(x), recipe_as_data)))
  }
  if (is.list(x) && !is.data.frame(x)) {
    return(lapply(x, recipe_as_data))
  }
  x
}
