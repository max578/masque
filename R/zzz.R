.onLoad <- function(libname, pkgname) {
  # Register S7 methods on load; otherwise print(masque_recipe) falls back to
  # the S4 default and shows the private level maps.
  S7::methods_register()
}
