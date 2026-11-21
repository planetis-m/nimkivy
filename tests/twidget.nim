# Tests of uix/widget (ACCEPTANCE.md, layer 6): kivy/tests/test_widget.py and
# the add_widget index tests of test_uix_widget.py, plus walk, opacity and
# the touch dispatch of a disabled widget.
#
# A WidgetException stops the program (it is a programming error, as in
# core/window), so test_invalid_add_widget runs this program again with a
# case name and checks that it stopped with Kivy's message.

import std/[assertions, cmdline, os, osproc, strutils, syncio]
import nimkivy/uix/widget
import stubs

proc expectQuit(caseName, message: string) =
  # Runs this program with `caseName`; it must stop with `message`.
  var output = ""
  var code = 0
  try:
    (output, code) = execCmdEx(quoteShell(getAppFilename()) & " " & caseName)
  except:
    quit "cannot run " & getAppFilename()
  assert code != 0, caseName & " did not stop"
  assert message in output, output

if paramCount() > 0:
  # The cases that must stop the program.
  let root = newWidget()
  case paramStr(1)
  of "add-self":
    root.addWidget(root)
  of "add-with-parent":
    let c = newWidget()
    root.addWidget(c)
    newWidget().addWidget(c)
  else: discard
  quit 0

block test_add_remove_widget:
  # kivy/tests/test_widget.py::test_add_remove_widget
  let root = newWidget()
  assert root.children.len == 0
  let c1 = newWidget()
  root.addWidget(c1)
  assert root.children == @[WidgetBase(c1)]
  root.removeWidget(c1)
  assert root.children.len == 0

block test_invalid_add_widget:
  # kivy/tests/test_widget.py::test_invalid_add_widget. Adapted: Nim's types
  # rule out None and classes; adding a widget to itself and adding one that
  # already has a parent raise WidgetException.
  expectQuit("add-self", "WidgetException: Widget instances cannot be added to themselves.")
  expectQuit("add-with-parent", "WidgetException: Cannot add <Widget>, it already has a parent")

block test_clear_widgets:
  # kivy/tests/test_widget.py::test_clear_widgets
  let root = newWidget()
  let c1 = newWidget()
  let c2 = newWidget()
  let c3 = newWidget()
  root.addWidget(c1, index = 0)
  root.addWidget(c2, index = 1)
  root.addWidget(c3, index = 2)
  assert root.children == @[WidgetBase(c1), c2, c3]
  root.clearWidgets(@[WidgetBase(c2)])
  assert root.children == @[WidgetBase(c1), c3]
  root.clearWidgets(@[])
  assert root.children == @[WidgetBase(c1), c3]
  root.clearWidgets()
  assert root.children.len == 0

block test_clear_widgets_children:
  # kivy/tests/test_widget.py::test_clear_widgets_children
  let root = newWidget()
  for _ in 0 ..< 10:
    root.addWidget(newWidget())
  assert root.children.len == 10
  root.clearWidgets(root.children)
  assert root.children.len == 0

block test_position:
  # kivy/tests/test_widget.py::test_position
  let wid = newWidget()
  wid.x = 50
  assert wid.x == 50
  assert wid.pos == (50.0, 0.0)
  wid.y = 60
  assert wid.y == 60
  assert wid.pos == (50.0, 60.0)
  wid.pos = (0.0, 0.0)
  assert wid.pos == (0.0, 0.0)
  assert wid.x == 0 and wid.y == 0

block test_size:
  # kivy/tests/test_widget.py::test_size
  let wid = newWidget()
  wid.width = 50
  assert wid.width == 50
  assert wid.size == (50.0, 100.0)
  wid.height = 60
  assert wid.height == 60
  assert wid.size == (50.0, 60.0)
  wid.size = (100.0, 100.0)
  assert wid.size == (100.0, 100.0)
  assert wid.width == 100 and wid.height == 100

block test_collision:
  # kivy/tests/test_widget.py::test_collision
  let wid = newWidget()
  assert wid.pos == (0.0, 0.0)
  assert wid.size == (100.0, 100.0)
  assert not wid.collidePoint(-1, -1)
  assert wid.collidePoint(0, 0)
  assert wid.collidePoint(50, 50)
  assert wid.collidePoint(100, 100)
  assert not wid.collidePoint(200, 0)
  assert not wid.collidePoint(500, 500)

block test_disabled:
  # kivy/tests/test_widget.py::test_disabled. Adapted: without
  # `disabled=None` (Nim's bool has no None).
  let w = newWidget()
  w.disabled = false
  w.disabled = true
  assert w.disabled

proc indexTree(index: int): (Widget, Widget, Widget, Widget) =
  # test_uix_widget.py test_add_widget_index_*: a, b, then c at `index`.
  # Adapted: Buttons become plain widgets.
  let root = newWidget()
  let a = newWidget()
  let b = newWidget()
  b.pos = (50.0, 10.0)
  let c = newWidget()
  c.pos = (10.0, 50.0)
  root.addWidget(a)
  root.addWidget(b)
  root.addWidget(c, index)
  result = (root, a, b, c)

