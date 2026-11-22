## The widgets of the buildUi prototype, declared with `properties:`.

import std/syncio
import nimkivy/props
import uibase

export props, uibase

properties:
  type
    Widget* = ref object of WidgetBase
      name*: string
      opacity* {.bounds: 0.0 .. 1.0.}: float = 1.0
    Label* = ref object of Widget
      text* {.prop.}: string = ""
    Button* = ref object of Label
      press* {.event.}: proc ()
      touch* {.event.}: proc (x, y: float)
    Slider* = ref object of Widget
      value* {.bounds: 0.0 .. 1.0.}: float = 0.0
