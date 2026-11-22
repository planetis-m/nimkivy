# Expected: compile error, `refs` names something that is not a property of
# the type or its bases (`h`).
import nimkivy/props
properties:
  type
    Box* = ref object of RootObj
      w* {.prop.}: float
      size* {.refs: (w, h).}: (float, float)
