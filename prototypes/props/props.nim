## Typed Kivy properties and events (prototype): the `properties:` block.
##
## .. code-block:: nim
##   properties:
##     type
##       Widget* = ref object of RootObj
##         x* {.prop.}: float = 0.0
##         opacity* {.bounds: 0.0 .. 1.0.}: float = 1.0
##         pos* {.refs: (x, y).}: (float, float)
##         press* {.event.}: proc ()
##
## generates for each property `p`: `p`, `p=` (dispatches only on a change),
## `bindP` (returns a `Binding`), `unbindP` and `initP` (sets without a
## dispatch); for each event `e`: `bindE`, `unbindE`, `dispatchE` and the
## default handler, the base method `onE`; and `initProps` for the defaults.
## A module that uses a `properties:` block imports std/syncio (`quit`).

import observers
export observers

template properties*(body: untyped) {.plugin: "propsplug".}
  ## Declares types with properties and events; see the module doc.
