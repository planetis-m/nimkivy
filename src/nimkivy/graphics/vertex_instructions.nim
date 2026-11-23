## Vertex instructions: Kivy's `kivy/graphics/vertex_instructions.pyx`
## (Triangle, Quad, Rectangle, BorderImage, Ellipse, RoundedRectangle, and the
## smooth ones: AntiAliasingLine, SmoothRectangle, SmoothRoundedRectangle,
## SmoothEllipse, SmoothQuad, SmoothTriangle) and
## `vertex_instructions_line.pxi` (Line, SmoothLine).
##
## Each `build` is Kivy's, line for line: the same vertices, texture
## coordinates and indices, with the same mix of 32-bit fields (`cdef float`)
## and 64-bit arithmetic, so the `points` they expose are Kivy's. Kivy's quirks
## are kept: a zero-sized Ellipse or RoundedRectangle keeps its last
## geometry, round RoundedRectangle corners ignore `texCoords`, and a Line's
## `width` is half of its thickness.
##
## A Line of width exactly 1 is a line strip, which the renderer draws as a
## 1 px polyline; any other width is triangulated by `buildExtended`.
##
## The smooth instructions antialias without multisampling, as Kivy does: a
## smooth shape is built 1 px smaller and an AntiAliasingLine, a band textured
## with a gradient from opaque to transparent, is drawn on its outline; a
## SmoothLine is a band with a transparent border. Out of scope (SCOPE.md):
## Mesh, Point, Bezier, StripMesh, Line dashes, `bezier`, `ellipse`,
## `close_mode` and `force_custom_drawing_method`.

import std/[assertions, math, syncio]
import instructions, texture

type
  Triangle* = ref object of VertexInstruction
    ## A triangle. vertex_instructions.pyx Triangle
    points: seq[float]

  Quad* = ref object of VertexInstruction
    ## A quadrilateral. vertex_instructions.pyx Quad
    points: seq[float]

  Rectangle* = ref object of VertexInstruction
    ## A rectangle. vertex_instructions.pyx Rectangle
    x, y, w, h: float32
    points: seq[float]

  BorderAutoScale* = enum
    ## How BorderImage scales its borders (`auto_scale`).
    asOff = "off", asBoth = "both", asXOnly = "x_only", asYOnly = "y_only",
    asYFullXLower = "y_full_x_lower", asXFullYLower = "x_full_y_lower",
    asBothLower = "both_lower"

  BorderImage* = ref object of Rectangle
    ## A texture drawn as nine slices: fixed borders, stretched middle.
    ## vertex_instructions.pyx BorderImage
    border: seq[float]           # bottom, right, top, left
    autoScale: BorderAutoScale
    displayBorder: seq[float]

  Ellipse* = ref object of Rectangle
    ## An ellipse, or a slice of one, inside pos and size.
    ## vertex_instructions.pyx Ellipse
    segments: int
    angleStart, angleEnd: float32

  RoundedRectangle* = ref object of Rectangle
    ## A rectangle with elliptic corners. vertex_instructions.pyx
    ## RoundedRectangle
    segments: array[4, int]                 # per corner
    radius: array[4, (float, float)]        # top-left, top-right, bottom-right, bottom-left

  LineCap* = enum
    ## The ends of a wide line.
    capNone = "none", capSquare = "square", capRound = "round"

  LineJoint* = enum
    ## The joints of a wide line.
    jointNone = "none", jointRound = "round", jointBevel = "bevel", jointMiter = "miter"

  LineMode = enum
    # Where the points come from (Kivy's LINE_MODE_*).
    lmPoints, lmCircle, lmRectangle, lmRoundedRectangle

  Line* = ref object of VertexInstruction
    ## A polyline. vertex_instructions_line.pxi Line
    points: seq[float]
    width: float32
    cap: LineCap
    joint: LineJoint
    capPrecision, jointPrecision: int
    close: bool
    lineMode: LineMode
    modeArgs: seq[float]
    circle, rectangle, roundedRectangle: seq[float]   # the normalised args; empty is None
    bxmin, bymin, bxmax, bymax: float

  SmoothLine* = ref object of Line
    ## A line with antialiased borders, drawn as a band whose border fades
    ## out over `overdrawWidth` pixels. `cap` and `joint` are ignored.
    ## vertex_instructions_line.pxi SmoothLine
    owidth: float32

  AntiAliasingLine* = ref object of VertexInstruction
    ## The band drawn on the outline of a smooth shape: 2.5 px to each side,
    ## textured with Kivy's gradient (transparent, opaque, transparent). Its
    ## shape adds it to the canvas, never by itself. With a colour whose
    ## alpha is below 1 Kivy draws it only outside `stencilMask`, the shape,
    ## through a stencil; the renderer does not draw it then (PORTING.md,
    ## Gaps). vertex_instructions.pyx AntiAliasingLine (internal in Kivy)
    points: seq[float]
    width: float32
    close: bool
    stencilMask: Instruction

  SmoothRectangle* = ref object of Rectangle
    ## A Rectangle with antialiased edges. vertex_instructions.pyx
    ## SmoothRectangle
    antialiasingLine: nil AntiAliasingLine   # set by the constructor

  SmoothEllipse* = ref object of Ellipse
    ## An Ellipse with antialiased edges. vertex_instructions.pyx
    ## SmoothEllipse
    antialiasingLine: nil AntiAliasingLine

  SmoothRoundedRectangle* = ref object of RoundedRectangle
    ## A RoundedRectangle with antialiased edges. vertex_instructions.pyx
    ## SmoothRoundedRectangle
    antialiasingLine: nil AntiAliasingLine

  SmoothTriangle* = ref object of Triangle
    ## A Triangle with antialiased edges. vertex_instructions.pyx
    ## SmoothTriangle
    antialiasingLine: nil AntiAliasingLine

  SmoothQuad* = ref object of Quad
    ## A Quad with antialiased edges. vertex_instructions.pyx SmoothQuad
    antialiasingLine: nil AntiAliasingLine

  GradientTextures = ref object
    # Kivy's Cache 'kv.graphics.texture': the two gradients, made on first use.
    antialiasingLine, smoothLine: nil Texture

const
  AntiAliasingLineGradient* = [0xff'u8, 0xff, 0xff, 0x00, 0xff, 0xff, 0xff, 0xff,
    0xff, 0xff, 0xff, 0x00]
    ## The 3 x 1 RGBA texture of AntiAliasingLine (`_texture_reload_observer`).
  SmoothLineGradient* = [0xff'u8, 0xff, 0xff, 0x00, 0xff, 0xff, 0xff, 0xff,
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x00]
    ## The 4 x 1 RGBA texture of SmoothLine (`_smooth_reload_observer`).
  Deg2Rad = 0.017453292519943295
  PI2 = 1.5707963267948966              # common.pxi DEF PI2
  Pi32 = 3.1415926535'f32               # vertex_instructions_line.pxi `cdef float PI`

let gradients = GradientTextures(antialiasingLine: nil, smoothLine: nil)

proc warn(category, msg: string) =
  # Kivy's Logger.warning, on stderr in Kivy's layout.
  stderr.writeLine "[WARNING] [" & category & "] " & msg

# ---------------------------------------------------------------- Triangle

