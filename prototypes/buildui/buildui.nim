## A declarative widget tree (prototype): `buildUi:`, see `builduiplug`.

template buildUi*(body: untyped) {.plugin: "builduiplug".}
  ## Builds a widget tree once and binds what it binds; the `as` names are
  ## declared in the caller's scope.
