type
  Thing* {.plugin: "addhello".} = object
    x*: int

proc newThing*(): Thing = Thing(x: 1)