method build*(t: Triangle) =
  ## vertex_instructions.pyx Triangle.build
  let vc = t.points
  let tc = t.texCoords
  t.vertices = @[
    Vertex(x: float32(vc[0]), y: float32(vc[1]), s0: tc[0], t0: tc[1]),
    Vertex(x: float32(vc[2]), y: float32(vc[3]), s0: tc[2], t0: tc[3]),
    Vertex(x: float32(vc[4]), y: float32(vc[5]), s0: tc[4], t0: tc[5])]
  t.indices = @[0'i32, 1, 2]

proc newTriangle*(points: openArray[float] = [0.0, 0.0, 100.0, 0.0, 50.0, 100.0]): Triangle =
  ## `Triangle(points=...)`: x1, y1, x2, y2, x3, y3.
  assert points.len >= 6
  result = Triangle(textureBinding: newBindTexture(), points: @points)
  result.initVertexInstruction(vmTriangles)
  result.flagUpdate()

proc points*(t: Triangle): seq[float] {.inline.} =
  ## The six coordinates.
  t.points

proc `points=`*(t: Triangle; points: openArray[float]) =
  ## Sets the six coordinates.
  assert points.len >= 6
  t.points = @points
  t.flagUpdate()

# ---------------------------------------------------------------- Quad

method build*(q: Quad) =
  ## vertex_instructions.pyx Quad.build
  let vc = q.points
  let tc = q.texCoords
  q.vertices = @[
    Vertex(x: float32(vc[0]), y: float32(vc[1]), s0: tc[0], t0: tc[1]),
    Vertex(x: float32(vc[2]), y: float32(vc[3]), s0: tc[2], t0: tc[3]),
    Vertex(x: float32(vc[4]), y: float32(vc[5]), s0: tc[4], t0: tc[5]),
    Vertex(x: float32(vc[6]), y: float32(vc[7]), s0: tc[6], t0: tc[7])]
  q.indices = @[0'i32, 1, 2, 2, 3, 0]

proc newQuad*(points: openArray[float] = [0.0, 50.0, 50.0, 0.0, 100.0, 50.0, 50.0, 100.0]): Quad =
  ## `Quad(points=...)`: x1, y1, x2, y2, x3, y3, x4, y4.
  assert points.len == 8, "Quad: invalid number of points"
  result = Quad(textureBinding: newBindTexture(), points: @points)
  result.initVertexInstruction(vmTriangles)
  result.flagUpdate()

proc points*(q: Quad): seq[float] {.inline.} =
  ## The eight coordinates.
  q.points

proc `points=`*(q: Quad; points: openArray[float]) =
  ## Sets the eight coordinates.
  assert points.len == 8, "Quad: invalid number of points"
  q.points = @points
  q.flagUpdate()

# ---------------------------------------------------------------- Rectangle

method build*(r: Rectangle) =
  ## vertex_instructions.pyx Rectangle.build
  let tc = r.texCoords
  let x = r.x
  let y = r.y
  let w = r.w
  let h = r.h
  r.vertices = @[
    Vertex(x: x, y: y, s0: tc[0], t0: tc[1]),
    Vertex(x: x + w, y: y, s0: tc[2], t0: tc[3]),
    Vertex(x: x + w, y: y + h, s0: tc[4], t0: tc[5]),
    Vertex(x: x, y: y + h, s0: tc[6], t0: tc[7])]
  r.indices = @[0'i32, 1, 2, 2, 3, 0]
  # Sums of 32-bit floats, as Kivy's `cdef float` locals.
  r.points = @[float(x), float(y), float(x + w), float(y), float(x + w), float(y + h),
    float(x), float(y + h)]

proc initRectangle(r: Rectangle; pos, size: (float, float); mode: VertexMode) =
  # vertex_instructions.pyx Rectangle.__init__
  r.initVertexInstruction(mode)
  r.x = float32(pos[0])
  r.y = float32(pos[1])
  r.w = float32(size[0])
  r.h = float32(size[1])
  r.points = @[]
  r.flagUpdate()

proc newRectangle*(pos = (0.0, 0.0); size = (100.0, 100.0)): Rectangle =
  ## `Rectangle(pos=..., size=...)`.
  result = Rectangle(textureBinding: newBindTexture())
  result.initRectangle(pos, size, vmTriangles)

proc pos*(r: Rectangle): (float, float) {.inline.} =
  ## The bottom-left corner.
  (float(r.x), float(r.y))

proc `pos=`*(r: Rectangle; pos: (float, float)) =
  ## Moves the rectangle; nothing happens if it is already there.
  let x = float32(pos[0])
  let y = float32(pos[1])
  if r.x != x or r.y != y:
    r.x = x
    r.y = y
    r.flagUpdate()

proc size*(r: Rectangle): (float, float) {.inline.} =
  ## The size.
  (float(r.w), float(r.h))

proc `size=`*(r: Rectangle; size: (float, float)) =
  ## Resizes the rectangle; nothing happens if the size is the same.
  let w = float32(size[0])
  let h = float32(size[1])
  if r.w != w or r.h != h:
    r.w = w
    r.h = h
    r.flagUpdate()

proc points*(r: Rectangle): seq[float] {.inline.} =
  ## The points of the last build: four corners for a Rectangle, the
  ## outline for an Ellipse, the outline (pairs flattened) for a
  ## RoundedRectangle.
  r.points

# ---------------------------------------------------------------- BorderImage

method build*(b: BorderImage) =
  ## vertex_instructions.pyx BorderImage.build
  let x = b.x
  let y = b.y
  let w = b.w
  let h = b.h
  let tc = b.texCoords
  let tc0 = tc[0]
  let tc1 = tc[1]
  let tc2 = tc[2]
  let tc7 = tc[7]
  # Kivy's default texture (nil here) is one pixel.
  var tw = 1'f32
  var th = 1'f32
  let tex = b.texture
  if tex != nil:
    tw = float32(tex.width)
    th = float32(tex.height)
  let tcw = tc2 - tc0
  let tch = tc7 - tc1
  let b0 = float32(b.border[0])
  let b1 = float32(b.border[1])
  let b2 = float32(b.border[2])
  let b3 = float32(b.border[3])
  let tb = [b0 / th * tch, b1 / tw * tcw, b2 / th * tch, b3 / tw * tcw]
  var sb0, sb1, sb2, sb3 = 0'f32
  case b.autoScale
  of asOff:
    (sb0, sb1, sb2, sb3) = (b0, b1, b2, b3)
  of asBoth:
    (sb0, sb1, sb2, sb3) = ((b0 / th) * h, (b1 / tw) * w, (b2 / th) * h, (b3 / tw) * w)
  of asXOnly:
    (sb0, sb1, sb2, sb3) = (b0, (b1 / tw) * w, b2, (b3 / tw) * w)
  of asYOnly:
    (sb0, sb1, sb2, sb3) = ((b0 / th) * h, b1, (b2 / th) * h, b3)
  of asYFullXLower:
    (sb0, sb1, sb2, sb3) = ((b0 / th) * h, min((b1 / tw) * w, b1), (b2 / th) * h,
      min((b3 / tw) * w, b3))
  of asXFullYLower:
    (sb0, sb1, sb2, sb3) = (min((b0 / th) * h, b0), (b1 / tw) * w, min((b2 / th) * h, b2),
      (b3 / tw) * w)
  of asBothLower:
    (sb0, sb1, sb2, sb3) = (min((b0 / th) * h, b0), min((b1 / tw) * w, b1),
      min((b2 / th) * h, b2), min((b3 / tw) * w, b3))
  let db = b.displayBorder
  if db.len >= 4:
    (sb0, sb1, sb2, sb3) = (float32(db[0]), float32(db[1]), float32(db[2]), float32(db[3]))
  let hs = [x, x + sb3, x + w - sb1, x + w]
  let vs = [y, y + sb0, y + h - sb2, y + h]
  let ths = [tc0, tc0 + tb[3], tc0 + tcw - tb[1], tc0 + tcw]
  let tvs = [tc1, tc1 + tb[0], tc1 + tch - tb[2], tc1 + tch]
  # v9---v8------v7----v6
  # |        b2        |
  # v10  v15------v14   v5
  # |    |        |    |
  # |-b4-|        |-b1-|
  # |    |        |    |
  # v11  v12------v13   v4
  # |        b0        |
  # v0---v1------v2----v3
  let grid = [(0, 0), (1, 0), (2, 0), (3, 0), (3, 1), (3, 2), (3, 3), (2, 3), (1, 3), (0, 3),
    (0, 2), (0, 1), (1, 1), (2, 1), (2, 2), (1, 2)]
  b.vertices = @[]
  for (i, j) in grid:
    b.vertices.add Vertex(x: hs[i], y: vs[j], s0: ths[i], t0: tvs[j])
  b.indices = @[
    0'i32, 1, 12, 12, 11, 0,     # bottom left
    1, 2, 13, 13, 12, 1,         # bottom middle
    2, 3, 4, 4, 13, 2,           # bottom right
    13, 4, 5, 5, 14, 13,         # center right
    14, 5, 6, 6, 7, 14,          # top right
    15, 14, 7, 7, 8, 15,         # top middle
    10, 15, 8, 8, 9, 10,         # top left
    11, 12, 15, 15, 10, 11,      # center left
    12, 13, 14, 14, 15, 12]      # center middle

proc newBorderImage*(pos = (0.0, 0.0); size = (100.0, 100.0);
    border: openArray[float] = [10.0, 10.0, 10.0, 10.0]; autoScale = asOff): BorderImage =
  ## `BorderImage(pos=..., size=..., border=...)`; `border` is bottom,
  ## right, top, left in pixels.
  assert border.len == 4
  result = BorderImage(textureBinding: newBindTexture(), border: @border, autoScale: autoScale, displayBorder: @[])
  result.initRectangle(pos, size, vmTriangles)

proc border*(b: BorderImage): seq[float] {.inline.} =
  ## Bottom, right, top and left borders in texture pixels.
  b.border

proc `border=`*(b: BorderImage; border: openArray[float]) =
  ## Sets the borders.
  assert border.len == 4
  b.border = @border
  b.flagUpdate()

proc autoScale*(b: BorderImage): BorderAutoScale {.inline.} =
  ## How the borders scale with the size.
  b.autoScale

proc `autoScale=`*(b: BorderImage; v: BorderAutoScale) =
  ## Sets how the borders scale.
  b.autoScale = v
  b.flagUpdate()

proc displayBorder*(b: BorderImage): seq[float] {.inline.} =
  ## The borders as drawn, overriding `border` when not empty.
  b.displayBorder

proc `displayBorder=`*(b: BorderImage; v: openArray[float]) =
  ## Sets the drawn borders.
  b.displayBorder = @v
  b.flagUpdate()

# ---------------------------------------------------------------- Ellipse

method build*(e: Ellipse) =
  ## vertex_instructions.pyx Ellipse.build
  let tc = e.texCoords
  e.points = @[]
  # Kivy returns before set_data: the last geometry stays.
  if e.w == 0 or e.h == 0:
    return
  var segments = e.segments
  if segments == 0 or segments < 3:
    if segments != 0:
      warn("Ellipse     ",
        "A minimum of 3 segments is required. The default value will be used instead.")
    segments = max(1, int(abs(e.angleEnd - e.angleStart) / 2'f32))
  let tx = float(tc[0])
  let ty = float(tc[1])
  let tw = float(tc[4]) - tx
  let th = float(tc[5]) - ty
  let ex = float(e.x)
  let ey = float(e.y)
  let ew = float(e.w)
  let eh = float(e.h)
  let rx = 0.5 * ew
  let ry = 0.5 * eh
  let angleStart = float(e.angleStart) * Deg2Rad
  let angleEnd = float(e.angleEnd) * Deg2Rad
  let angleRange = -1.0 * (angleEnd - angleStart) / float(segments)
  # The start vertex in the middle.
  var x = ex + rx
  var y = ey + ry
  var ttx = ((x - ex) / ew) * tw + tx
  var tty = ((y - ey) / eh) * th + ty
  e.vertices = @[Vertex(x: float32(ex + rx), y: float32(ey + ry), s0: float32(ttx),
    t0: float32(tty))]
  e.indices = @[0'i32]
  # A circle of radius 0.5 about (0.5, 0.5), stretched to the ellipse, by
  # rotating one point (http://slabode.exofire.net/circle_draw.shtml).
  let tangentialFactor = tan(angleRange)
  let radialFactor = cos(angleRange)
  const cx = 0.5
  const cy = 0.5
  const r = 0.5
  x = r * sin(angleStart)
  y = r * cos(angleStart)
  for i in 1 .. segments + 1:
    ttx = (cx + x) * tw + tx
    tty = (cy + y) * th + ty
    let realX = ex + (cx + x) * ew
    let realY = ey + (cy + y) * eh
    e.vertices.add Vertex(x: float32(realX), y: float32(realY), s0: float32(ttx),
      t0: float32(tty))
    e.indices.add int32(i)
    let fx = -y
    let fy = x
    x += fx * tangentialFactor
    y += fy * tangentialFactor
    x *= radialFactor
    y *= radialFactor
    e.points.add realX
    e.points.add realY

proc newEllipse*(pos = (0.0, 0.0); size = (100.0, 100.0); angleStart = 0.0;
    angleEnd = 360.0; segments = 0): Ellipse =
  ## `Ellipse(pos=..., size=..., angle_start=..., angle_end=...,
  ## segments=...)`. Angles are in degrees; `segments` 0 (or below 3)
  ## means one per two degrees. As in Kivy, an `angleEnd` of 0 means 360.
  result = Ellipse(textureBinding: newBindTexture(), segments: segments, angleStart: float32(angleStart),
    angleEnd: float32(if angleEnd == 0: 360.0 else: angleEnd))
  result.initRectangle(pos, size, vmTriangleFan)

proc segments*(e: Ellipse): int {.inline.} =
  ## The number of segments (0: from the angle range).
  e.segments

proc `segments=`*(e: Ellipse; v: int) =
  ## Sets the number of segments.
  e.segments = v
  e.flagUpdate()

proc angleStart*(e: Ellipse): float {.inline.} =
  ## The start angle in degrees, clockwise from the top.
  float(e.angleStart)

proc `angleStart=`*(e: Ellipse; v: float) =
  ## Sets the start angle.
  e.angleStart = float32(v)
  e.flagUpdate()

proc angleEnd*(e: Ellipse): float {.inline.} =
  ## The end angle in degrees.
  float(e.angleEnd)

proc `angleEnd=`*(e: Ellipse; v: float) =
  ## Sets the end angle.
  e.angleEnd = float32(v)
  e.flagUpdate()

# ---------------------------------------------------------------- RoundedRectangle

proc drawArc(cx, cy, rx, ry, angleStart, angleEnd: float; segments: int): seq[float] =
  # vertex_instructions.pyx RoundedRectangle.draw_arc: `segments` points
  # (flattened pairs) from angleStart towards angleEnd, without the end.
  let a0 = angleStart * Deg2Rad
  let a1 = angleEnd * Deg2Rad
  let theta = (a1 - a0) / float(segments)
  let tangentialFactor = tan(theta)
  let radialFactor = cos(theta)
  var x = cos(a0)
  var y = sin(a0)
  result = @[]
  for i in 0 ..< segments:
    result.add cx + x * rx
    result.add cy + y * ry
    let fx = -y
    let fy = x
    x += fx * tangentialFactor
    y += fy * tangentialFactor
    x *= radialFactor
    y *= radialFactor

method build*(r: RoundedRectangle) =
  ## vertex_instructions.pyx RoundedRectangle.build
  let tc = r.texCoords
  r.points = @[]
  # Kivy returns before set_data: the last geometry stays.
  if r.w == 0 or r.h == 0:
    return
  # One vertex for a sharp corner, segments + 1 for a round one, and the
  # middle; the radii here are the unclamped ones, as in Kivy.
  var count = 1
  for corner in 0 ..< 4:
    let (rx, ry) = r.radius[corner]
    count += 1 + (if rx * ry != 0: r.segments[corner] else: 0)
  let x0 = r.x
  let y0 = r.y
  let w = r.w
  let h = r.h
  # `self.w / 2` divides a C float: a 32-bit result kept as a double.
  let halfW = float(w / 2'f32)
  let halfH = float(h / 2'f32)
  var xradius = default(array[4, float])
  var yradius = default(array[4, float])
  for corner in 0 ..< 4:
    xradius[corner] = min(r.radius[corner][0], halfW)
    yradius[corner] = min(r.radius[corner][1], halfH)
  let tx = float(tc[0])
  let ty = float(tc[1])
  let tw = float(tc[4]) - tx
  let th = float(tc[5]) - ty
  var vertices = newSeq[Vertex](count)
  var indices = newSeq[int32](count + 1)
  vertices[0] = Vertex(x: float32(float(x0) + halfW), y: float32(float(y0) + halfH),
    s0: float32(tx + tw / 2), t0: float32(ty + th / 2))
  indices[0] = 0
  var index = 1
  const coefficients = [(0, 1), (1, 1), (1, 0), (0, 0)]
  for corner in 0 ..< 4:
    # The corner's arc runs clockwise, from `angle` to `angle - 90`.
    let angle = float(180 - 90 * corner)
    let (dw, dh) = coefficients[corner]
    let rx = xradius[corner]
    let ry = yradius[corner]
    # The ellipse centre; `y + h` and `x + w` add two C floats first.
    let (px, py) =
      case corner
      of 0: (float(x0) + rx, float(y0 + h) - ry)
      of 1: (float(x0 + w) - rx, float(y0 + h) - ry)
      of 2: (float(x0 + w) - rx, float(y0) + ry)
      else: (float(x0) + rx, float(y0) + ry)
    let segments = r.segments[corner]
    if rx == 0 or ry == 0 or segments == 0:
      # A sharp corner.
      let vx = x0 + w * float32(dw)
      let vy = y0 + h * float32(dh)
      vertices[index] = Vertex(x: vx, y: vy, s0: float32(tx + tw * float(dw)),
        t0: float32(ty + th * float(dh)))
      r.points.add float(vx)
      r.points.add float(vy)
    else:
      let pts = drawArc(px, py, rx, ry, angle, angle - 90, segments)
      for k in 0 ..< segments:
        let x = pts[2 * k]
        let y = pts[2 * k + 1]
        # Kivy maps the round corners through the box, not `texCoords`,
        # and flips them vertically.
        vertices[index + k] = Vertex(x: float32(x), y: float32(y),
          s0: float32((x - float(x0)) / float(w)), t0: float32(1 - (y - float(y0)) / float(h)))
        indices[index + k] = int32(index + k)
      index += segments
      # The vertex that closes the arc (see Kivy's comment on A to F).
      let a = float(ord(dw != dh))
      let bb = float32(ord(dw == dh))
      let c = float32(dw * dh)
      let f = float32(ord(dh > dw))
      let x = px * a + float(x0 * bb) + float(w * c)
      let y = py * float(ord(dw == dh)) + float(y0 * float32(ord(dw != dh))) + float(h * f)
      vertices[index] = Vertex(x: float32(x), y: float32(y),
        s0: float32((x - float(x0)) / float(w)), t0: float32(1 - (y - float(y0)) / float(h)))
      for v in pts:
        r.points.add v
      r.points.add x
      r.points.add y
    indices[index] = int32(index)
    inc index
  # The fan closes on the first corner vertex.
  indices[count] = indices[1]
  r.vertices = vertices
  r.indices = indices

proc newRoundedRectangle*(pos = (0.0, 0.0); size = (100.0, 100.0)): RoundedRectangle =
  ## `RoundedRectangle(pos=..., size=...)` with Kivy's defaults: radius 10 at
  ## every corner and 10 segments per corner. Set `radius` and `segments`
  ## after.
  result = RoundedRectangle(textureBinding: newBindTexture(), segments: [10, 10, 10, 10],
    radius: [(10.0, 10.0), (10.0, 10.0), (10.0, 10.0), (10.0, 10.0)])
  result.initRectangle(pos, size, vmTriangleFan)

proc radius*(r: RoundedRectangle): array[4, (float, float)] {.inline.} =
  ## The (x, y) radii of the top-left, top-right, bottom-right and
  ## bottom-left corners, as set (the build clamps them to half the size).
  r.radius

proc `radius=`*(r: RoundedRectangle; radius: openArray[(float, float)]) =
  ## Sets the radii from (x, y) pairs: one pair for every corner, or four
  ## (more are ignored; two or three use the first for every corner).
  ## RoundedRectangle._check_radius
  assert radius.len > 0, "Invalid radius value, must be list of tuples/numerics"
  for corner in 0 ..< 4:
    r.radius[corner] = if radius.len < 4: radius[0] else: radius[corner]
  r.flagUpdate()

proc `radius=`*(r: RoundedRectangle; radius: openArray[float]) =
  ## Sets the radii from numbers, each one for both axes.
  var pairs: seq[(float, float)] = @[]
  for v in radius:
    pairs.add (v, v)
  `radius=`(r, pairs)

proc segments*(r: RoundedRectangle): array[4, int] {.inline.} =
  ## The number of segments of each corner.
  r.segments

proc `segments=`*(r: RoundedRectangle; v: int) =
  ## Sets the number of segments of every corner.
  r.segments = [v, v, v, v]
  r.flagUpdate()

proc `segments=`*(r: RoundedRectangle; v: openArray[int]) =
  ## Sets the segments per corner: four values, or the first for all.
  ## RoundedRectangle._check_segments
  assert v.len > 0, "Invalid segments value, must be list of integers"
  for corner in 0 ..< 4:
    r.segments[corner] = if v.len < 4: v[0] else: v[corner]
  r.flagUpdate()

# ---------------------------------------------------------------- Line

proc lineIntersection(x1, y1, x2, y2, x3, y3, x4, y4: float; px, py: var float): bool =
  # vertex_instructions_line.pxi line_intersection
  let u = x1 * y2 - y1 * x2
  let v = x3 * y4 - y3 * x4
  let denom = (x1 - x2) * (y3 - y4) - (y1 - y2) * (x3 - x4)
  if denom == 0:
    return false
  px = (u * (x3 - x4) - (x1 - x2) * v) / denom
  py = (u * (y3 - y4) - (y1 - y2) * v) / denom
  result = true

proc prebuildCircle(l: Line) =
  # vertex_instructions_line.pxi Line.prebuild_circle
  let args = l.modeArgs
  let x = args[0]
  let y = args[1]
  let r = args[2]
  var angleStart = 0.0
  var angleEnd = 360.0
  var segments = 0
  if args.len >= 5:
    angleStart = args[3]
    angleEnd = args[4]
  if args.len == 6:
    segments = int(args[5]) + 1
  let angleDir = if angleEnd > angleStart: 1 else: -1
  if segments == 0:
    segments = int(abs(angleEnd - angleStart) / 2) + 3
  l.circle = @[x, y, r, angleStart, angleEnd, float(segments)]
  l.rectangle = @[]
  l.roundedRectangle = @[]
  let segmentPoints = segments * 2
  let a0 = angleStart * Deg2Rad
  let a1 = angleEnd * Deg2Rad
  let angleRange = abs(a1 - a0) / float(segmentPoints - 2)
  l.points = newSeq[float](segmentPoints)
  for i in countup(0, segmentPoints - 1, 2):
    let angle = a0 + float(angleDir * i) * angleRange
    l.points[i] = x + r * sin(angle)
    l.points[i + 1] = y + r * cos(angle)

proc prebuildRectangle(l: Line) =
  # vertex_instructions_line.pxi Line.prebuild_rectangle
  let args = l.modeArgs
  let (x, y, width, height) = (args[0], args[1], args[2], args[3])
  l.rectangle = @[x, y, width, height]
  l.roundedRectangle = @[]
  l.circle = @[]
  l.points = @[x, y, x + width, y, x + width, y + height, x, y + height]
  l.close = true

proc prebuildRoundedRectangle(l: Line) =
  # vertex_instructions_line.pxi Line.prebuild_rounded_rectangle, with its
  # `cdef float` locals as float32.
  let args = l.modeArgs
  l.points = @[]
  let x = float32(args[0])
  let y = float32(args[1])
  let w = float32(args[2])
  let h = float32(args[3])
  # A zero size draws nothing and leaves `rounded_rectangle` as it was; so
  # does a SmoothLine under 2 px, which Kivy cannot draw well.
  if w <= 0 or h <= 0 or l of SmoothLine and (w < 2 or h < 2):
    return
  var resolution = 45.0
  var c1, c2, c3, c4 = 0'f32
  case args.len
  of 5:
    c1 = float32(args[4])
    (c2, c3, c4) = (c1, c1, c1)
  of 6:
    c1 = float32(args[4])
    (c2, c3, c4) = (c1, c1, c1)
    resolution = args[5]
  of 8:
    (c1, c2, c3, c4) = (float32(args[4]), float32(args[5]), float32(args[6]), float32(args[7]))
  else:
    (c1, c2, c3, c4) = (float32(args[4]), float32(args[5]), float32(args[6]), float32(args[7]))
    resolution = args[8]
  if resolution <= 4:
    resolution = 4
  # The minimum radius is 1 px, which avoids rendering issues.
  c1 = max(c1, 1'f32)
  c2 = max(c2, 1'f32)
  c3 = max(c3, 1'f32)
  c4 = max(c4, 1'f32)
  let minDimension = min(w, h)
  let halfMinDimension = minDimension / 2'f32
  # A corner larger than half the side shrinks its neighbours to half, and
  # itself to what they leave.
  if c1 > halfMinDimension:
    c2 = min(c2, halfMinDimension)
    c4 = min(c4, halfMinDimension)
    c1 = min(c1, min(minDimension - c2, minDimension - c4))
  if c2 > halfMinDimension:
    c1 = min(c1, halfMinDimension)
    c3 = min(c3, halfMinDimension)
    c2 = min(c2, min(minDimension - c1, minDimension - c3))
  if c3 > halfMinDimension:
    c2 = min(c2, halfMinDimension)
    c4 = min(c4, halfMinDimension)
    c3 = min(c3, min(minDimension - c2, minDimension - c4))
  if c4 > halfMinDimension:
    c3 = min(c3, halfMinDimension)
    c1 = min(c1, halfMinDimension)
    c4 = min(c4, min(minDimension - c3, minDimension - c1))
  l.roundedRectangle = @[float(x), float(y), float(w), float(h), float(c1), float(c2),
    float(c3), float(c4), resolution]
  l.rectangle = @[]
  l.circle = @[]
  # Kivy divides `PI / resolution` as a double and stores a float.
  let step = float32(float(Pi32) / resolution)
  let maxA = float32(float(Pi32) / 2.0 - float(step))
  # top-left
  var a = 0'f32
  var px = x + c1
  var py = y + h - c1
  while a < maxA:
    a += step
    l.points.add float(px) - cos(float(a)) * float(c1)
    l.points.add float(py) + sin(float(a)) * float(c1)
  # top-right
  a = 0'f32
  px = x + w - c2
  py = y + h - c2
  while a < maxA:
    a += step
    l.points.add float(px) + sin(float(a)) * float(c2)
    l.points.add float(py) + cos(float(a)) * float(c2)
  # bottom-right
  a = 0'f32
  px = x + w - c3
  py = y + c3
  while a < maxA:
    a += step
    l.points.add float(px) + cos(float(a)) * float(c3)
    l.points.add float(py) - sin(float(a)) * float(c3)
  # bottom-left
  a = 0'f32
  px = x + c4
  py = y + c4
  while a < maxA:
    a += step
    l.points.add float(px) - sin(float(a)) * float(c4)
    l.points.add float(py) - cos(float(a)) * float(c4)
  l.close = true

proc buildLegacy(l: Line) =
  # vertex_instructions_line.pxi Line.build_legacy, without dashes: a line
  # strip through the points.
  var p = l.points
  var count = p.len div 2
  if count < 2:
    l.vertices = @[]
    l.indices = @[]
    return
  if l.close:
    p.add p[0]
    p.add p[1]
    inc count
  l.mode = vmLineStrip
  if l.texture != nil:
    l.texture = nil
  l.vertices = newSeq[Vertex](count)
  l.indices = newSeq[int32](count)
  for i in 0 ..< count:
    l.vertices[i] = Vertex(x: float32(p[i * 2]), y: float32(p[i * 2 + 1]), s0: 0, t0: 0)
    l.indices[i] = int32(i)

proc vtx(x, y: float; s, t: float32): Vertex {.inline.} =
  # A vertex of a wide line: the coordinates stored as C floats.
  Vertex(x: float32(x), y: float32(y), s0: s, t0: t)

proc buildExtended(l: Line) =
  # vertex_instructions_line.pxi Line.build_extended: each segment is a quad
  # of half-width `width` on both sides, plus joints and caps as triangles.
  l.texture = nil
  l.bxmin = 999999999
  l.bymin = 999999999
  l.bxmax = -999999999
  l.bymax = -999999999
  var p = l.points
  var count = p.len div 2
  if count < 2:
    l.vertices = @[]
    l.indices = @[]
    return
  var cap = l.cap
  if l.close and count > 2:
    p.add p[0]
    p.add p[1]
    p.add p[2]
    p.add p[3]
    count += 2
    cap = capNone
  l.mode = vmTriangles
  let joint = l.joint
  let jointPrecision = l.jointPrecision
  let capPrecision = l.capPrecision
  var verticesCount = (count - 1) * 4
  var indicesCount = (count - 1) * 6
  case joint
  of jointBevel:
    indicesCount += (count - 2) * 3
    verticesCount += count - 2
  of jointRound:
    indicesCount += (jointPrecision * 3) * (count - 2)
    verticesCount += jointPrecision * (count - 2)
  of jointMiter:
    indicesCount += (count - 2) * 6
    verticesCount += (count - 2) * 2
  of jointNone:
    discard
  case cap
  of capSquare:
    indicesCount += 12
    verticesCount += 4
  of capRound:
    indicesCount += (capPrecision * 3) * 2
    verticesCount += capPrecision * 2
  of capNone:
    discard
  var vertices = newSeq[Vertex](verticesCount)
  var indices = newSeq[int32](indicesCount)
  let w = float(l.width)
  var ax, ay, bx, by, cx, cy, angle, a1, a2 = 0.0
  var x1, y1, x2, y2, x3, y3, x4, y4 = 0.0
  var sx1, sy1, sx4, sy4, sangle = 0.0
  var pcx, pcy, px1, py1, px2, py2, px3, py3, px4, py4, pangle, pangle2 = 0.0
  var ix, iy = 0.0
  var iv, ii, siv, piv, piv2, skip = 0
  var cos1, cos2, sin1, sin2 = 0.0

  for i in 0 ..< count - 1:
    ax = p[i * 2]
    ay = p[i * 2 + 1]
    bx = p[i * 2 + 2]
    by = p[i * 2 + 3]
    if ax == bx and ay == by:
      inc skip
    else:
      if i - skip > 0 and joint != jointNone:
        pcx = cx
        pcy = cy
        px1 = x1
        px2 = x2
        px3 = x3
        px4 = x4
        py1 = y1
        py2 = y2
        py3 = y3
        py4 = y4
      piv2 = piv
      piv = iv
      pangle2 = pangle
      pangle = angle
      # The orientation of the segment, between pi and -pi.
      cx = bx - ax
      cy = by - ay
      angle = arctan2(cy, cx)
      a1 = angle - PI2
      a2 = angle + PI2
      # The corners of the segment's quad.
      cos1 = cos(a1) * w
      sin1 = sin(a1) * w
      cos2 = cos(a2) * w
      sin2 = sin(a2) * w
      x1 = ax + cos1
      y1 = ay + sin1
      x4 = ax + cos2
      y4 = ay + sin2
      x2 = bx + cos1
      y2 = by + sin1
      x3 = bx + cos2
      y3 = by + sin2
      if i - skip == 0:
        sx1 = x1
        sy1 = y1
        sx4 = x4
        sy4 = y4
        sangle = angle
      for k, d in [0, 1, 2, 0, 2, 3]:
        indices[ii + k] = int32(iv + d)
      ii += 6
      vertices[iv] = vtx(x1, y1, 0, 0)
      vertices[iv + 1] = vtx(x2, y2, 1, 0)
      vertices[iv + 2] = vtx(x3, y3, 1, 1)
      vertices[iv + 3] = vtx(x4, y4, 0, 1)
      iv += 4
      # The joint with the previous segment.
      if i - skip != 0 and joint != jointNone:
        # The angle between the previous segment and this one.
        let jangle = arctan2(cx * pcy - cy * pcx, cx * pcx + cy * pcy)
        if jangle == 0:
          # No joint: the counts shrink, as in Kivy.
          case joint
          of jointRound:
            verticesCount -= jointPrecision
            indicesCount -= jointPrecision * 3
          of jointBevel:
            verticesCount -= 1
            indicesCount -= 3
          of jointMiter:
            verticesCount -= 2
            indicesCount -= 6
          of jointNone:
            discard
        else:
          case joint
          of jointBevel:
            vertices[iv] = vtx(ax, ay, 0, 0)
            if jangle < 0:
              indices[ii] = int32(piv2 + 1)
              indices[ii + 1] = int32(piv)
              indices[ii + 2] = int32(iv)
            else:
              indices[ii] = int32(piv2 + 2)
              indices[ii + 1] = int32(piv + 3)
              indices[ii + 2] = int32(iv)
            ii += 3
            iv += 1
          of jointMiter:
            vertices[iv] = vtx(ax, ay, 0, 0)
            if jangle < 0:
              if not lineIntersection(px1, py1, px2, py2, x1, y1, x2, y2, ix, iy):
                verticesCount -= 2
                indicesCount -= 6
              else:
                vertices[iv + 1] = vtx(ix, iy, 0, 0)
                for k, d in [iv, iv + 1, piv2 + 1, iv, piv, iv + 1]:
                  indices[ii + k] = int32(d)
                ii += 6
                iv += 2
            else:
              if not lineIntersection(px3, py3, px4, py4, x3, y3, x4, y4, ix, iy):
                verticesCount -= 2
                indicesCount -= 6
              else:
                vertices[iv + 1] = vtx(ix, iy, 0, 0)
                for k, d in [iv, iv + 1, piv2 + 2, iv, piv + 3, iv + 1]:
                  indices[ii + k] = int32(d)
                ii += 6
                iv += 2
          of jointRound:
            var a0, step = 0.0
            var pivstart, pivend = 0
            if jangle < 0:
              a1 = pangle2 - PI2
              a2 = angle + PI2
              a0 = a2
              step = abs(jangle) / float(jointPrecision)
              pivstart = piv + 3
              pivend = piv2 + 1
            else:
              a1 = angle - PI2
              a2 = pangle2 + PI2
              a0 = a1
              step = -abs(jangle) / float(jointPrecision)
              pivstart = piv
              pivend = piv2 + 2
            siv = iv
            vertices[iv] = vtx(ax, ay, 0, 0)
            iv += 1
            for j in 0 ..< jointPrecision - 1:
              vertices[iv] = vtx(ax - cos(a0 - step * float(j)) * w,
                ay - sin(a0 - step * float(j)) * w, 0, 0)
              indices[ii] = int32(siv)
              indices[ii + 1] = int32(if j == 0: pivstart else: iv - 1)
              indices[ii + 2] = int32(iv)
              iv += 1
              ii += 3
            indices[ii] = int32(siv)
            indices[ii + 1] = int32(iv - 1)
            indices[ii + 2] = int32(pivend)
            ii += 3
          of jointNone:
            discard

  # The caps.
  case cap
  of capSquare:
    vertices[iv] = vtx(x2 + cos(angle) * w, y2 + sin(angle) * w, 0, 0)
    vertices[iv + 1] = vtx(x3 + cos(angle) * w, y3 + sin(angle) * w, 0, 0)
    for k, d in [piv + 1, piv + 2, iv + 1, piv + 1, iv, iv + 1]:
      indices[ii + k] = int32(d)
    ii += 6
    iv += 2
    vertices[iv] = vtx(sx1 - cos(sangle) * w, sy1 - sin(sangle) * w, 0, 0)
    vertices[iv + 1] = vtx(sx4 - cos(sangle) * w, sy4 - sin(sangle) * w, 0, 0)
    for k, d in [0, 3, iv + 1, 0, iv, iv + 1]:
      indices[ii + k] = int32(d)
    ii += 6
    iv += 2
  of capRound:
    # The start cap.
    a1 = sangle - PI2
    a2 = sangle + PI2
    var step = (a1 - a2) / float(capPrecision)
    siv = iv
    cx = p[0]
    cy = p[1]
    vertices[iv] = vtx(cx, cy, 0, 0)
    iv += 1
    for i in 0 ..< capPrecision - 1:
      vertices[iv] = vtx(cx + cos(a1 + step * float(i)) * w, cy + sin(a1 + step * float(i)) * w,
        1, 1)
      indices[ii] = int32(siv)
      indices[ii + 1] = int32(if i == 0: 0 else: iv - 1)
      indices[ii + 2] = int32(iv)
      iv += 1
      ii += 3
    indices[ii] = int32(siv)
    indices[ii + 1] = int32(iv - 1)
    indices[ii + 2] = 3
    ii += 3
    # The end cap.
    a1 = angle - PI2
    a2 = angle + PI2
    step = (a2 - a1) / float(capPrecision)
    siv = iv
    cx = p[p.len - 2]
    cy = p[p.len - 1]
    vertices[iv] = vtx(cx, cy, 0, 0)
    iv += 1
    for i in 0 ..< capPrecision - 1:
      vertices[iv] = vtx(cx + cos(a1 + step * float(i)) * w, cy + sin(a1 + step * float(i)) * w,
        0, 0)
      indices[ii] = int32(siv)
      indices[ii + 1] = int32(if i == 0: piv + 1 else: iv - 1)
      indices[ii + 2] = int32(iv)
      iv += 1
      ii += 3
    indices[ii] = int32(siv)
    indices[ii + 1] = int32(iv - 1)
    indices[ii + 2] = int32(piv + 2)
    ii += 3
  of capNone:
    discard

  # The remaining indices all point to the last start vertex.
  while ii < indicesCount:
    indices[ii] = int32(siv)
    inc ii
  vertices.shrink(verticesCount)
  indices.shrink(indicesCount)
  # The bounding box (Kivy's stencil uses it when alpha < 1).
  for v in vertices:
    l.bxmin = min(l.bxmin, float(v.x))
    l.bxmax = max(l.bxmax, float(v.x))
    l.bymin = min(l.bymin, float(v.y))
    l.bymax = max(l.bymax, float(v.y))
  l.vertices = vertices
  l.indices = indices

method build*(l: Line) =
  ## vertex_instructions_line.pxi Line.build: the points from `circle`,
  ## `rectangle` or `rounded_rectangle` when set, then a line strip for
  ## width 1 or triangles for any other width.
  case l.lineMode
  of lmCircle: l.prebuildCircle()
  of lmRectangle: l.prebuildRectangle()
  of lmRoundedRectangle: l.prebuildRoundedRectangle()
  of lmPoints: discard
  if l.width == 1'f32:
    l.buildLegacy()
  else:
    l.buildExtended()

proc newLine*(points: openArray[float] = []; width = 1.0; cap = capRound; joint = jointRound;
    close = false): Line =
  ## `Line(points=..., width=..., cap=..., joint=..., close=...)`. A width
  ## of 0 means 1, as in Kivy. Set `circle`, `rectangle` or
  ## `roundedRectangle` after, in Kivy's keyword order.
  result = Line(textureBinding: newBindTexture(), points: @points, width: float32(if width == 0: 1.0 else: width), cap: cap,
    joint: joint, capPrecision: 10, jointPrecision: 10, close: close, lineMode: lmPoints,
    modeArgs: @[], circle: @[], rectangle: @[], roundedRectangle: @[])
  result.initVertexInstruction(vmLineStrip)
  result.flagUpdate()

proc points*(l: Line): seq[float] {.inline.} =
  ## The points, x1, y1, x2, y2, ...; after `circle`, `rectangle` or
  ## `roundedRectangle`, the ones the last build computed.
  l.points

proc `points=`*(l: Line; points: openArray[float]) =
  ## Sets the points, replacing a circle or rectangle.
  l.points = @points
  l.lineMode = lmPoints
  l.flagUpdate()

proc width*(l: Line): float {.inline.} =
  ## Half the thickness of the line; 1 draws a 1 px polyline.
  float(l.width)

proc `width=`*(l: Line; v: float) =
  ## Sets the width, which must be above 0.
  assert v > 0, "Invalid width value, must be > 0"
  l.width = float32(v)
  l.flagUpdate()

proc cap*(l: Line): LineCap {.inline.} =
  ## The ends of a wide line.
  l.cap

proc `cap=`*(l: Line; v: LineCap) =
  ## Sets the ends.
  l.cap = v
  l.flagUpdate()

proc joint*(l: Line): LineJoint {.inline.} =
  ## The joints of a wide line.
  l.joint

proc `joint=`*(l: Line; v: LineJoint) =
  ## Sets the joints.
  l.joint = v
  l.flagUpdate()

proc capPrecision*(l: Line): int {.inline.} =
  ## The segments of a round cap.
  l.capPrecision

proc `capPrecision=`*(l: Line; v: int) =
  ## Sets the segments of a round cap, at least 1.
  assert v >= 1, "Invalid cap_precision value, must be >= 1"
  l.capPrecision = v
  l.flagUpdate()

proc jointPrecision*(l: Line): int {.inline.} =
  ## The segments of a round joint.
  l.jointPrecision

proc `jointPrecision=`*(l: Line; v: int) =
  ## Sets the segments of a round joint, at least 1.
  assert v >= 1, "Invalid joint_precision value, must be >= 1"
  l.jointPrecision = v
  l.flagUpdate()

proc close*(l: Line): bool {.inline.} =
  ## Whether the last point joins the first.
  l.close

proc `close=`*(l: Line; v: bool) =
  ## Sets whether the line is closed.
  l.close = v
  l.flagUpdate()

proc circle*(l: Line): seq[float] {.inline.} =
  ## x, y, r, angle_start, angle_end, segments of the last build, or empty.
  l.circle

proc `circle=`*(l: Line; args: openArray[float]) =
  ## Draws a circle or arc: (x, y, r[, angle_start, angle_end[, segments]]),
  ## angles in degrees clockwise from the top.
  assert args.len in [3, 5, 6], "Invalid number of arguments"
  l.modeArgs = @args
  l.lineMode = lmCircle
  l.flagUpdate()

proc rectangle*(l: Line): seq[float] {.inline.} =
  ## x, y, width, height of the last build, or empty.
  l.rectangle

proc `rectangle=`*(l: Line; args: openArray[float]) =
  ## Draws a closed rectangle: (x, y, width, height).
  assert args.len == 4, "Invalid number of arguments"
  l.modeArgs = @args
  l.lineMode = lmRectangle
  l.flagUpdate()

proc roundedRectangle*(l: Line): seq[float] {.inline.} =
  ## x, y, w, h, the four normalised radii and the resolution of the last
  ## build, or empty.
  l.roundedRectangle

proc `roundedRectangle=`*(l: Line; args: openArray[float]) =
  ## Draws a closed rounded rectangle: (x, y, w, h, r[, resolution]) or
  ## (x, y, w, h, r1, r2, r3, r4[, resolution]), radii clockwise from the
  ## top left, resolution 45 segments per corner by default.
  assert args.len in [5, 6, 8, 9], "invalid number of arguments"
  l.modeArgs = @args
  l.lineMode = lmRoundedRectangle
  l.flagUpdate()

proc boundingBox*(l: Line): (float, float, float, float) {.inline.} =
  ## xmin, ymin, xmax, ymax of the last wide build (Kivy's stencil box).
  (l.bxmin, l.bymin, l.bxmax, l.bymax)

# ---------------------------------------------------------------- AntiAliasingLine

proc gradientTexture(smoothLine: bool): Texture =
  # Kivy's premultiplied_texture: one texture of each gradient for every
  # instruction, made on first use (Kivy's Cache 'kv.graphics.texture').
  if smoothLine:
    var t = gradients.smoothLine
    if t == nil:
      t = newTexture(4, 1, SmoothLineGradient)
      gradients.smoothLine = t
    result = t
  else:
    var t = gradients.antialiasingLine
    if t == nil:
      t = newTexture(3, 1, AntiAliasingLineGradient)
      gradients.antialiasingLine = t
    result = t

proc filteredPoints(points: openArray[float]): seq[float] =
  # vertex_instructions.pyx AntiAliasingLine.filtered_points: drops each
  # point less than 1 px from the one before it on both axes, and the first
  # if the last is that close to it; fewer than 3 points left is none.
  if points.len < 6:
    return @[]
  var p = @points
  var index = 0
  while index < p.len - 2:
    let (x1, y1) = (p[index], p[index + 1])
    let (x2, y2) = (p[index + 2], p[index + 3])
    if abs(x2 - x1) < 1.0 and abs(y2 - y1) < 1.0:
      p.delete(index + 2)
      p.delete(index + 2)
    else:
      index += 2
  if abs(p[0] - p[p.len - 2]) < 1.0 and abs(p[1] - p[p.len - 1]) < 1.0:
    p.delete(0)
    p.delete(0)
  result = if p.len < 6: @[] else: p

proc newAntiAliasingLine*(stencilMask: Instruction; points: openArray[float] = [];
    close = true): AntiAliasingLine =
  ## `AntiAliasingLine(stencil_mask, points=..., close=...)`: the line of a
  ## smooth shape, `stencilMask`; closed by default.
  result = AntiAliasingLine(textureBinding: newBindTexture(), points: @[], width: 2.5,
    close: close, stencilMask: stencilMask)
  result.initVertexInstruction(vmTriangles)
  `points=`(result, points)
  result.texture = gradientTexture(false)

proc points*(a: AntiAliasingLine): seq[float] {.inline.} =
  ## The outline: the points given, filtered, with the first one again at
  ## the end when closed; empty when fewer than 3 points are left.
  a.points

proc `points=`*(a: AntiAliasingLine; points: openArray[float]) =
  ## Sets the outline. vertex_instructions.pyx AntiAliasingLine.points
  var p = filteredPoints(points)
  if p.len > 0 and a.close:
    p.add p[0]
    p.add p[1]
  a.points = p
  a.flagUpdate()

proc width*(a: AntiAliasingLine): float {.inline.} =
  ## The half-width of the band, 2.5 (Kivy found it by experiment).
  float(a.width)

proc close*(a: AntiAliasingLine): bool {.inline.} =
  ## Whether the line returns to its first point.
  a.close

proc `close=`*(a: AntiAliasingLine; v: bool) =
  ## Sets whether the line is closed; the points are kept as they are.
  a.close = v
  a.flagUpdate()

proc stencilMask*(a: AntiAliasingLine): Instruction {.inline.} =
  ## The shape the line is drawn around.
  a.stencilMask

method radd*(a: sink AntiAliasingLine; ig: InstructionGroup) =
  ## Nothing: the shape adds its line (Kivy's AntiAliasingLine.radd).
  discard

method rinsert*(a: sink AntiAliasingLine; ig: InstructionGroup; index: int) =
  ## Nothing: the shape inserts its line.
  discard

method rremove*(a: AntiAliasingLine; ig: InstructionGroup) =
  ## Nothing: the shape removes its line.
  discard

method build*(a: AntiAliasingLine) =
  ## vertex_instructions.pyx AntiAliasingLine.build: for each segment, a quad
  ## 2.5 px to each side (texture s 0 on one side, 1 on the other), and a
  ## triangle that fills the miter joint with the segment before.
  let p = a.points
  let width = float(a.width)
  if p.len == 0:
    a.vertices = @[]
    a.indices = @[]
    return
  let discardedVcount = if a.close: 0 else: 3
  let vcount = 9 * (p.len - 2) div 2 - discardedVcount
  var vertices = newSeq[Vertex](vcount)
  var ax, ay, bx, by, cx, cy, lastAngle, angle, angleDiff = 0.0
  var offsetX, offsetY, jointOffsetX, jointOffsetY = 0.0
  var iv = 0
  if a.close:
    ax = p[p.len - 4]
    ay = p[p.len - 3]
    bx = p[0]
    by = p[1]
    cx = bx - ax
    cy = by - ay
    lastAngle = arctan2(cy, cx)
  # `<float>ax - offset_x`: the point is cast to a C float first, then the
  # sum is a double, stored as a float.
  proc moved(base, offset: float): float32 {.inline.} =
    float32(float(float32(base)) + offset)
  for i in countup(0, p.len - 3, 2):
    ax = p[i]
    ay = p[i + 1]
    bx = p[i + 2]
    by = p[i + 3]
    cx = bx - ax
    cy = by - ay
    angle = arctan2(cy, cx)
    offsetX = width * sin(angle)
    offsetY = width * cos(angle)
    # The two triangles of the segment.
    for (px, py, ox, oy, s) in [(ax, ay, -offsetX, offsetY, 0'f32),
        (bx, by, offsetX, -offsetY, 1'f32), (ax, ay, offsetX, -offsetY, 1'f32),
        (ax, ay, -offsetX, offsetY, 0'f32), (bx, by, offsetX, -offsetY, 1'f32),
        (bx, by, -offsetX, offsetY, 0'f32)]:
      vertices[iv] = Vertex(x: moved(px, ox), y: moved(py, oy), s0: s, t0: 0)
      inc iv
    # The miter joint.
    if i > 0 or a.close:
      jointOffsetX = width * sin(lastAngle)
      jointOffsetY = width * cos(lastAngle)
      angleDiff = angle - lastAngle
      let direction = if -PI < angleDiff and angleDiff < 0 or angleDiff > PI: -1.0 else: 1.0
      vertices[iv] = Vertex(x: float32(ax), y: float32(ay), s0: 0.5, t0: 0)
      vertices[iv + 1] = Vertex(x: moved(ax, offsetX * direction),
        y: moved(ay, -offsetY * direction), s0: 1, t0: 0)
      vertices[iv + 2] = Vertex(x: moved(ax, jointOffsetX * direction),
        y: moved(ay, -jointOffsetY * direction), s0: 1, t0: 0)
      iv += 3
    lastAngle = angle
  var indices = newSeq[int32](vcount)
  for i in 0 ..< vcount:
    indices[i] = int32(i)
  a.vertices = vertices
  a.indices = indices

# ---------------------------------------------------------------- the smooth shapes

proc hasTextureSet(v: VertexInstruction): bool =
  # vertex_instructions.pyx has_texture_set. Kivy compares the texture with
  # the one given to the constructor; nimkivy's constructors take none, so
  # that is the default texture (nil).
  v.texture != nil or v.source.len > 0

proc tooSmallForAntialiasing(r: Rectangle): bool =
  # vertex_instructions.pyx too_small_for_antialiasing
  let (w, h) = r.size
  result = -4 < w and w < 4 or -4 < h and h < 4

proc adjustParams(r: Rectangle; delta: float) =
  # vertex_instructions.pyx adjust_params: moves the edges `delta` px out
  # (in when negative) through the `pos` and `size` setters (C floats), and
  # a SmoothRoundedRectangle's radii by `delta`, not below 0. Kivy builds
  # with -1 and restores with +1, so a radius below 1 comes back as 1 and a
  # position can move by the last bit of its float.
  var (x, y) = r.pos
  var (w, h) = r.size
  let signX = if w < 0: 1.0 else: -1.0
  let signY = if h < 0: 1.0 else: -1.0
  x += delta * signX
  y += delta * signY
  w += delta * 2 * signX * -1
  h += delta * 2 * signY * -1
  r.pos = (x, y)
  r.size = (w, h)
  if r of SmoothRoundedRectangle:
    let rr = SmoothRoundedRectangle(r)
    var radius = default(array[4, (float, float)])
    for corner in 0 ..< 4:
      let (rx, ry) = rr.radius[corner]
      radius[corner] = (max(0.0, rx + delta), max(0.0, ry + delta))
    `radius=`(rr, radius)

proc smoothRadd(ig: InstructionGroup; target: sink VertexInstruction; aa: sink AntiAliasingLine) =
  # vertex_instructions.pyx radd_instructions: the shape's BindTexture, the
  # shape, the line's BindTexture, the line. As in Kivy, the parent of the
  # line's BindTexture is not set (Kivy sets the shape's twice).
  ig.children.add target.textureBinding
  ig.children.add target
  ig.children.add aa.textureBinding
  ig.children.add aa
  target.textureBinding.setParent(ig)
  aa.setParent(ig)
  target.setParent(ig)

proc smoothRinsert(ig: InstructionGroup; index: int; target: sink VertexInstruction;
    aa: sink AntiAliasingLine) =
  # vertex_instructions.pyx rinsert_instructions: the four in order at
  # `index`, or each at `index` when it is negative (each before the last).
  let step = if index < 0: 0 else: 1
  ig.children.insertAt(index, Instruction(target.textureBinding))
  ig.children.insertAt(index + step, Instruction(target))
  ig.children.insertAt(index + 2 * step, Instruction(aa.textureBinding))
  ig.children.insertAt(index + 3 * step, Instruction(aa))
  target.textureBinding.setParent(ig)
  aa.setParent(ig)
  target.setParent(ig)

proc smoothRremove(ig: InstructionGroup; target: VertexInstruction; aa: AntiAliasingLine) =
  # vertex_instructions.pyx rremove_instructions
  ig.children.removeFirst(target.textureBinding)
  ig.children.removeFirst(target)
  ig.children.removeFirst(aa.textureBinding)
  ig.children.removeFirst(aa)
  target.textureBinding.setParent(nil)
  aa.setParent(nil)
  target.setParent(nil)

proc line(a: sink nil AntiAliasingLine): AntiAliasingLine =
  # A smooth shape's line, which its constructor sets.
  assert a != nil, "a smooth shape without its antialiasing line"
  result = a

# Kivy's radd, rinsert and rremove of each smooth shape, and its
# `antialiasing_line_points`.

method radd*(v: sink SmoothRectangle; ig: InstructionGroup) =
  ## Adds the shape and its antialiasing line, each with its BindTexture.
  smoothRadd(ig, v, line(v.antialiasingLine))

method rinsert*(v: sink SmoothRectangle; ig: InstructionGroup; index: int) =
  ## Inserts the shape and its antialiasing line at `index`.
  smoothRinsert(ig, index, v, line(v.antialiasingLine))

method rremove*(v: SmoothRectangle; ig: InstructionGroup) =
  ## Removes the shape and its antialiasing line.
  smoothRremove(ig, v, line(v.antialiasingLine))

proc antialiasingLine*(v: SmoothRectangle): AntiAliasingLine {.inline.} =
  ## The antialiasing line.
  line(v.antialiasingLine)

proc antialiasingLinePoints*(v: SmoothRectangle): seq[float] {.inline.} =
  ## The points of the antialiasing line after the last build (empty: none).
  line(v.antialiasingLine).points

method radd*(v: sink SmoothEllipse; ig: InstructionGroup) =
  ## Adds the shape and its antialiasing line, each with its BindTexture.
  smoothRadd(ig, v, line(v.antialiasingLine))

method rinsert*(v: sink SmoothEllipse; ig: InstructionGroup; index: int) =
  ## Inserts the shape and its antialiasing line at `index`.
  smoothRinsert(ig, index, v, line(v.antialiasingLine))

method rremove*(v: SmoothEllipse; ig: InstructionGroup) =
  ## Removes the shape and its antialiasing line.
  smoothRremove(ig, v, line(v.antialiasingLine))

proc antialiasingLine*(v: SmoothEllipse): AntiAliasingLine {.inline.} =
  ## The antialiasing line.
  line(v.antialiasingLine)

proc antialiasingLinePoints*(v: SmoothEllipse): seq[float] {.inline.} =
  ## The points of the antialiasing line after the last build (empty: none).
  line(v.antialiasingLine).points

method radd*(v: sink SmoothRoundedRectangle; ig: InstructionGroup) =
  ## Adds the shape and its antialiasing line, each with its BindTexture.
  smoothRadd(ig, v, line(v.antialiasingLine))

method rinsert*(v: sink SmoothRoundedRectangle; ig: InstructionGroup; index: int) =
  ## Inserts the shape and its antialiasing line at `index`.
  smoothRinsert(ig, index, v, line(v.antialiasingLine))

method rremove*(v: SmoothRoundedRectangle; ig: InstructionGroup) =
  ## Removes the shape and its antialiasing line.
  smoothRremove(ig, v, line(v.antialiasingLine))

proc antialiasingLine*(v: SmoothRoundedRectangle): AntiAliasingLine {.inline.} =
  ## The antialiasing line.
  line(v.antialiasingLine)

proc antialiasingLinePoints*(v: SmoothRoundedRectangle): seq[float] {.inline.} =
  ## The points of the antialiasing line after the last build (empty: none).
  line(v.antialiasingLine).points

method radd*(v: sink SmoothTriangle; ig: InstructionGroup) =
  ## Adds the shape and its antialiasing line, each with its BindTexture.
  smoothRadd(ig, v, line(v.antialiasingLine))

method rinsert*(v: sink SmoothTriangle; ig: InstructionGroup; index: int) =
  ## Inserts the shape and its antialiasing line at `index`.
  smoothRinsert(ig, index, v, line(v.antialiasingLine))

method rremove*(v: SmoothTriangle; ig: InstructionGroup) =
  ## Removes the shape and its antialiasing line.
  smoothRremove(ig, v, line(v.antialiasingLine))

proc antialiasingLine*(v: SmoothTriangle): AntiAliasingLine {.inline.} =
  ## The antialiasing line.
  line(v.antialiasingLine)

proc antialiasingLinePoints*(v: SmoothTriangle): seq[float] {.inline.} =
  ## The points of the antialiasing line after the last build (empty: none).
  line(v.antialiasingLine).points

method radd*(v: sink SmoothQuad; ig: InstructionGroup) =
  ## Adds the shape and its antialiasing line, each with its BindTexture.
  smoothRadd(ig, v, line(v.antialiasingLine))

method rinsert*(v: sink SmoothQuad; ig: InstructionGroup; index: int) =
  ## Inserts the shape and its antialiasing line at `index`.
  smoothRinsert(ig, index, v, line(v.antialiasingLine))

method rremove*(v: SmoothQuad; ig: InstructionGroup) =
  ## Removes the shape and its antialiasing line.
  smoothRremove(ig, v, line(v.antialiasingLine))

proc antialiasingLine*(v: SmoothQuad): AntiAliasingLine {.inline.} =
  ## The antialiasing line.
  line(v.antialiasingLine)

proc antialiasingLinePoints*(v: SmoothQuad): seq[float] {.inline.} =
  ## The points of the antialiasing line after the last build (empty: none).
  line(v.antialiasingLine).points

method build*(r: SmoothRectangle) =
  ## vertex_instructions.pyx SmoothRectangle.build: no line with a texture
  ## or a side under 4 px; else the rectangle 1 px inside, the line on it.
  let aa = line(r.antialiasingLine)
  if hasTextureSet(r) or tooSmallForAntialiasing(r):
    `points=`(aa, [])
    procCall build(Rectangle(r))
  else:
    r.adjustParams(-1)
    procCall build(Rectangle(r))
    `points=`(aa, r.points)
    r.adjustParams(1)

method build*(e: SmoothEllipse) =
  ## vertex_instructions.pyx SmoothEllipse.build: as SmoothRectangle's; the
  ## line also goes through the centre, which closes a slice (the stencil
  ## hides it inside a full ellipse).
  let aa = line(e.antialiasingLine)
  if hasTextureSet(e) or tooSmallForAntialiasing(e):
    `points=`(aa, [])
    procCall build(Ellipse(e))
  else:
    e.adjustParams(-1)
    procCall build(Ellipse(e))
    # `self.x + self.w / 2` on C floats.
    `points=`(aa, e.points & @[float(e.x + e.w / 2'f32), float(e.y + e.h / 2'f32)])
    e.adjustParams(1)

method build*(r: SmoothRoundedRectangle) =
  ## vertex_instructions.pyx SmoothRoundedRectangle.build
  let aa = line(r.antialiasingLine)
  if hasTextureSet(r) or tooSmallForAntialiasing(r):
    `points=`(aa, [])
    procCall build(RoundedRectangle(r))
  else:
    r.adjustParams(-1)
    procCall build(RoundedRectangle(r))
    `points=`(aa, r.points)
    r.adjustParams(1)

method build*(t: SmoothTriangle) =
  ## vertex_instructions.pyx SmoothTriangle.build: the line on the triangle
  ## itself (no adjustment).
  let aa = line(t.antialiasingLine)
  if hasTextureSet(t):
    `points=`(aa, [])
    procCall build(Triangle(t))
  else:
    procCall build(Triangle(t))
    `points=`(aa, t.points.toOpenArray(0, 5))

method build*(q: SmoothQuad) =
  ## vertex_instructions.pyx SmoothQuad.build
  let aa = line(q.antialiasingLine)
  if hasTextureSet(q):
    `points=`(aa, [])
    procCall build(Quad(q))
  else:
    procCall build(Quad(q))
    `points=`(aa, q.points)

proc newSmoothRectangle*(pos = (0.0, 0.0); size = (100.0, 100.0)): SmoothRectangle =
  ## `SmoothRectangle(pos=..., size=...)`.
  result = SmoothRectangle(textureBinding: newBindTexture(), antialiasingLine: nil)
  result.antialiasingLine = newAntiAliasingLine(result)
  result.initRectangle(pos, size, vmTriangles)

proc newSmoothEllipse*(pos = (0.0, 0.0); size = (100.0, 100.0); angleStart = 0.0;
    angleEnd = 360.0; segments = 0): SmoothEllipse =
  ## `SmoothEllipse(pos=..., size=..., angle_start=..., angle_end=...,
  ## segments=...)`, as `newEllipse`.
  result = SmoothEllipse(textureBinding: newBindTexture(), segments: segments,
    angleStart: float32(angleStart), angleEnd: float32(if angleEnd == 0: 360.0 else: angleEnd),
    antialiasingLine: nil)
  result.antialiasingLine = newAntiAliasingLine(result)
  result.initRectangle(pos, size, vmTriangleFan)

proc newSmoothRoundedRectangle*(pos = (0.0, 0.0); size = (100.0, 100.0)): SmoothRoundedRectangle =
  ## `SmoothRoundedRectangle(pos=..., size=...)` with RoundedRectangle's
  ## defaults; set `radius` and `segments` after.
  result = SmoothRoundedRectangle(textureBinding: newBindTexture(), segments: [10, 10, 10, 10],
    radius: [(10.0, 10.0), (10.0, 10.0), (10.0, 10.0), (10.0, 10.0)], antialiasingLine: nil)
  result.antialiasingLine = newAntiAliasingLine(result)
  result.initRectangle(pos, size, vmTriangleFan)

proc newSmoothTriangle*(points: openArray[float] = [0.0, 0.0, 100.0, 0.0, 50.0, 100.0]): SmoothTriangle =
  ## `SmoothTriangle(points=...)`.
  assert points.len >= 6
  result = SmoothTriangle(textureBinding: newBindTexture(), points: @points,
    antialiasingLine: nil)
  result.antialiasingLine = newAntiAliasingLine(result)
  result.initVertexInstruction(vmTriangles)
  result.flagUpdate()

proc newSmoothQuad*(points: openArray[float] = [0.0, 50.0, 50.0, 0.0, 100.0, 50.0, 50.0, 100.0]): SmoothQuad =
  ## `SmoothQuad(points=...)`.
  assert points.len == 8, "Quad: invalid number of points"
  result = SmoothQuad(textureBinding: newBindTexture(), points: @points, antialiasingLine: nil)
  result.antialiasingLine = newAntiAliasingLine(result)
  result.initVertexInstruction(vmTriangles)
  result.flagUpdate()

# ---------------------------------------------------------------- SmoothLine

const
  MinDistanceThreshold = float(0.1'f32)   # `float min_distance_threshold = 0.1`
  MinAngleThreshold = 0.017453292519943295  # 1 degree, Kivy's empirical value

proc removeTooNearbyPoints(p: var seq[float]; threshold: float) =
  # vertex_instructions_line.pxi SmoothLine._remove_too_nearby_points
  var index = 0
  while index < p.len - 2:
    if abs(p[index + 2] - p[index]) < threshold and abs(p[index + 3] - p[index + 1]) < threshold:
      p.delete(index + 2)
      p.delete(index + 2)
    else:
      index += 2

proc angleBetween(x1, y1, x2, y2, x3, y3, x4, y4: float): float =
  # vertex_instructions_line.pxi SmoothLine._get_angle_diff: the angle
  # between the vectors (x1, y1)->(x2, y2) and (x3, y3)->(x4, y4).
  let angle1 = arctan2(y2 - y1, x2 - x1)
  let angle2 = arctan2(y4 - y3, x4 - x3)
  result = abs(angle1 - angle2)
  if result > PI:
    result = 2 * PI - result

proc buildSmooth(l: SmoothLine) =
  # vertex_instructions_line.pxi SmoothLine.build_smooth: four vertices per
  # point, two at `width - 1` (opaque, texture s 0.5) and two at that plus
  # `overdraw_width` (transparent, s 1), on the bisector of the joint,
  # mitred; 6 triangles per segment. As in Kivy, the nearby points are
  # removed from the line's own `points`.
  l.points.removeTooNearbyPoints(MinDistanceThreshold)
  var p = l.points
  var mustCloseLine = l.close
  let width = max(0.0, float(l.width) - 1.0)
  let owidth = width + float(l.owidth)
  # A single segment is never closed.
  if p.len <= 4:
    mustCloseLine = false
  if mustCloseLine and not (abs(p[p.len - 2] - p[0]) < MinDistanceThreshold and
      abs(p[p.len - 1] - p[1]) < MinDistanceThreshold):
    p.add p[0]
    p.add p[1]
  let count = p.len div 2
  if count < 2:
    l.vertices = @[]
    l.indices = @[]
    return
  let vcount = count * 4
  let icount = (count - 1) * 18
  var vertices = newSeq[Vertex](vcount)
  var indices = newSeq[int32](icount)
  var ax, ay, bx, by, rx, ry, lastAngle, angle, avAngle, adAngle, angleDiff = 0.0
  if mustCloseLine:
    # close_mode 'straight-line', the only one here.
    ax = p[p.len - 4]
    ay = p[p.len - 3]
    bx = p[0]
    by = p[1]
    rx = bx - ax
    ry = by - ay
    lastAngle = arctan2(ry, rx)
  let maxIndex = p.len
  var iv = 0
  for index in countup(0, maxIndex - 1, 2):
    ax = p[index]
    ay = p[index + 1]
    if index < maxIndex - 2:
      bx = p[index + 2]
      by = p[index + 3]
      rx = bx - ax
      ry = by - ay
      angle = arctan2(ry, rx)
    elif mustCloseLine and index == maxIndex - 2:
      ax = p[0]
      ay = p[1]
      bx = p[2]
      by = p[3]
      rx = bx - ax
      ry = by - ay
      angle = arctan2(ry, rx)
    else:
      angle = lastAngle
    if index == 0 and not mustCloseLine:
      avAngle = angle
      adAngle = PI
    else:
      avAngle = arctan2(sin(angle) + sin(lastAngle), cos(angle) + cos(lastAngle))
      adAngle = abs(PI - abs(angle - lastAngle))
    let a1 = avAngle - PI2
    let a2 = avAngle + PI2
    var lw, olw = 0.0
    if (index == 0 or index >= maxIndex - 2) and not mustCloseLine:
      lw = width
      olw = owidth
    else:
      var ox, oy = 0.0
      if index == 0:
        ox = p[p.len - 4]
        oy = p[p.len - 3]
      else:
        ox = p[index - 2]
        oy = p[index - 1]
      let la1 = lastAngle - PI2
      let la2 = angle - PI2
      let ra1 = lastAngle + PI2
      let ra2 = angle + PI2
      angleDiff = angleBetween(ox + cos(ra1) * owidth, oy + sin(ra1) * owidth,
        ax + cos(ra1) * owidth, ay + sin(ra1) * owidth, ax + cos(ra2) * owidth,
        ay + sin(ra2) * owidth, bx + cos(ra2) * owidth, by + sin(ra2) * owidth)
      # Under 1 degree the intersection is too far away: no mitre.
      if angleDiff < MinAngleThreshold or adAngle < MinAngleThreshold:
        lw = width
        olw = owidth
      else:
        # Where the intersection fails, Kivy keeps rx, ry as they were.
        discard lineIntersection(ox + cos(la1) * width, oy + sin(la1) * width,
          ax + cos(la1) * width, ay + sin(la1) * width, ax + cos(la2) * width,
          ay + sin(la2) * width, bx + cos(la2) * width, by + sin(la2) * width, rx, ry)
        lw = float(float32(sqrt((ax - rx) ^ 2 + (ay - ry) ^ 2)))
        discard lineIntersection(ox + cos(ra1) * owidth, oy + sin(ra1) * owidth,
          ax + cos(ra1) * owidth, ay + sin(ra1) * owidth, ax + cos(ra2) * owidth,
          ay + sin(ra2) * owidth, bx + cos(ra2) * owidth, by + sin(ra2) * owidth, rx, ry)
        olw = float(float32(sqrt((ax - rx) ^ 2 + (ay - ry) ^ 2)))
    lastAngle = angle
    vertices[iv] = vtx(ax + cos(a1) * lw, ay + sin(a1) * lw, 0.5, 0.25)
    vertices[iv + 1] = vtx(ax + cos(a2) * lw, ay + sin(a2) * lw, 0.5, 0.75)
    vertices[iv + 2] = vtx(ax + cos(a1) * olw, ay + sin(a1) * olw, 1, 0)
    vertices[iv + 3] = vtx(ax + cos(a2) * olw, ay + sin(a2) * olw, 1, 1)
    iv += 4
  var ii = 0
  for vindex in countup(0, vcount - 5, 4):
    for d in [0, 2, 6, 0, 6, 4, 1, 0, 4, 1, 4, 5, 3, 1, 5, 3, 5, 7]:
      indices[ii] = int32(vindex + d)
      inc ii
  l.vertices = vertices
  l.indices = indices

method build*(l: SmoothLine) =
  ## vertex_instructions_line.pxi SmoothLine.build: the points from
  ## `circle`, `rectangle` or `rounded_rectangle` when set, then the band.
  case l.lineMode
  of lmCircle: l.prebuildCircle()
  of lmRectangle: l.prebuildRectangle()
  of lmRoundedRectangle: l.prebuildRoundedRectangle()
  of lmPoints: discard
  l.buildSmooth()

proc newSmoothLine*(points: openArray[float] = []; width = 1.0; close = false;
    overdrawWidth = 0.0): SmoothLine =
  ## `SmoothLine(points=..., width=..., close=..., overdraw_width=...)`; an
  ## overdraw width of 0 means Kivy's 1.2. Set `circle`, `rectangle` or
  ## `roundedRectangle` after.
  result = SmoothLine(textureBinding: newBindTexture(), points: @points,
    width: float32(if width == 0: 1.0 else: width), cap: capRound, joint: jointRound,
    capPrecision: 10, jointPrecision: 10, close: close, lineMode: lmPoints, modeArgs: @[],
    circle: @[], rectangle: @[], roundedRectangle: @[],
    owidth: float32(if overdrawWidth == 0: 1.2 else: overdrawWidth))
  result.initVertexInstruction(vmTriangles)
  result.texture = gradientTexture(true)
  result.flagUpdate()

proc overdrawWidth*(l: SmoothLine): float {.inline.} =
  ## How far the transparent border reaches beyond the line, in pixels.
  float(l.owidth)

proc `overdrawWidth=`*(l: SmoothLine; v: float) =
  ## Sets the overdraw width, which must be above 0.
  assert v > 0, "Invalid width value, must be > 0"
  l.owidth = float32(v)
  l.flagUpdate()
