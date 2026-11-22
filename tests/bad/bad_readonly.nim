# Expected: compile error, a read-only alias (no setter) has no setter proc.
import nimkivy/props
properties:
  type
    Box* = ref object of RootObj
      w* {.prop.}: float
      half* {.alias: getHalf.}: float
  proc getHalf(b: Box): float = b.w / 2
let b = Box()
b.initProps()
b.half = 1.0
