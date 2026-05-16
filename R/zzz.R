.onLoad <- function(libname, pkgname) {
  # Wire up S7 methods at package load. Without this, `print(masque_recipe)`
  # and friends fall back to S4-style default printing, which leaks the
  # private level maps in `R CMD check`'s installed environment (devtools::test
  # works because load_all() auto-registers).
  S7::methods_register()
}
