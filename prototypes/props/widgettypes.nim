## The property declarations of the prototype's Widget and Button.
##
## Only the `properties:` block lives here: a type that a module-level
## template plugin declares cannot be named in a later proc signature of the
## same module (planetis-m/nimony-bugs-llms#290), so the procs that name these
## types are in `widgets`.

import std/syncio
import props

export props

properties:
  type
    Widget* = ref object of RootObj
      x* {.prop.}: float = 0.0
      y* {.prop.}: float = 0.0
      pos* {.refs: (x, y).}: (float, float)
      opacity* {.bounds: 0.0 .. 1.0.}: float = 1.0
      tags* {.prop.}: seq[string] = @["new"]
      name*: string                  # a plain field
    Button* = ref object of Widget
      text* {.prop.}: string = ""
      press* {.event.}: proc ()
      touch* {.event.}: proc (x, y: float)

