# Expected: compile error from the plugin, `refs` names a property that is
# not declared in the same type.
import std/syncio
import ../props
properties:
  type
    Box* = ref object of RootObj
      w* {.prop.}: float
      size* {.refs: (w, h).}: (float, float)
