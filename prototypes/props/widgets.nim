## A tiny Widget and Button with typed properties and events (prototype).

import widgettypes

export widgettypes

proc newWidget*(name = ""): Widget =
  result = Widget(name: name)
  result.initProps()

proc newButton*(name = ""): Button =
  result = Button(name: name)
  result.initProps()
