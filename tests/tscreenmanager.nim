# Tests uix/screenmanager (Screen, ScreenManager, NoTransition,
# FadeTransition) against kivy/tests/test_screen.py, plus the lifecycle
# events, next/previous, renaming and removing screens, switch_to, touches
# during a transition and the fade's drawing. The `screens` trace checks the
# event order against Kivy's.

import std/[assertions, os, syncio]
import nimkivy/[clock, config, base]
import nimkivy/uix/screenmanager
import stubs

proc tickFor(seconds: float) =
  let t0 = time()
  while time() - t0 < seconds:
    sleep(10)
    Clock.tick()

Config.graphics.width = 800
Config.graphics.height = 600

block testSwitchTo:
  # test_screen.py test_switch_to (with nimkivy's default NoTransition).
  let manager = newScreenManager()
  let screen1 = newScreen("first")
  let screen2 = newScreen("second")
  manager.switchTo(screen1)
  manager.switchTo(screen2)
  manager.switchTo(screen1)
  manager.switchTo(screen2)
  manager.current = "first"
  manager.switchTo(screen1)
  manager.current = "second"
  manager.switchTo(screen2)

proc switchingDoesNotAffectScreens(make: proc (): TransitionBase {.closure.}) =
  # test_screen.py test_switching_does_not_affect_a_list_of_screens
  let scrmgr = newScreenManager()
  for i in 0 ..< 3:
    scrmgr.addWidget(newScreen($i))
  let names = scrmgr.screenNames
  scrmgr.transition = make()
  scrmgr.current = "1"
  assert names == scrmgr.screenNames
  scrmgr.transition = make()
  scrmgr.current = "2"
  assert names == scrmgr.screenNames

block testSwitchingDoesNotAffectAListOfScreens:
  # Only NoTransition and FadeTransition are ported (ACCEPTANCE.md).
  switchingDoesNotAffectScreens(proc (): TransitionBase {.closure.} = newNoTransition())
  switchingDoesNotAffectScreens(proc (): TransitionBase {.closure.} = newFadeTransition())

type Log = ref object
  lines: seq[string]

proc logEvent(s: Screen; log: Log; e: string) =
  # One closure per call: closures made in a loop share the loop's variables.
  s.bind(e, proc (d: EventDispatcher; args: seq[Value]): bool {.closure.} =
    log.lines.add Screen(d).name & " " & e
    result = false)

proc logged(s: Screen; log: Log) =
  for ev in ["on_pre_enter", "on_enter", "on_pre_leave", "on_leave"]:
    s.logEvent(log, ev)

block lifecycleNoTransition:
  let log = Log(lines: @[])
  let sm = newScreenManager()
  let a = newScreen("a")
  let b = newScreen("b")
  a.logged(log)
  b.logged(log)
  sm.addWidget(a)
  sm.addWidget(b)
  assert sm.current.get("") == "a" and sm.currentScreen == a
  assert log.lines == @["a on_pre_enter", "a on_enter"]
  sm.current = "b"
  assert sm.transition.isActive
  assert b.transitionState == tsIn and a.transitionState == tsOut
  # NoTransition: both are children until the next frame.
  assert sm.children.len == 2
  Clock.tick()
  assert not sm.transition.isActive
  assert sm.children == @[WidgetBase(b)]
  assert log.lines == @["a on_pre_enter", "a on_enter", "b on_pre_enter", "a on_pre_leave",
    "b on_enter", "a on_leave"]
  assert b.transitionProgress == 1 and a.transitionProgress == 0
  assert sm.next.get("") == "a" and sm.previous.get("") == "a"
  assert sm.hasScreen("a") and not sm.hasScreen("z")
  assert sm.getScreen("a") == a

block renameAndRemove:
  let sm = newScreenManager()
  let a = newScreen("a")
  let b = newScreen("b")
  sm.addWidget(a)
  sm.addWidget(b)
  var names: seq[seq[string]] = @[]
  sm.bind("screen_names", proc (d: EventDispatcher; v: Value) {.closure.} =
    var n: seq[string] = @[]
    for x in v.items: n.add x.str
    names.add n)
  a.name = "first"
  assert sm.current.get("") == "first"
  assert names == @[@["first", "b"]]
  # Removing the shown screen shows the next one.
  sm.removeWidget(a)
  assert sm.screenNames == @["b"] and a.manager == nil
  assert sm.current.get("") == "b"
  Clock.tick()
  assert sm.children == @[WidgetBase(b)]
  # Removing the only screen shows none.
  sm.removeWidget(b)
  assert sm.current.isNone and sm.currentScreen == nil and sm.children.len == 0
  # clear_widgets
  sm.addWidget(newScreen("x"))
  sm.addWidget(newScreen("y"))
  sm.clearWidgets()
  assert sm.screens.len == 0

block switchToRemovesOldScreen:
  let sm = newScreenManager()
  let a = newScreen("a")
  sm.switchTo(a)
  let b = newScreen("a")              # the same name: renamed
  sm.switchTo(b)
  assert b.name == "_screen0"
  Clock.tick()
  # The old screen is gone once the transition completed.
  assert sm.screens == @[b] and sm.children == @[WidgetBase(b)]

block fadeTransition:
  let sm = newScreenManager()
  let t = newFadeTransition()
  t.duration = 0.1
  sm.transition = t
  sm.sizeHint = (none[float](), none[float]())
  sm.size = (200.0, 100.0)
  sm.pos = (10.0, 20.0)
  let a = newScreen("a")
  let b = newScreen("b")
  sm.addWidget(a)
  sm.addWidget(b)
  Clock.tickDraw()                    # the layout sizes the screen
  assert a.size == (200.0, 100.0) and a.pos == (10.0, 20.0)
  sm.current = "b"
  # Both screens are drawn into textures; neither is a child meanwhile.
  assert sm.children.len == 0 and t.isActive
  assert b.size == a.size and b.pos == a.pos
  t.animProgress(0.5)
  assert b.transitionProgress == 0.5 and a.transitionProgress == 0.5
  tickFor(0.3)
  assert not t.isActive and sm.children == @[WidgetBase(b)]
  # A touch is ignored during a transition.
  sm.current = "a"
  assert t.isActive
  assert not sm.dispatchTouchDown(newUnitTestTouch(50, 50))
  # Starting a running transition twice stops the program (tested by the
  # behaviour of `current`: it stops the running transition first).
  sm.current = "b"
  assert t.isActive and sm.currentScreen == b
  tickFor(0.3)
  assert sm.children == @[WidgetBase(b)]

echo "tscreenmanager: all tests passed"
