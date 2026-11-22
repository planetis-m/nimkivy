# Expected: compile error from the plugin, a pragma that is not a property
# kind (`propp`).
import nimkivy/props
properties:
  type
    Box* = ref object of RootObj
      w* {.propp.}: float
