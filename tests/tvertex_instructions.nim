# Tests graphics/vertex_instructions: Kivy's test_line_rounded_rectangle, and
# the geometry Kivy computes for the same instructions, read from
# reference/out/graphics_points.txt (written by reference/graphics_points.py
# with the running Kivy). Kivy builds an instruction when it is drawn; here
# `build` is called directly, which is what the renderer does.

import std/[assertions, parseutils, strutils, syncio]
import nimkivy/graphics/[instructions, vertex_instructions]

# One overload per type, because a generic `[T: VertexInstruction]` rejects
# the subtypes (planetis-m/nimony-bugs-llms#330, bug-reports/03). It is only
# repetition, not an inaccuracy, so there is no GAP.
proc built(v: Triangle): Triangle =
  v.build()
  result = v

proc built(v: Rectangle): Rectangle =
  # Also an Ellipse or RoundedRectangle, for their points.
  v.build()
  result = v

proc built(v: Line): Line =
  v.build()
  result = v

# kivy/tests/test_graphics.py::test_line_rounded_rectangle
block test_line_rounded_rectangle:
  proc normalised(args: openArray[float]): seq[float] =
    let line = newLine()
    line.roundedRectangle = args
    result = built(line).roundedRectangle

  # basic rounded_rectangle
  assert normalised([100.0, 100, 100, 100, 10, 20, 30, 40, 100]) ==
    @[100.0, 100, 100, 100, 10, 20, 30, 40, 100]
  # The largest radius allowed is the smallest dimension minus the larger of
  # the neighbouring radii.
  assert normalised([100.0, 100, 100, 100, 100, 20, 10, 30, 100]) ==
    @[100.0, 100, 100, 100, 70, 20, 10, 30, 100]
  assert normalised([100.0, 100, 100, 100, 100, 25, 100, 50, 100]) ==
    @[100.0, 100, 100, 100, 50, 25, 50, 50, 100]
  # A circle when width and height are equal and every radius is at least
  # half the smallest dimension.
  assert normalised([100.0, 100, 100, 100, 150, 50, 50.001, 51, 100]) ==
    @[100.0, 100, 100, 100, 50, 50, 50, 50, 100]
  # The minimum radius is 1.
  assert normalised([100.0, 100, 100, 100, 0, 0, 0, 0, 100]) ==
    @[100.0, 100, 100, 100, 1, 1, 1, 1, 100]
  # Radii adjusted, and none below 1.
  assert normalised([100.0, 100, 100, 100, 100, 0, 0, 0, 100]) ==
    @[100.0, 100, 100, 100, 99, 1, 1, 1, 100]

# BorderImage has no `points` in Kivy: its nine slices, from
# vertex_instructions.pyx BorderImage.build, with Kivy's default texture
# (one pixel) when there is none.
block border_image:
  let b = newBorderImage((10.0, 20.0), (100.0, 50.0), border = [5.0, 6, 7, 8])
  b.build()
  assert b.vertices.len == 16 and b.indices.len == 54
  let v = b.vertices
  # v0, v1, v2, v3 along the bottom; v12 and v14 the inner corners.
  assert v[0].x == 10 and v[1].x == 18 and v[2].x == 104 and v[3].x == 110
  assert v[0].y == 20 and v[4].y == 25 and v[5].y == 63 and v[6].y == 70
  assert v[12].x == 18 and v[12].y == 25 and v[14].x == 104 and v[14].y == 63

# The cases of reference/graphics_points.py, in the same order.
proc line(points: openArray[float] = []; width = 1.0): Line =
  newLine(points, width = width)

proc circleLine(args: openArray[float]; width = 1.0): Line =
  result = newLine(width = width)
  result.circle = args

proc rectLine(args: openArray[float]): Line =
  result = newLine()
  result.rectangle = args

proc rrectLine(args: openArray[float]; width = 1.0): Line =
  result = newLine(width = width)
  result.roundedRectangle = args

proc rrect(pos, size: (float, float); radius: openArray[(float, float)]): RoundedRectangle =
  result = newRoundedRectangle(pos, size)
  result.radius = radius

proc rrect(pos, size: (float, float); radius: openArray[float]): RoundedRectangle =
  result = newRoundedRectangle(pos, size)
  result.radius = radius

