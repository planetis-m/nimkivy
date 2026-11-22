# Tests graphics/vertex_instructions: Kivy's test_line_rounded_rectangle,
# test_smoothline_rounded_rectangle and SmoothVertexInstructionTest, and the
# geometry Kivy computes for the same instructions, read from
# tests/fixtures/graphics_points.txt and smooth_points.txt (written by
# archive/reference/graphics_points.py and smooth.py with the running Kivy).
# Kivy builds an instruction when it is drawn; here `build` is called
# directly, which is what the renderer does.

import std/[assertions, parseutils, strutils, syncio]
import nimkivy/config
import nimkivy/graphics/[instructions, texture, vertex_instructions]
import nimkivy/core/image

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

# The cases of archive/reference/graphics_points.py, in the same order.
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
    of "roundedRectangle": l.roundedRectangle
    of "close": @[if l.close: 1.0 else: 0.0]
    of "width": @[l.width]
    else: quit "unknown attribute " & attr

# Kivy's numbers, against nimkivy's: exactly, or within 1e-9 relative where
# the last bits of sin, cos and tan differ (Nimony's fdlibm against glibc).
block graphics_points:
  var text = ""
  try:
    text = readFile("tests/fixtures/graphics_points.txt")
  except:
    quit "cannot read tests/fixtures/graphics_points.txt"
  var values, inexact = 0
  for line in text.splitLines():
    let fields = line.split(' ')
    if fields.len >= 2 and fields[0] != "canvas":
      let (name, attr) = (fields[0], fields[1])
      let got = caseValue(name, attr)
      if fields.len == 3 and fields[2] == "none":
        assert got.len == 0, name & " " & attr & " should be none"
      elif attr == "close":
        # A bool, which caseValue gives as 1.0 or 0.0.
        assert fields.len == 3 and fields[2] == $(got == @[1.0]),
          name & " close differs from Kivy's " & fields[2]
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

# ---------------------------------------------------------------- smooth instructions

# kivy/tests/test_graphics.py::test_smoothline_rounded_rectangle
block test_smoothline_rounded_rectangle:
  # Under 2 px wide or high, the figure is not drawn.
  let line = newSmoothLine()
  line.roundedRectangle = [100.0, 100, 0.5, 1.99, 30, 30, 30, 30, 100]
  line.build()
  assert line.roundedRectangle.len == 0      # None

# SmoothVertexInstructionTest._filtered_points: the AntiAliasingLine filter,
# written out again by the test.
proc filtered(points: openArray[float]): seq[float] =
  if points.len < 6:
    return @[]
  var p = @points
  var index = 0
  while index < p.len - 2:
    if abs(p[index + 2] - p[index]) < 1.0 and abs(p[index + 3] - p[index + 1]) < 1.0:
      p.delete(index + 2)
      p.delete(index + 2)
    else:
      index += 2
  if abs(p[0] - p[p.len - 2]) < 1.0 and abs(p[1] - p[p.len - 1]) < 1.0:
    p.delete(0)
    p.delete(0)
  result = p

proc closed(p: seq[float]): seq[float] =
  # `filtered_points + filtered_points[:2]`
  result = p
  if p.len >= 2:
    result.add p[0]
    result.add p[1]

