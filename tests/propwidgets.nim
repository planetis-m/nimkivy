## The Widget and Button of tprops (the prototype's test types), declared
## with `properties:`. The constructors are in the block: a later signature
## in this module cannot name these types (planetis-m/nimony-bugs-llms#290).

import nimkivy/props

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

  proc newWidget*(name = ""): Widget =
    result = Widget(name: name)
    result.initProps()

  proc newButton*(name = ""): Button =
    result = Button(name: name)
    result.initProps()
