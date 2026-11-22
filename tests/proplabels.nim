## Subclasses of tprops in another module: Label overrides inherited
## defaults; FancyButton adds a property and overrides `onPress`.
##
## The override and the constructors are in the block: a method for
## FancyButton in another module fails in shoggoth
## (planetis-m/nimony-bugs-llms#345), and a later signature in this module
## cannot name FancyButton (#290).

import propwidgets

export propwidgets

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

  proc newLabel*(): Label =
    result = Label(name: "label")
    result.initProps()

  proc newFancyButton*(): FancyButton =
    result = FancyButton(name: "fancy")
    result.initProps()