proc aTexture(): Texture =
  # SmoothVertexInstructionTest._get_texture: any texture but the default.
  newTexture(1, 1, [255'u8, 255, 255, 255])

const
  Points1 = [51.0, 649.0, 199.0, 649.0, 199.0, 501.0, 51.0, 501.0]
  Points2 = [261.0, 275.0, 335.0, 349.0, 335.0, 349.0, 409.0, 275.0, 409.0, 275.0, 335.0,
    201.0, 335.0, 201.0, 261.0, 275.0]
  Points3 = [260.0, 275.0, 261.0, 275.0, 261.0, 275.0, 261.999999999999, 275.99999999,
    261.06667650085353, 278.14064903651496, 261.26658584785304, 281.2756384111877,
    261.56658584785305, 281.3756384111877, 261.5993677908431, 284.39931866126904,
    262.0644226342696, 287.50606070381684, 262.0644226342696, 287.50606070381684,
    262.6609123178712, 290.59026597968375, 263.3877619269211, 293.6463765424993,
    264.2436616292954, 296.66888507446475, 265.22706903587977, 299.65234481091227,
    265.22706903587977, 299.65234481091227, 266.3362119800583, 302.59137935574284,
    267.5690917112779, 305.48069237005546, 268.9234864969319, 308.31507711650784,
    270.39695562607204, 311.089425842209, 270.89695562607204, 311.589425842209,
    271.98684380773494, 313.7987389832352, 273.69028595595563, 316.4381341741821,
    275.50421235284637, 319.00285504651725, 275.50421235284637, 319.00285504651725,
    277.4253541804354, 321.48827979987755, 279.45024941129833, 323.8899295308661,
    281.57524904736516, 326.20347630433844, 283.79652369566156, 328.4247509526349,
    283.99652369566156, 328.7247509526349, 286.1100704691339, 330.54975058870167,
    288.5117202001224, 332.5746458195646, 288.5117202001224, 332.5746458195646,
    290.99714495348275, 334.4957876471537, 293.5618658258179, 336.3097140440444,
    293.5618658258179, 336.3097140440444, 293.2618658258179, 336.1097140440444]
  Points4 = [100.0, 100, 200, 100]

# kivy/tests/test_graphics.py::SmoothVertexInstructionTest::test_antialiasing_line
# Adapted: the TypeError for a `stencil_mask` that is not an Instruction is a
# compile error here; the texture's gradient is checked as the texture's size
# and the bytes it is made of (Kivy reads them back from GL).
block test_antialiasing_line:
  discard newAntiAliasingLine(newRectangle(), [10.0, 20, 30, 40, 50, 60])
  let aaLine = newAntiAliasingLine(Instruction())
  let t = aaLine.texture
  assert t != nil and t.size == (3, 1)
  assert AntiAliasingLineGradient == [0xff'u8, 0xff, 0xff, 0x00, 0xff, 0xff, 0xff, 0xff,
    0xff, 0xff, 0xff, 0x00]
  # The width, defined through tests with the custom texture.
  assert aaLine.width == 2.5
  # Points1 stays as it is, Points2 goes from 16 to 8 values, Points3 from 72
  # to 50, and Points4 to none; the line is closed by default.
  assert filtered(Points1).len == 8 and filtered(Points2).len == 8 and
    filtered(Points3).len == 50 and filtered(Points4).len == 0
  for points in [@Points1, @Points2, @Points3, @Points4]:
    let a = newAntiAliasingLine(Instruction(), points)
    assert a.points == closed(filtered(points))
  # Without closing the line.
  for points in [@Points1, @Points2, @Points3, @Points4]:
    let a = newAntiAliasingLine(Instruction(), points, close = false)
    assert a.points == filtered(points)

# kivy/tests/test_graphics.py::SmoothVertexInstructionTest::test_smoothrectangle
block test_smoothrectangle:
  var rect = newSmoothRectangle((100.0, 100.0), (150.0, 150.0))
  rect.build()
  let fp = filtered(rect.points)
  assert rect.antialiasingLinePoints == closed(fp)
  # Antialiasing is disabled when a side is under 4 px.
  rect.size = (150.0, -2.0)
  rect.build()
  assert rect.antialiasingLinePoints.len == 0
  rect.size = (150.0, 2.0)
  rect.build()
  assert rect.antialiasingLinePoints.len == 0
  # Enabled again.
  rect.size = (150.0, 150.0)
  rect.build()
  assert rect.antialiasingLinePoints == closed(fp)
  # A texture disables it, and `source = ""` enables it again.
  rect.texture = aTexture()
  rect.build()
  assert rect.antialiasingLinePoints.len == 0
  rect.source = ""
  rect.build()
  assert rect.antialiasingLinePoints == closed(fp)
  # Disabled from the start when a side is under 4 px.
  rect = newSmoothRectangle((100.0, 100.0), (150.0, -3.0))
  rect.build()
  assert rect.antialiasingLinePoints.len == 0
  rect = newSmoothRectangle((100.0, 100.0), (3.99, 3.99))
  rect.build()
  assert rect.antialiasingLinePoints.len == 0

# kivy/tests/test_graphics.py::SmoothVertexInstructionTest::test_smoothroundedrectangle
block test_smoothroundedrectangle:
  var rr = newSmoothRoundedRectangle((100.0, 100.0), (150.0, 150.0))
  rr.radius = [(10.0, 50.0), (100.0, 50.0), (0.0, 150.0), (200.0, 50.0)]
  rr.segments = 60
  rr.build()
  let fp = filtered(rr.points)
  assert rr.antialiasingLinePoints == closed(fp)
  rr.size = (150.0, -2.0)
  rr.build()
  assert rr.antialiasingLinePoints.len == 0
  rr.size = (150.0, 2.0)
  rr.build()
  assert rr.antialiasingLinePoints.len == 0
  rr.size = (150.0, 150.0)
  rr.build()
  assert rr.antialiasingLinePoints == closed(fp)
  rr.texture = aTexture()
  rr.build()
  assert rr.antialiasingLinePoints.len == 0
  rr.source = ""
  rr.build()
  assert rr.antialiasingLinePoints == closed(fp)
  rr = newSmoothRoundedRectangle((100.0, 100.0), (150.0, 150.0))
  rr.segments = 0
  rr.build()
  assert rr.antialiasingLinePoints == closed(filtered(rr.points))
  rr = newSmoothRoundedRectangle((100.0, 100.0), (150.0, -3.0))
  rr.build()
  assert rr.antialiasingLinePoints.len == 0
  rr = newSmoothRoundedRectangle((100.0, 100.0), (3.99, 3.99))
  rr.build()
  assert rr.antialiasingLinePoints.len == 0

# kivy/tests/test_graphics.py::SmoothVertexInstructionTest::test_smoothellipse
block test_smoothellipse:
  proc centred(e: SmoothEllipse): seq[float] =
    # `ellipse.points + ellipse_center`, the centre from pos and size.
    result = e.points
    result.add e.pos[0] + e.size[0] / 2
    result.add e.pos[1] + e.size[1] / 2
  var e = newSmoothEllipse((100.0, 100.0), (150.0, 150.0))
  e.build()
  let fp = filtered(centred(e))
  assert e.antialiasingLinePoints == closed(fp)
  e.size = (150.0, -2.0)
  e.build()
  assert e.antialiasingLinePoints.len == 0
  e.size = (150.0, 2.0)
  e.build()
  assert e.antialiasingLinePoints.len == 0
  e.size = (150.0, 150.0)
  e.build()
  assert e.antialiasingLinePoints == closed(fp)
  e.texture = aTexture()
  e.build()
  assert e.antialiasingLinePoints.len == 0
  e.source = ""
  e.build()
  assert e.antialiasingLinePoints == closed(fp)
  e = newSmoothEllipse((100.0, 100.0), (150.0, 150.0), angleStart = 90, angleEnd = -120)
  e.build()
  assert e.antialiasingLinePoints == closed(filtered(centred(e)))
  e = newSmoothEllipse((100.0, 100.0), (150.0, -3.0))
  e.build()
  assert e.antialiasingLinePoints.len == 0
  e = newSmoothEllipse((100.0, 100.0), (3.99, 3.99))
  e.build()
  assert e.antialiasingLinePoints.len == 0

# kivy/tests/test_graphics.py::SmoothVertexInstructionTest::test_smoothtriangle
block test_smoothtriangle:
  var t = newSmoothTriangle([100.0, 100, 200, 100, 150, 200,
    500, 500, 400, 400])          # the last four only for testing purposes
  t.build()
  assert t.antialiasingLinePoints == closed(filtered(t.points[0 .. 5]))
  t = newSmoothTriangle([125.0, 200, 200, 100, 100, 100, 500, 500, 400, 400])
  t.build()
  let fp = filtered(t.points[0 .. 5])
  assert t.antialiasingLinePoints == closed(fp)
  # Points too close together disable it.
  t = newSmoothTriangle([100.0, 100, 100.5, 100, 100, 100.5])
  t.build()
  assert t.antialiasingLinePoints.len == 0
  t.points = [125.0, 200, 200, 100, 100, 100]
  t.build()
  assert t.antialiasingLinePoints == closed(fp)
  t.texture = aTexture()
  t.build()
  assert t.antialiasingLinePoints.len == 0
  t.source = ""
  t.build()
  assert t.antialiasingLinePoints == closed(fp)

# kivy/tests/test_graphics.py::SmoothVertexInstructionTest::test_smoothquad
block test_smoothquad:
  var q = newSmoothQuad([100.0, 100, 100, 200, 200, 200, 200, 100])
  q.build()
  assert q.antialiasingLinePoints == closed(filtered(q.points))
  q = newSmoothQuad([200.0, 100, 200, 200, 100, 200, 100, 100])
  q.build()
  let fp = filtered(q.points)
  assert q.antialiasingLinePoints == closed(fp)
  q = newSmoothQuad([200.0, 100, 200, 100.8, 100, 100.8, 100, 100])
  q.build()
  assert q.antialiasingLinePoints.len == 0
  q.points = [200.0, 100, 200, 200, 100, 200, 100, 100]
  q.build()
  assert q.antialiasingLinePoints == closed(fp)
  q.texture = aTexture()
  q.build()
  assert q.antialiasingLinePoints.len == 0
  q.source = ""
  q.build()
  assert q.antialiasingLinePoints == closed(fp)

# Kivy's radd_instructions: the shape and its line, each with its BindTexture,
# count four in the canvas; `remove` and `clear` take all four.
block smooth_canvas_children:
  let c = newCanvas()
  let e = newSmoothEllipse()
  c.add e
  assert c.length == 4 and c.indexof(e) == 1 and c.indexof(e.antialiasingLine) == 3
  c.insert(0, newSmoothRectangle())
  assert c.length == 8 and c.indexof(e) == 5
  c.remove(e)
  assert c.length == 4
  c.clear()
  assert c.length == 0

# smooth.py's cases, against tests/fixtures/smooth_points.txt.
proc pair(v: (float, float)): seq[float] = @[v[0], v[1]]

proc smoothValue(name, attr: string): seq[float] =
  # The value of `attr` of the instruction of case `name`, built once.
  case name
  of "srect", "srect_fraction", "srect_drift", "srect_negative", "srect_small":
    let r =
      case name
      of "srect": newSmoothRectangle((100.0, 100.0), (150.0, 150.0))
      of "srect_fraction": newSmoothRectangle((30.5, 20.5), (100.4, 40.6))
      of "srect_drift": newSmoothRectangle((127.1, 50.0), (60.3, 30.0))
      of "srect_negative": newSmoothRectangle((300.0, 200.0), (-50.0, 40.0))
      else: newSmoothRectangle((10.0, 10.0), (3.99, 3.99))
    r.build()
    result =
      case attr
      of "points": r.points
      of "antialiasingLinePoints": r.antialiasingLinePoints
      of "pos": pair(r.pos)
      else: pair(r.size)
  of "srrect_test", "srrect_mixed", "srrect_no_segments":
    let r = newSmoothRoundedRectangle()
    case name
    of "srrect_test":
      r.pos = (100.0, 100.0)
      r.size = (150.0, 150.0)
      r.radius = [(10.0, 50.0), (100.0, 50.0), (0.0, 150.0), (200.0, 50.0)]
      r.segments = 60
    of "srrect_mixed":
      r.pos = (540.0, 420.0)
      r.size = (220.0, 140.0)
      r.radius = [(10.0, 10.0), (60.0, 30.0), (0.0, 0.0), (40.0, 40.0)]
    else:
      r.pos = (100.0, 100.0)
      r.size = (150.0, 150.0)
      r.segments = 0
    r.build()
    result =
      case attr
      of "points": r.points
      of "antialiasingLinePoints": r.antialiasingLinePoints
      of "pos": pair(r.pos)
      of "size": pair(r.size)
      else:
        var s: seq[float] = @[]
        for (x, y) in r.radius:
          s.add x
          s.add y
        s
  of "sellipse", "sellipse_arc", "sellipse_6":
    let e =
      case name
      of "sellipse": newSmoothEllipse((100.0, 100.0), (150.0, 150.0))
      of "sellipse_arc":
        newSmoothEllipse((100.0, 100.0), (150.0, 150.0), angleStart = 90, angleEnd = -120)
      else: newSmoothEllipse((440.0, 200.0), (160.0, 120.0), segments = 6)
    e.build()
    result =
      case attr
      of "points": e.points
      of "antialiasingLinePoints": e.antialiasingLinePoints
      of "pos": pair(e.pos)
      else: pair(e.size)
  of "stri", "stri_reverse", "stri_tiny":
    let t =
      case name
      of "stri": newSmoothTriangle([100.0, 100, 200, 100, 150, 200, 500, 500, 400, 400])
      of "stri_reverse": newSmoothTriangle([125.0, 200, 200, 100, 100, 100])
      else: newSmoothTriangle([100.0, 100, 100.5, 100, 100, 100.5])
    t.build()
    result = if attr == "points": t.points else: t.antialiasingLinePoints
  of "squad", "squad_tiny":
    let q =
      if name == "squad": newSmoothQuad([100.0, 100, 100, 200, 200, 200, 200, 100])
      else: newSmoothQuad([200.0, 100, 200, 100.8, 100, 100.8, 100, 100])
    q.build()
    result = if attr == "points": q.points else: q.antialiasingLinePoints
  of "aaline_closed", "aaline_open", "aaline_two":
    let a =
      case name
      of "aaline_closed": newAntiAliasingLine(Instruction(), Points3)
      of "aaline_open": newAntiAliasingLine(Instruction(), Points3, close = false)
      else: newAntiAliasingLine(Instruction(), [100.0, 100, 200, 100])
    result = if attr == "width": @[a.width] else: a.points
  else:
    let l =
      case name
      of "sline_points": newSmoothLine([20.0, 560, 200, 520, 200.05, 520.05, 120, 580], width = 2)
      of "sline_circle":
        let l = newSmoothLine(width = 1.5)
        l.circle = [400.0, 300, 50]
        l
      of "sline_rrect":
        let l = newSmoothLine(width = 2)
        l.roundedRectangle = [20.0, 20, 300, 60, 20]
        l
      of "sline_rrect_thin":
        let l = newSmoothLine()
        l.roundedRectangle = [100.0, 100, 0.5, 1.99, 30, 30, 30, 30, 100]
        l
      of "sline_rectangle":
        let l = newSmoothLine(width = 3)
        l.rectangle = [580.0, 110, 180, 100]
        l
      else: quit "unknown case " & name
    l.build()
    result =
      case attr
      of "points": l.points
      of "overdrawWidth": @[l.overdrawWidth]
      of "circle": l.circle
      of "rectangle": l.rectangle
      of "roundedRectangle": l.roundedRectangle
      else: quit "unknown attribute " & attr

# Kivy's numbers against nimkivy's, as in graphics_points (within 1e-9
# relative where sin, cos and tan differ in the last bits).
block smooth_points:
  var text = ""
  try:
    text = readFile("tests/fixtures/smooth_points.txt")
  except:
    quit "cannot read tests/fixtures/smooth_points.txt"
  var values, inexact = 0
  for line in text.splitLines():
    let fields = line.split(' ')
    if fields.len >= 2:
      let (name, attr) = (fields[0], fields[1])
      let got = smoothValue(name, attr)
      if fields.len == 3 and fields[2] == "none" or fields.len == 2:
        assert got.len == 0, name & " " & attr & " should be empty"
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
  echo "smooth_points: ", values, " values, ", inexact, " not bit-identical (within 1e-9)"

# With multisamples > 0 (Kivy's default 2) the regular shapes get the edges of
# their smooth counterparts (msaaEdge), and keep Kivy's own points, pos, size
# and radius; with 0 they have none.
block msaa_edges:
  proc shapes(): seq[VertexInstruction] =
    let rr = newRoundedRectangle((540.0, 420.0), (220.0, 140.0))
    rr.radius = [(10.0, 10.0), (60.0, 30.0), (0.0, 0.0), (40.0, 40.0)]
    let l = newLine(width = 2)
    l.circle = [80.0, 160, 50]
    result = @[VertexInstruction(newEllipse((20.0, 220.0), (180.0, 120.0))), rr,
      newTriangle([640.0, 200, 780, 200, 700, 360]), l,
      newLine([0.0, 0, 50, 50, 100, 0], width = 3), newRectangle((1.0, 2.0), (30.0, 40.0)),
      newLine([0.0, 0, 50, 50])]
  proc geometry(v: VertexInstruction): seq[float] =
    if v of RoundedRectangle:
      result = RoundedRectangle(v).points
      for (x, y) in RoundedRectangle(v).radius:
        result.add x
        result.add y
    elif v of Rectangle:
      result = Rectangle(v).points & @[Rectangle(v).pos[0], Rectangle(v).pos[1],
        Rectangle(v).size[0], Rectangle(v).size[1]]
    elif v of Triangle: result = Triangle(v).points
    else: result = Line(v).points
  assert Config.graphics.multisamples == 2
  let smooth = shapes()
  Config.graphics.multisamples = 0
  let hard = shapes()
  for k in 0 ..< hard.len:
    hard[k].build()
    assert msaaEdge(hard[k]) == nil
  Config.graphics.multisamples = 2
  for k in 0 ..< smooth.len:
    smooth[k].build()
    assert geometry(smooth[k]) == geometry(hard[k])
    # A Line of width 1 keeps its hard edges.
    assert (msaaEdge(smooth[k]) == nil) == (k == 6)
  # With 2 samples the ramp is 0.5 px: the rounded rectangle is drawn
  # 0.25 px inside, its line (half-width 0.75) on that outline.
  let rr = RoundedRectangle(smooth[1])
  let edge = msaaEdge(rr)
  assert edge != nil and edge of AntiAliasingLine
  let aa = AntiAliasingLine(edge)
  assert aa.points[0] == 540.25 and aa.points[1] == 550.0 and aa.width == 0.75
  assert rr.vertices[0].x == 650 and rr.vertices[1].x == 540.25
  # The open wide line keeps only its caps; a full circle has none.
  assert Line(smooth[4]).indices.len == 2 * 10 * 3 and Line(smooth[3]).indices.len == 0
  let band = msaaEdge(smooth[4])
  assert band != nil and band of SmoothLine and SmoothLine(band).width == 3.5 and
    SmoothLine(band).overdrawWidth == 1
