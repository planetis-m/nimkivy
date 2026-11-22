# Tests of uix/layout and uix/boxlayout (ACCEPTANCE.md, layer 6):
# kivy/tests/test_uix_layout.py, BoxLayout's minimum_size and the
# placement of children with size_hint_min, and layout_hint_with_bounds
# against the numbers Kivy 2.3.2 computes for the same arguments
# (archive/reference/scenes.py's boxlayout_hints covers it in a scene too).
#
# Layout() raises in Kivy; here it stops the program, so
# test_instantiation runs this program again and checks that.

import std/[assertions, cmdline, os, osproc, strutils, syncio]
import nimkivy/clock
import nimkivy/uix/[boxlayout, anchorlayout, floatlayout]

if paramCount() > 0:
  if paramStr(1) == "layout":
    let l = Layout(cls: LayoutClass, canvas: newCanvas())
    l.initLayout()
  quit 0

block test_instantiation:
  # kivy/tests/test_uix_layout.py::test_instantiation
  var output = ""
  var code = 0
  try:
    (output, code) = execCmdEx(quoteShell(getAppFilename()) & " layout")
  except:
    quit "cannot run " & getAppFilename()
  assert code != 0
  assert "The Layout class is abstract" in output, output

proc o(xs: openArray[float]): seq[Opt[float]] =
  # A list of hints where NaN is None.
  result = @[]
  for x in xs:
    result.add(if x != x: none[float]() else: some(x))

const N = NaN

block layout_hint_with_bounds:
  # Layout.layout_hint_with_bounds; the expected numbers are Kivy's.
  let l = newBoxLayout()
  let cases = [
    (3.0, 600.0, 300.0, o([300.0, N, N]), o([N, 60.0, N]), o([1.0, 1.0, 1.0]),
      @[1.5, 0.3, 1.2]),
    (4.0, 400.0, 0.0, o([N, N, N]), o([50.0, N, 20.0]), o([1.0, 2.0, 1.0]),
      @[0.5, 3.3, 0.2]),
    (2.0, 100.0, 80.0, o([80.0, N]), o([N, N]), o([1.0, 1.0]),
      @[1.6, 0.3999999999999999]),
    (3.0, 500.0, 200.0, o([100.0, 100.0, N]), o([N, N, 30.0]), o([1.0, 1.0, 1.0]),
      @[1.4100000000000001, 1.4100000000000001, 0.18]),
    (2.5, 300.0, 250.0, o([100.0, 150.0, N]), o([N, N, N]), o([1.0, 1.0, 0.5]),
      @[0.9166666666666666, 1.25, 0.33333333333333337])]
  for (shSum, space, minBounded, mins, maxs, hint0, expected) in cases:
    var hint = hint0
    l.layoutHintWithBounds(shSum, space, minBounded, mins, maxs, hint)
    for i in 0 ..< hint.len:
      assert hint[i].get(0) == expected[i], $i & ": " & $hint[i].get(0) & " " & $expected[i]

block boxlayout_minimum_size:
  # BoxLayout(padding=10, spacing=5) of a fixed-width child, a child with
  # size_hint_min_x = 30 and a fixed-height child, horizontal then
  # vertical; the numbers are Kivy's.
  let b = newBoxLayout()
  b.padding = [10.0]
  b.spacing = 5
  let c1 = newWidget()
  c1.sizeHintX = none[float]()
  c1.width = 50
  let c2 = newWidget()
  c2.sizeHintMinX = 30.0
  let c3 = newWidget()
  c3.sizeHintY = none[float]()
  c3.height = 70
  for c in [c1, c2, c3]: b.addWidget(c)
  b.doLayout()
  assert b.minimumSize == (110.0, 90.0)
  assert c3.pos == (100.0, 10.0) and c3.size == (100.0, 70.0)
  assert c2.pos == (65.0, 10.0) and c2.size == (30.0, 80.0)
  assert c1.pos == (10.0, 10.0) and c1.size == (50.0, 80.0)
  b.orientation = orientationVertical
  b.doLayout()
  assert b.minimumSize == (70.0, 100.0)
  assert c3.pos == (10.0, 10.0) and c3.size == (80.0, 70.0)
  assert c2.pos == (10.0, 85.0) and c2.size == (80.0, 0.0)
  assert c1.pos == (10.0, 90.0) and c1.size == (50.0, 0.0)
  # An empty box: the padding.
  b.clearWidgets()
  b.doLayout()
  assert b.minimumSize == (20.0, 20.0)

block layout_trigger:
  # A change of a child's size_hint lays out again before the next frame
  # (Clock.tick_draw), once however many changes there were.
  let f = newFloatLayout()
  f.size = (200.0, 100.0)
  let c = newWidget()
  f.addWidget(c)
  Clock.tickDraw()
  assert c.size == (200.0, 100.0)
  c.sizeHint = (0.5, 0.5)
  c.posHint = {phRight: 1.0, phTop: 1.0}
  assert c.size == (200.0, 100.0)
  Clock.tickDraw()
  assert c.size == (100.0, 50.0) and c.pos == (100.0, 50.0)
  # After remove_widget the layout no longer follows the child.
  f.removeWidget(c)
  c.sizeHint = (1.0, 1.0)
  Clock.tickDraw()
  assert c.size == (100.0, 50.0)

block anchorlayout_padding:
  # AnchorLayout: anchor_x right, anchor_y bottom, padding [l, t, r, b].
  let a = newAnchorLayout()
  a.size = (300.0, 200.0)
  a.pos = (10.0, 20.0)
  a.padding = [1.0, 2.0, 3.0, 4.0]
  a.anchorX = anchorRight
  a.anchorY = anchorBottom
  let c = newWidget()
  c.sizeHint = (some(0.5), none[float]())
  a.addWidget(c)
  a.doLayout()
  assert c.size == (148.0, 100.0)
  assert c.pos == (10.0 + 300.0 - (148.0 + 3.0), 24.0)

echo "tlayout: ok"
