## Constructors of the subclasses.

import labeltypes

export labeltypes

proc newLabel*(): Label =
  result = Label(name: "label")
  result.initProps()

proc newFancyButton*(): FancyButton =
  result = FancyButton(name: "fancy")
  result.initProps()