proc caseValue(name, attr: string): seq[float] =
  # The value of `attr` of the instruction of case `name`, flattened.
  case name
  of "rect_fraction": built(newRectangle((30.5, 20.5), (100.4, 40.6))).points
  of "rect_default": built(newRectangle()).points
  of "ellipse_full": built(newEllipse((20.0, 220.0), (180.0, 120.0))).points
  of "ellipse_arc":
    built(newEllipse((240.0, 200.0), (160.0, 160.0), angleStart = 45, angleEnd = 300)).points
  of "ellipse_6": built(newEllipse((440.0, 200.0), (160.0, 160.0), segments = 6)).points
  of "ellipse_reverse":
    built(newEllipse((10.0, 10.0), (50.0, 30.0), angleStart = 300, angleEnd = 45)).points
  of "ellipse_2_segments": built(newEllipse((10.0, 10.0), (50.0, 30.0), segments = 2)).points
  of "ellipse_zero": built(newEllipse((10.0, 10.0), (0.0, 30.0))).points
  of "rrect_30", "rrect_mixed", "rrect_clamped", "rrect_no_segments", "rrect_five_radii",
      "rrect_two_radii", "rrect_default":
    let r =
      case name
      of "rrect_30": rrect((300.0, 420.0), (200.0, 140.0), [30.0])
      of "rrect_mixed":
        rrect((540.0, 420.0), (220.0, 140.0), [(10.0, 10.0), (60.0, 30.0), (0.0, 0.0),
          (40.0, 40.0)])
      of "rrect_clamped": rrect((5.0, 6.0), (100.0, 60.0), [200.0])
      of "rrect_no_segments": rrect((5.0, 6.0), (100.0, 60.0), [20.0])
      of "rrect_five_radii": rrect((0.0, 0.0), (80.0, 80.0), [1.0, 2, 3, 4, 5])
      of "rrect_two_radii": rrect((0.0, 0.0), (80.0, 80.0), [5.0, 6])
      else: newRoundedRectangle((200.0, 20.0), (560.0, 140.0))
    if name == "rrect_clamped":
      r.segments = [3, 0, 5, 2]
    elif name == "rrect_no_segments":
      r.segments = 0
    discard built(r)
    case attr
    of "points": r.points
    of "radius":
      var s: seq[float] = @[]
      for (x, y) in r.radius:
        s.add x
        s.add y
      s
    else:
      var s: seq[float] = @[]
      for n in r.segments:
        s.add float(n)
      s
  of "triangle": built(newTriangle([640.0, 200, 780, 200, 700, 360])).points
  of "triangle_default": built(newTriangle()).points
  else:
    let l =
      case name
      of "line_circle": circleLine([80.0, 160, 50])
      of "line_circle_arc": circleLine([360.0, 160, 50, 45, 135], 3)
      of "line_circle_segments": circleLine([500.0, 160, 50, 0, 270, 12], 2)
      of "line_circle_reverse": circleLine([0.0, 0, 10, 90, 0])
      of "line_rectangle": rectLine([580.0, 110, 180, 100])
      of "line_rrect": rrectLine([20.0, 20, 300, 60, 20], 2)
      of "line_rrect_four": rrectLine([340.0, 20, 300, 60, 30, 5, 0, 15], 1.2)
      of "line_rrect_resolution": rrectLine([0.0, 0, 50, 40, 8, 3])
      of "line_rrect_empty": rrectLine([0.0, 0, 0, 40, 8])
      of "line_points": line([20.0, 560, 200, 520, 120, 580])
      of "line_default": line()
      else: quit "unknown case " & name
    discard built(l)
    case attr
    of "points": l.points
    of "circle": l.circle
    of "rectangle": l.rectangle
    of "rounded_rectangle": l.roundedRectangle
    of "close": @[if l.close: 1.0 else: 0.0]
    of "width": @[l.width]
    else: quit "unknown attribute " & attr

# Kivy's numbers, against nimkivy's: exactly, or within 1e-9 relative where
# the last bits of sin, cos and tan differ (Nimony's fdlibm against glibc).
block graphics_points:
  var text = ""
  try:
    text = readFile("reference/out/graphics_points.txt")
  except:
    quit "cannot read reference/out/graphics_points.txt"
  var values, inexact = 0
  for line in text.splitLines():
    let fields = line.split(' ')
    if fields.len >= 2 and fields[0] != "canvas":
      let (name, attr) = (fields[0], fields[1])
      let got = caseValue(name, attr)
      if fields.len == 3 and fields[2] == "None":
        assert got.len == 0, name & " " & attr & " should be None"
      else:
        assert got.len == fields.len - 2,
          name & " " & attr & ": " & $got.len & " values, Kivy has " & $(fields.len - 2)
        for i in 0 ..< got.len:
          var want = 0.0
          assert parseFloat(fields[i + 2], want) > 0
          inc values
          if got[i] != want:
            inc inexact
            assert abs(got[i] - want) <= 1e-9 * max(1.0, abs(want)),
              name & " " & attr & "[" & $i & "]: " & $got[i] & ", Kivy " & $want
  assert values > 1000
  echo "graphics_points: ", values, " values, ", inexact, " not bit-identical (within 1e-9)"
