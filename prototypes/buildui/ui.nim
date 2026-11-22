## Constructors and the tree of the buildUi prototype's widgets.

import uitypes, buildui

export uitypes, buildui

proc newWidget*(): Widget =
  result = Widget()
  result.initProps()

proc newLabel*(): Label =
  result = Label()
  result.initProps()

proc newButton*(): Button =
  result = Button()
  result.initProps()

proc newSlider*(): Slider =
  result = Slider()
  result.initProps()