block test_add_widget_index_0:
  # kivy/tests/test_uix_widget.py::test_add_widget_index_0: c on top.
  let (root, a, b, c) = indexTree(0)
  assert root.children == @[WidgetBase(c), b, a]
  assert root.canvas.indexof(a.canvas) == 0 and root.canvas.indexof(b.canvas) == 1 and
    root.canvas.indexof(c.canvas) == 2

block test_add_widget_index_1:
  # kivy/tests/test_uix_widget.py::test_add_widget_index_1: c between.
  let (root, a, b, c) = indexTree(1)
  assert root.children == @[WidgetBase(b), c, a]
  assert root.canvas.indexof(a.canvas) == 0 and root.canvas.indexof(c.canvas) == 1 and
    root.canvas.indexof(b.canvas) == 2

block test_add_widget_index_2:
  # kivy/tests/test_uix_widget.py::test_add_widget_index_2: c at the bottom.
  let (root, a, b, c) = indexTree(2)
  assert root.children == @[WidgetBase(b), a, c]
  assert root.canvas.indexof(c.canvas) == 0 and root.canvas.indexof(a.canvas) == 1 and
    root.canvas.indexof(b.canvas) == 2

block add_widget_canvas_before_after:
  # Widget.add_widget: `canvas` names the group, for index 0 only; with a
  # canvas.before, index 0 of the canvas stays before it.
  let root = newWidget()
  let a = newWidget()
  let b = newWidget()
  root.addWidget(a, canvas = "before")
  root.addWidget(b, canvas = "after")
  assert root.canvas.before.indexof(a.canvas) == 0
  assert root.canvas.after.indexof(b.canvas) == 0
  root.removeWidget(a)
  root.removeWidget(b)
  assert root.canvas.before.length == 0 and root.canvas.after.length == 0
  let c = newWidget()
  let d = newWidget()
  root.addWidget(c)
  root.addWidget(d, 1)
  # c's canvas is at 1, after `before`; d, added below c, takes its place.
  assert root.canvas.indexof(d.canvas) == 1 and root.canvas.indexof(c.canvas) == 2

block walk_order:
  # Widget.walk: depth first, oldest child first, then the later siblings
  # and up; loopback goes round to the start.
  let root = newWidget()
  let a = newWidget()
  let a1 = newWidget()
  let b = newWidget()
  let b1 = newWidget()
  let b2 = newWidget()
  root.addWidget(a)
  a.addWidget(a1)
  root.addWidget(b)
  b.addWidget(b1)
  b.addWidget(b2)
  assert root.walk() == @[root, a, a1, b, b1, b2]
  assert a.walk() == @[a, a1, b, b1, b2]
  assert a.walk(restrict = true) == @[a, a1]
  assert b.walk(loopback = true) == @[b, b1, b2, root, a, a1]

block opacity_and_collide_widget:
  let w = newWidget()
  w.opacity = 0.5
  assert w.canvas.opacity == 0.5
  let o = newWidget()
  o.pos = (100.0, 100.0)
  assert w.collideWidget(o)
  o.x = 101
  assert not w.collideWidget(o)

block disabled_inherited_and_touches:
  # inc_disabled/dec_disabled: a child added to a disabled parent is
  # disabled; a disabled widget swallows a touch down on it, and passes
  # nothing on.
  let parent = newWidget()
  parent.disabled = true
  let child = newWidget()
  var downs = 0
  child.bind("on_touch_down", proc (d: EventDispatcher; a: seq[Value]): bool {.closure.} =
    inc downs
    result = false)
  parent.addWidget(child)
  assert child.disabled
  let t = newUnitTestTouch(10, 10)
  assert parent.dispatch("on_touch_down", toValue(t))
  assert downs == 0
  parent.removeWidget(child)
  assert not child.disabled
  parent.disabled = false
  parent.addWidget(child)
  assert not parent.dispatch("on_touch_down", toValue(t))
  assert downs == 1

block coordinates_not_relative:
  # Widget.to_widget, to_window, to_parent and to_local: a plain widget
  # does not change coordinates unless `relative`.
  let root = newWidget()
  let w = newWidget()
  root.addWidget(w)
  w.pos = (30.0, 40.0)
  assert w.toWidget(5, 6) == (5.0, 6.0)
  assert w.toWidget(5, 6, relative = true) == (-25.0, -34.0)
  assert w.toWindow(5, 6) == (5.0, 6.0)
  assert w.toParent(5, 6, relative = true) == (35.0, 46.0)
  assert w.toLocal(35, 46, relative = true) == (5.0, 6.0)
  assert w.getRootWindow() == nil

echo "twidget: ok"
