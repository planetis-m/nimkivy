## Subclasses in another module (prototype): Label overrides inherited
## defaults; FancyButton adds a property and overrides `onPress`.
##
## The override is inside the block: a method for FancyButton in another
## module fails in shoggoth (planetis-m/nimony-bugs-llms#175), and a later
## signature in this module cannot name FancyButton (#290).

import std/syncio
import widgets

export widgets

properties:
  type
    Label* {.defaults: (opacity: 0.5, tags: @["label"]).} = ref object of Widget
      text* {.prop.}: string = "label"
    FancyButton* = ref object of Button
      presses* {.prop.}: int = 0

  method onPress*(w: FancyButton): bool =
    ## Counts presses; returning true is Kivy's "handled".
    w.presses = w.presses + 1
    result = true
