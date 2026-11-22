## Tests of the property prototype: typed properties, bind/unbind, change-only
## dispatch, bounds, a list, a reference list, events, subclass defaults.

import std/[syncio, assertions]
import labels

proc testDefaults() =
  let w = newWidget("w")
  assert w.x == 0.0 and w.y == 0.0 and w.opacity == 1.0
  assert w.tags == @["new"] and w.name == "w"
  assert w.pos == (0.0, 0.0)
  let l = newLabel()
  assert l.opacity == 0.5            # overridden in the subclass
  assert l.tags == @["label"]
  assert l.text == "label" and l.x == 0.0

proc testChangeOnly() =
  let w = newWidget()
  var log: seq[string] = @[]
  let b = w.bindOpacity(proc (v: float) {.closure.} =
    log.add "opacity " & $v)
  w.opacity = 0.5
  w.opacity = 0.5                    # unchanged: no dispatch
  w.opacity = 0.25
  assert log == @["opacity 0.5", "opacity 0.25"]
  w.unbindOpacity(b)
  w.opacity = 1.0
  assert log.len == 2
  w.unbindOpacity(b)                 # unbinding again is ignored

proc testOrderAndReentrancy() =
  let w = newWidget()
  var log: seq[string] = @[]
  var late = Binding(0)
  var second = Binding(0)
  discard w.bindX(proc (v: float) {.closure.} =
    log.add "first"
    w.unbindX(second)                # unbound during the dispatch: not called
    late = w.bindX(proc (v: float) {.closure.} =
      log.add "late"))               # bound during the dispatch: not called
  second = w.bindX(proc (v: float) {.closure.} = log.add "second")
  w.x = 1.0
  assert log == @["first"]
  log = @[]
  w.x = 2.0                          # now `late` runs (and binds another)
  assert log == @["first", "late"]

proc testList() =
  let w = newWidget()
  var n = 0
  discard w.bindTags(proc (v: seq[string]) {.closure.} = inc n)
  w.tags = @["new"]                  # equal list: no dispatch
  w.tags = @["a", "b"]
  w.tags = @["a", "b"]
  assert n == 1 and w.tags == @["a", "b"]

proc testReferenceList() =
  let w = newWidget()
  var log: seq[string] = @[]
  discard w.bindX(proc (v: float) {.closure.} = log.add "x " & $v)
  discard w.bindPos(proc (v: (float, float)) {.closure.} =
    log.add "pos " & $v[0] & " " & $v[1])
  # pos was linked by bindPos, after the first x observer: its trigger
  # comes after that observer and before any later one, as in Kivy.
  discard w.bindX(proc (v: float) {.closure.} = log.add "x late")
  w.pos = (0.0, 0.0)                 # the first set always dispatches pos
  assert log == @["pos 0.0 0.0"]
  log = @[]
  w.pos = (1.0, 2.0)                 # x, then y, then pos once
  assert log == @["x 1.0", "x late", "pos 1.0 2.0"]
  log = @[]
  w.x = 5.0                          # a reference alone dispatches pos too
  assert log == @["x 5.0", "pos 5.0 2.0", "x late"]
  assert w.pos == (5.0, 2.0)
  log = @[]
  w.pos = (5.0, 2.0)                 # unchanged
  assert log.len == 0

proc testEvents() =
  let b = newButton()
  var log: seq[string] = @[]
  discard b.bindPress(proc (): bool {.closure.} =
    log.add "first"
    false)
  let stopper = b.bindPress(proc (): bool {.closure.} =
    log.add "second"
    true)
  assert b.dispatchPress()           # last bound first; stops at true
  assert log == @["second"]
  b.unbindPress(stopper)
  log = @[]
  assert not b.dispatchPress()       # then the default handler: false
  assert log == @["first"]
  var at = (0.0, 0.0)
  discard b.bindTouch(proc (x, y: float): bool {.closure.} =
    at = (x, y)
    false)
  discard b.dispatchTouch(3.0, 4.0)
  assert at == (3.0, 4.0)

proc testOverriddenHandler() =
  let f = newFancyButton()
  assert f.dispatchPress()           # FancyButton's onPress method
  assert f.presses == 1
  var n = 0
  discard f.bindPresses(proc (v: int) {.closure.} = n = v)
  discard f.bindPress(proc (): bool {.closure.} = true)
  assert f.dispatchPress()           # an observer stopped it
  assert f.presses == 1 and n == 0
  f.text = "go"                      # inherited from Button
  assert f.text == "go"

testDefaults()
testChangeOnly()
testOrderAndReentrancy()
testList()
testReferenceList()
testEvents()
testOverriddenHandler()
echo "tprops: ok"
