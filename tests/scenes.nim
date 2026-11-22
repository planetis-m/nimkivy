# Renders the reference scenes of archive/reference/scenes.py into
# tests/out/<scene>.png and <scene>.txt, for `bin/compare tests/out <scene> ...`
# (tests/compare.nim):
#
#   bin/scenes-<mode> graphics_basic boxlayout_tests ...
#
# As scenes.py does, each scene is a widget tree, the root widget of the
# 800 x 600 window (SDL3 offscreen; the renderer SDL_RENDER_DRIVER names,
# run_tests.sh uses opengl), cleared white. After a few frames (the layouts
# run before each frame) the window takes a screenshot, and the `.txt` gets
# every widget's class, pos and size (and a Label's texture_size, an Image's
# texture_size and norm_image_size), walking from each root widget. What
# scenes.py schedules at 0.2 s (opening a modal, freezing a fade) runs after
# the first frames, followed by a few more.

import std/[algorithm, envvars, formatfloat, os, strutils, syncio]
from std/files import tryRemoveFile, moveFile
from std/paths import path
import nimkivy/[config, clock]
import nimkivy/graphics/[context_instructions, vertex_instructions]
import nimkivy/core/image
import nimkivy/uix/[boxlayout, floatlayout, anchorlayout, label, image, screenmanager,
  modalview]

proc a(name: string): string =
  # scenes.py a(): an asset of tests/assets.
  "tests/assets/" & name

# ---------------------------------------------------------------- helpers

proc follow(w: Widget; rect: Rectangle) =
  # rect follows the widget's pos and size (scenes.py binds pos and size).
  discard w.bindPos(proc (v: (float, float)) {.closure.} = rect.pos = v)
  discard w.bindSize(proc (v: (float, float)) {.closure.} = rect.size = v)

type Setup = proc (w: Widget) {.closure.}
  # Sets a widget's keyword arguments.

proc boxed(r, g, b: float; setup: nil Setup = nil): Widget =
  # scenes.py boxed: a plain Widget with a coloured rectangle that follows
  # it. `setup` sets the keyword arguments, before the rectangle is made.
  let w = newWidget()
  if setup != nil: setup(w)
  w.canvas.add newColor(r, g, b)
  let rect = newRectangle(w.pos, w.size)
  w.canvas.add rect
  w.follow(rect)
  result = w

proc frame(widget: Widget; rgba: array[4, float]) =
  # scenes.py frame: the widget's bounds painted in canvas.before.
  widget.canvas.before.add newColor(rgba[0], rgba[1], rgba[2], rgba[3])
  let rect = newRectangle(widget.pos, widget.size)
  widget.canvas.before.add rect
  widget.follow(rect)

proc place(root, child: Widget; x, y, w, h: float) =
  # scenes.py place
  child.sizeHint = (none[float](), none[float]())
  child.pos = (x, y)
  child.size = (w, h)
  root.addWidget(child)

const Grey = [0.85, 0.85, 0.85, 1.0]

# ---------------------------------------------------------------- scenes

proc graphicsBasic(): Widget =
  # scenes.py graphics_basic
  let w = newWidget()
  let c = w.canvas
  c.add newColor(0.8, 0.2, 0.2)
  c.add newRectangle((20.0, 420.0), (160.0, 140.0))
  c.add newColor(0.2, 0.6, 0.2, 0.5)
  c.add newRectangle((100.0, 380.0), (160.0, 140.0))
  c.add newColor(0.2, 0.3, 0.8)
  let rr1 = newRoundedRectangle((300.0, 420.0), (200.0, 140.0))
  rr1.radius = [30.0]
  c.add rr1
  c.add newColor(0.9, 0.6, 0.1)
  let rr2 = newRoundedRectangle((540.0, 420.0), (220.0, 140.0))
  rr2.radius = [(10.0, 10.0), (60.0, 30.0), (0.0, 0.0), (40.0, 40.0)]
  c.add rr2
  c.add newColor(0.5, 0.1, 0.5)
  c.add newEllipse((20.0, 220.0), (180.0, 120.0))
  c.add newColor(0.1, 0.5, 0.5)
  c.add newEllipse((240.0, 200.0), (160.0, 160.0), angleStart = 45, angleEnd = 300)
  c.add newColor(0.3, 0.3, 0.3)
  c.add newEllipse((440.0, 200.0), (160.0, 160.0), segments = 6)
  c.add newColor(0.9, 0.2, 0.5)
  c.add newTriangle([640.0, 200, 780, 200, 700, 360])
  c.add newColor(0, 0, 0, 1)
  c.add newRectangle((20.0, 20.0), (1.0, 1.0))
  c.add newRectangle((30.5, 20.5), (100.4, 40.6))
  c.add newColor(0.2, 0.2, 0.9, 0.25)
  let rr3 = newRoundedRectangle((200.0, 20.0), (560.0, 140.0))
  rr3.radius = [70.0]
  c.add rr3
  result = w

proc shifted(pts: openArray[float]; x, y: float): seq[float] =
  # scenes.py: [x + p if k % 2 == 0 else y + p for k, p in enumerate(pts)]
  result = @[]
  for k, p in pts:
    result.add(if k mod 2 == 0: x + p else: y + p)

proc graphicsSmooth(): Widget =
  # smooth.py graphics_smooth (archive/reference/smooth.py)
  let w = newWidget()
  let c = w.canvas
  c.add newColor(0.2, 0.3, 0.8)
  let rr1 = newSmoothRoundedRectangle((20.0, 440.0), (200.0, 140.0))
  rr1.radius = [30.0]
  c.add rr1
  c.add newColor(0.9, 0.6, 0.1)
  let rr2 = newSmoothRoundedRectangle((240.0, 440.0), (220.0, 140.0))
  rr2.radius = [(10.0, 10.0), (60.0, 30.0), (0.0, 0.0), (40.0, 40.0)]
  c.add rr2
  c.add newColor(0.5, 0.1, 0.5)
  c.add newSmoothEllipse((480.0, 450.0), (180.0, 120.0))
  c.add newColor(0.1, 0.5, 0.5)
  c.add newSmoothEllipse((675.0, 460.0), (110.0, 110.0), angleStart = 45, angleEnd = 300)
  c.add newColor(0.8, 0.2, 0.2)
  c.add newSmoothRectangle((20.5, 300.25), (150.4, 90.6))
  c.add newColor(0.9, 0.2, 0.5)
  c.add newSmoothTriangle([200.0, 300, 330, 315, 255, 410])
  c.add newColor(0.3, 0.6, 0.2)
  c.add newSmoothQuad([360.0, 300, 480, 322, 470, 410, 350, 385])
  c.add newColor(0.3, 0.3, 0.3)
  c.add newSmoothEllipse((510.0, 300.0), (110.0, 110.0), segments = 7)
  # Half alpha over a dark band: the line only outside the shape (Kivy's
  # stencil); here no line, hard edges (PORTING.md, Gaps).
  c.add newColor(0.15, 0.15, 0.15)
  c.add newRectangle((640.0, 280.0), (150.0, 150.0))
  c.add newColor(0.9, 0.9, 0.2, 0.5)
  c.add newSmoothEllipse((650.0, 300.0), (120.0, 100.0))
  c.add newColor(0.2, 0.8, 0.9, 0.5)
  let rr3 = newSmoothRoundedRectangle((700.0, 360.0), (80.0, 60.0))
  rr3.radius = [20.0]
  c.add rr3
  # SmoothLine: an open polyline, closed, circles, an arc, rectangles.
  c.add newColor(0, 0, 0)
  c.add newSmoothLine([20.0, 260, 120, 200, 200, 270, 260, 190], width = 1)
  c.add newColor(0.1, 0.4, 0.1)
  c.add newSmoothLine([280.0, 260, 380, 200, 440, 270, 330, 280], width = 3, close = true)
  c.add newColor(0.6, 0, 0.6)
  let circle = newSmoothLine(width = 2)
  circle.circle = [520.0, 230, 45]
  c.add circle
  let arc = newSmoothLine(width = 1.5)
  arc.circle = [640.0, 230, 45, 30, 270]
  c.add arc
  c.add newColor(0.4, 0.2, 0)
  let rect = newSmoothLine(width = 4)
  rect.rectangle = [700.0, 190, 80, 80]
  c.add rect
  c.add newColor(0.2, 0.2, 0.7)
  let rrl1 = newSmoothLine(width = 2)
  rrl1.roundedRectangle = [20.0, 30, 300, 120, 30]
  c.add rrl1
  let rrl2 = newSmoothLine(width = 1.2)
  rrl2.roundedRectangle = [340.0, 30, 200, 120, 40, 5, 1, 20]
  c.add rrl2
  c.add newColor(0.8, 0.3, 0.1, 0.5)
  c.add newSmoothLine([560.0, 40, 780, 140], width = 6)
  c.add newColor(0, 0, 0)
  c.add newSmoothLine([560.0, 140, 780, 40], width = 1, overdrawWidth = 2.5)
  result = w

proc graphicsLine(): Widget =
  # scenes.py graphics_line
  let w = newWidget()
  let c = w.canvas
  let pts = [0.0, 0, 60, 70, 120, 0]
  c.add newColor(0, 0, 0)
  c.add newLine([20.0, 560, 200, 520, 120, 580], width = 1)
  c.add newLine([220.0, 560, 400, 520, 300, 580], width = 1, close = true)
  for i, cap in [capNone, capSquare, capRound]:
    c.add newColor(0.8, 0.2, 0.2)
    c.add newLine(shifted(pts, 20.0 + float(i) * 150, 420), width = 8, cap = cap,
      joint = jointNone)
  for i, joint in [jointMiter, jointBevel, jointRound, jointNone]:
    c.add newColor(0.2, 0.2, 0.8)
    c.add newLine(shifted(pts, 20.0 + float(i) * 190, 280), width = 10, joint = joint,
      cap = capNone)
  c.add newColor(0.1, 0.5, 0.1)
  for (args, width) in [(@[80.0, 160, 50], 1.0), (@[220.0, 160, 50], 4.0),
      (@[360.0, 160, 50, 45, 135], 3.0), (@[500.0, 160, 50, 0, 270, 12], 2.0)]:
    let l = newLine(width = width)
    l.circle = args
    c.add l
  c.add newColor(0.4, 0.2, 0.0)
  for (args, width) in [(@[580.0, 110, 180, 100], 1.0), (@[590.0, 120, 160, 80], 3.0)]:
    let l = newLine(width = width)
    l.rectangle = args
    c.add l
  for (args, width) in [(@[20.0, 20, 300, 60, 20], 2.0),
      (@[340.0, 20, 300, 60, 30, 5, 0, 15], 1.2)]:
    let l = newLine(width = width)
    l.roundedRectangle = args
    c.add l
  c.add newColor(0.6, 0.0, 0.6)
  c.add newLine([660.0, 20, 780, 80], width = 1.5, cap = capRound)
  result = w

proc addTextured(c: Canvas; v: VertexInstruction; name: string) =
  # Adds an instruction with `source = a(name)` (scenes.py). Kivy sets the
  # source in the constructor, before building the geometry; here it is set
  # before the first draw, which builds it.
  v.source = a(name)
  c.add v

proc graphicsTexture(): Widget =
  # scenes.py graphics_texture
  let w = newWidget()
  let c = w.canvas
  c.add newColor(1, 1, 1, 1)
  c.addTextured(newRectangle((20.0, 380.0), (360.0, 180.0)), "landscape.png")
  c.addTextured(newRectangle((420.0, 340.0), (110.0, 220.0)), "portrait.png")
  c.addTextured(newEllipse((580.0, 380.0), (180.0, 180.0)), "flag.png")
  let rr = newRoundedRectangle((20.0, 140.0), (360.0, 180.0))
  rr.radius = [40.0]
  c.addTextured(rr, "landscape.png")
  c.add newColor(1, 0.5, 0.5, 1)
  c.addTextured(newRectangle((420.0, 140.0), (200.0, 100.0)), "landscape.jpg")
  c.add newColor(1, 1, 1, 0.5)
  c.addTextured(newEllipse((640.0, 140.0), (120.0, 120.0)), "flag.png")
  c.add newColor(1, 1, 1, 1)
  c.addTextured(newRectangle((20.0, 20.0), (200.0, 100.0)), "half_alpha.png")
  c.addTextured(newRectangle((260.0, 20.0), (40.0, 30.0)), "small.png")
  c.addTextured(newRectangle((320.0, 20.0), (160.0, 100.0)), "small.png")
  result = w

proc canvasOrder(): Widget =
  # scenes.py canvas_order
  let root = newWidget()
  let parent = newWidget()
  parent.pos = (50.0, 100.0)
  parent.size = (500.0, 400.0)
  parent.canvas.before.add newColor(0.8, 0.8, 0.2)
  parent.canvas.before.add newRectangle((50.0, 100.0), (500.0, 400.0))
  parent.canvas.add newColor(0.2, 0.2, 0.8)
  parent.canvas.add newRectangle((100.0, 150.0), (300.0, 300.0))
  parent.canvas.after.add newColor(0.8, 0.2, 0.2)
  parent.canvas.after.add newRectangle((150.0, 200.0), (100.0, 100.0))
  let child = newWidget()
  child.pos = (200.0, 250.0)
  child.size = (300.0, 150.0)
  child.canvas.add newColor(0.2, 0.7, 0.2)
  child.canvas.add newRectangle((200.0, 250.0), (300.0, 150.0))
  parent.addWidget(child)  # drawn above parent.canvas, below parent.canvas.after
  root.addWidget(parent)

  let faded = newWidget()
  faded.pos = (580.0, 100.0)
  faded.size = (200.0, 400.0)
  faded.opacity = 0.5
  faded.canvas.add newColor(0, 0, 0)
  faded.canvas.add newRectangle((580.0, 100.0), (200.0, 400.0))
  let inner = newWidget()
  inner.opacity = 0.5
  inner.canvas.add newColor(1, 1, 1)
  inner.canvas.add newRectangle((600.0, 300.0), (160.0, 160.0))  # 0.25 effective
  faded.addWidget(inner)
  root.addWidget(faded)

  let gone = newWidget()
  gone.canvas.add newColor(1, 0, 1)
  gone.canvas.add newRectangle((0.0, 0.0), (800.0, 600.0))
  gone.canvas.clear()  # nothing left to draw
  root.addWidget(gone)

  let first = boxed(0.5, 0.5, 0.5, proc (w: Widget) {.closure.} =
    w.pos = (60.0, 20.0)
    w.size = (200.0, 60.0))
  let second = boxed(0.1, 0.1, 0.1, proc (w: Widget) {.closure.} =
    w.pos = (160.0, 40.0)
    w.size = (200.0, 60.0))
  root.addWidget(first)
  root.addWidget(second)
  root.addWidget(boxed(0.9, 0.5, 0.0, proc (w: Widget) {.closure.} =
    w.pos = (110.0, 30.0)
    w.size = (200.0, 60.0)), index = 2)  # below both
  result = root

proc boxlayoutTests(): Widget =
  # scenes.py boxlayout_tests: the eight layouts of test_uix_boxlayout.py,
  # each in a 200 x 300 cell.
  let root = newFloatLayout()
  for i in 0 ..< 8:
    let lay = newBoxLayout()
    frame(lay, Grey)
    if i mod 2 == 1: lay.orientation = orientationVertical
    if i in [2, 3, 6, 7]: lay.spacing = 20
    if i >= 4: lay.padding = [20.0]
    for (r, g, b) in [(1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, 1.0)]:
      lay.addWidget(boxed(r, g, b))
    root.place(lay, float(i mod 4) * 200 + 5, 300 - float(i div 4) * 300 + 5, 190, 290)
  result = root

proc boxlayoutHints(): Widget =
  # scenes.py boxlayout_hints
  let root = newFloatLayout()

  let row = newBoxLayout()
  frame(row, Grey)
  row.spacing = 10
  row.padding = [10.0, 20.0]
  row.addWidget(boxed(1, 0, 0, proc (w: Widget) {.closure.} =
    w.sizeHint = (none[float](), some(1.0))
    w.width = 80))
  row.addWidget(boxed(0, 1, 0, proc (w: Widget) {.closure.} =
    w.sizeHint = (0.3, 0.5)
    w.posHint = {phTop: 1.0}))
  row.addWidget(boxed(0, 0, 1, proc (w: Widget) {.closure.} =
    w.sizeHint = (some(0.7), none[float]())
    w.height = 40
    w.posHint = {phCenterY: 0.5}))
  row.addWidget(boxed(1, 1, 0, proc (w: Widget) {.closure.} =
    w.sizeHint = (none[float](), none[float]())
    w.size = (50.0, 50.0)
    w.posHint = {phY: 0.0}))
  root.place(row, 10, 450, 780, 140)

  let bounds = newBoxLayout()
  frame(bounds, Grey)
  bounds.spacing = 5
  bounds.padding = [5.0, 10, 15, 20]
  bounds.addWidget(boxed(1, 0, 0, proc (w: Widget) {.closure.} = w.sizeHintMinX = 300.0))
  bounds.addWidget(boxed(0, 1, 0, proc (w: Widget) {.closure.} = w.sizeHintMaxX = 60.0))
  bounds.addWidget(boxed(0, 0, 1, proc (w: Widget) {.closure.} = w.sizeHintX = 2.0))
  root.place(bounds, 10, 300, 780, 130)

  let col = newBoxLayout()
  frame(col, Grey)
  col.orientation = orientationVertical
  col.spacing = 8
  col.padding = [12.0]
  col.addWidget(boxed(1, 0, 0, proc (w: Widget) {.closure.} =
    w.sizeHint = (none[float](), none[float]())
    w.size = (100.0, 30.0)
    w.posHint = {phCenterX: 0.5}))
  col.addWidget(boxed(0, 1, 0, proc (w: Widget) {.closure.} =
    w.sizeHint = (0.5, 0.42)
    w.posHint = {phRight: 1.0}))
  col.addWidget(boxed(0, 0, 1, proc (w: Widget) {.closure.} = w.sizeHint = (1.0, 0.58)))
  col.addWidget(boxed(1, 0, 1, proc (w: Widget) {.closure.} =
    w.sizeHint = (some(0.3), none[float]())
    w.height = 20
    w.posHint = {phX: 0.1}))
  root.place(col, 10, 10, 380, 270)

  let squeeze = newBoxLayout()
  frame(squeeze, Grey)
  squeeze.spacing = 10
  squeeze.padding = [10.0]
  for (r, g, b) in [(1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, 1.0)]:
    squeeze.addWidget(boxed(r, g, b, proc (w: Widget) {.closure.} =
      w.sizeHint = (none[float](), some(1.0))
      w.width = 200))  # wider than the box
  root.place(squeeze, 410, 150, 380, 130)

  let nested = newBoxLayout()
  frame(nested, Grey)
  nested.orientation = orientationVertical
  nested.spacing = 4
  let inner = newBoxLayout()
  inner.spacing = 4
  inner.addWidget(boxed(0.5, 0, 0))
  # the kiosk's "hidden photo" trick
  inner.addWidget(boxed(0, 0.5, 0, proc (w: Widget) {.closure.} = w.sizeHintX = 0.0001))
  nested.addWidget(inner)
  nested.addWidget(boxed(0, 0, 0.5, proc (w: Widget) {.closure.} = w.sizeHintY = 0.5))
  root.place(nested, 410, 10, 380, 130)
  result = root

proc floatlayoutHints(): Widget =
  # scenes.py floatlayout_hints
  let root = newFloatLayout()
  let inner = newFloatLayout()
  inner.sizeHint = (0.9, 0.9)
  inner.posHint = {phCenterX: 0.5, phCenterY: 0.5}
  frame(inner, Grey)
  inner.addWidget(boxed(1, 0, 0, proc (w: Widget) {.closure.} =
    w.sizeHint = (0.2, 0.2)
    w.posHint = {phX: 0.0, phY: 0.0}))
  inner.addWidget(boxed(0, 1, 0, proc (w: Widget) {.closure.} =
    w.sizeHint = (0.2, 0.2)
    w.posHint = {phRight: 1.0, phTop: 1.0}))
  inner.addWidget(boxed(0, 0, 1, proc (w: Widget) {.closure.} =
    w.sizeHint = (0.3, 0.1)
    w.posHint = {phCenterX: 0.5, phCenterY: 0.5}))
  inner.addWidget(boxed(1, 1, 0, proc (w: Widget) {.closure.} =
    w.sizeHint = (none[float](), none[float]())
    w.size = (60.0, 60.0)
    w.posHint = {phX: 0.5, phTop: 0.9}))
  inner.addWidget(boxed(0, 1, 1, proc (w: Widget) {.closure.} =
    w.sizeHint = (none[float](), none[float]())
    w.size = (80.0, 40.0)
    w.pos = (30.0, 300.0)))  # no pos_hint
  inner.addWidget(boxed(1, 0, 1, proc (w: Widget) {.closure.} =
    w.sizeHint = (0.05, 0.05)
    w.sizeHintMin = (100.0, 50.0)
    w.posHint = {phRight: 0.95, phY: 0.05}))
  inner.addWidget(boxed(0.5, 0.5, 0, proc (w: Widget) {.closure.} =
    w.sizeHint = (0.9, 0.3)
    w.sizeHintMaxX = 150.0
    w.posHint = {phCenterX: 0.25, phTop: 0.8}))
  root.addWidget(inner)
  result = root

proc anchorlayoutTests(): Widget =
  # scenes.py anchorlayout_tests: the layouts of test_uix_anchorlayout.py,
  # one per cell.
  let root = newFloatLayout()
  var i = 0
  for ax in [anchorLeft, anchorCenterX, anchorRight]:
    for ay in [anchorTop, anchorCenterY, anchorBottom]:
      let lay = newAnchorLayout()
      frame(lay, Grey)
      lay.anchorX = ax
      lay.anchorY = ay
      lay.padding = [10.0]
      lay.addWidget(boxed(1, 0, 0, proc (w: Widget) {.closure.} =
        w.sizeHint = (none[float](), none[float]())
        w.size = (60.0, 40.0)))
      root.place(lay, float(i mod 3) * 265 + 5, 400 - float(i div 3) * 200 + 5, 255, 190)
      inc i
  result = root

# ---------------------------------------------------------------- labels and images

const Lorem = "Figs have been grown in Greece for thousands of years. The fruit is " &
  "dried in the sun, pressed by hand and packed the same day."
  # scenes.py LOREM

proc sizeToTextSize(l: Label) =
  # scenes.py: the text size follows the label's size.
  discard l.bindSize(proc (v: (float, float)) {.closure.} = l.textSize = v)

proc fitHeight(l: Label) =
  # fit=True in the kiosk: as tall as its wrapped text.
  # scenes.py: the text width follows the width, the height the texture's.
  discard l.bindWidth(proc (v: float) {.closure.} = l.textSize = (some(v), none[float]()))
  discard l.bindTextureSize(proc (v: (float, float)) {.closure.} = l.height = v[1])

proc labelAlign(): Widget =
  # scenes.py label_align
  let root = newFloatLayout()
  for i, ha in [halignLeft, halignCenter, halignRight, halignJustify]:
    for j, va in [valignTop, valignMiddle, valignBottom]:
      let lb = newLabel(Lorem)
      lb.color = [0.0, 0, 0, 1]
      lb.fontSize = 13
      lb.halign = ha
      lb.valign = va
      frame(lb, [0.85, 0.9, 0.95, 1])
      lb.sizeToTextSize()
      root.place(lb, float(i) * 200 + 5, 400 - float(j) * 200 + 5, 190, 190)
  result = root

proc labelWrap(): Widget =
  # scenes.py label_wrap
  register("Deja", "data/fonts/DejaVuSans.ttf", fnBold = "data/fonts/Roboto-Bold.ttf")
  let root = newBoxLayout()
  root.orientation = orientationVertical
  root.padding = [10.0]
  root.spacing = 6
  frame(root, [0.98, 0.96, 0.94, 1])
  for lh in [1.0, 1.25, 0.8]:
    let lb = newLabel("line_height " & $lh & ": " & Lorem)
    lb.color = [0.2, 0.2, 0.2, 1]
    lb.fontSize = 18
    lb.lineHeight = lh
    lb.halign = halignLeft
    lb.sizeHintY = none[float]()
    frame(lb, [0.9, 0.85, 0.8, 1])
    lb.fitHeight()
    root.addWidget(lb)
  let deja = newLabel("Deja regular, size 24")
  deja.fontName = "Deja"
  deja.fontSize = 24
  deja.color = [0.29, 0.18, 0.16, 1]
  deja.sizeHintY = none[float]()
  deja.height = 36
  frame(deja, [0.9, 0.9, 0.8, 1])
  root.addWidget(deja)
  let dejaBold = newLabel("Deja bold (Roboto-Bold file), size 24")
  dejaBold.fontName = "Deja"
  dejaBold.bold = true
  dejaBold.fontSize = 24
  dejaBold.color = [0.29, 0.18, 0.16, 1]
  dejaBold.sizeHintY = none[float]()
  dejaBold.height = 36
  frame(dejaBold, [0.9, 0.9, 0.8, 1])
  root.addWidget(dejaBold)
  let padded = newLabel("Roboto bold 20, padding 30 x 4, halign right")
  padded.bold = true
  padded.fontSize = 20
  padded.padding = [30.0, 4]
  padded.halign = halignRight
  padded.color = [0.42, 0.55, 0.27, 1]
  padded.sizeHintY = none[float]()
  padded.height = 40
  frame(padded, [0.9, 0.9, 0.8, 1])
  root.addWidget(padded)
  let fill = newLabel("fill: size bound to text_size, valign middle")
  fill.fontSize = 20
  fill.color = [0.0, 0, 0, 1]
  fill.halign = halignCenter
  fill.valign = valignMiddle
  fill.sizeToTextSize()
  frame(fill, [0.8, 0.9, 0.8, 1])
  root.addWidget(fill)
  let spacer = newWidget()
  spacer.sizeHintY = 0.2
  root.addWidget(spacer)
  result = root

proc labelDefault(): Widget =
  # scenes.py label_default
  let root = newFloatLayout()
  proc add(root: Widget; text: string; size: float; color: array[4, float];
      bg: array[4, float]; x, y, w, h: float; disabled = false) =
    let lb = newLabel(text)
    if size > 0: lb.fontSize = size
    if color[3] >= 0: lb.color = color
    lb.disabled = disabled
    frame(lb, bg)
    root.place(lb, x, y, w, h)
  const black = [0.0, 0, 0, 1]
  const keep = [0.0, 0, 0, -1]      # the default colour
  root.add("Default label (Roboto 15sp, white)", 0, keep, [0.3, 0.3, 0.3, 1], 20, 500, 360, 60)
  root.add("first line\nsecond, longer line\nthird", 22, black, Grey, 420, 440, 360, 140)
  root.add("Too long for the widget, so it overflows both sides", 20, black, Grey,
    250, 360, 300, 40)
  root.add("disabled label", 28, keep, [0.2, 0.2, 0.2, 1], 20, 260, 360, 60, disabled = true)
  root.add("", 0, black, Grey, 420, 260, 360, 60)
  root.add("Ελληνικά — ünïcödé ½ €", 26, black, Grey, 20, 160, 760, 60)
  root.add("tiny 9", 9, black, Grey, 20, 60, 120, 40)
  root.add("huge 64", 64, black, Grey, 200, 40, 400, 100)
  result = root

const ImageBg = [0.8, 0.8, 0.8, 1]

proc imageFit(): Widget =
  # scenes.py image_fit
  let root = newFloatLayout()
  for i, mode in [fitScaleDown, fitFill, fitContain, fitCover]:
    for j, src in ["landscape.png", "portrait.png", "small.png"]:
      let img = newImage(a(src))
      img.fitMode = mode
      frame(img, ImageBg)
      root.place(img, float(i) * 200 + 10, 400 - float(j) * 200 + 10, 180, 150)
  result = root

proc imageMisc(): Widget =
  # scenes.py image_misc
  let root = newFloatLayout()
  let tinted = newImage(a("landscape.png"))
  tinted.color = [1.0, 0.5, 0.5, 1]
  tinted.fitMode = fitContain
  frame(tinted, ImageBg)
  root.place(tinted, 10, 310, 380, 280)
  let faded = newImage(a("landscape.png"))
  faded.opacity = 0.4
  faded.fitMode = fitContain
  frame(faded, ImageBg)
  root.place(faded, 410, 310, 380, 280)
  let changed = newImage(a("portrait.png"))
  changed.fitMode = fitCover
  changed.source = a("landscape.jpg")
  frame(changed, ImageBg)
  root.place(changed, 10, 10, 380, 280)
  let empty = newImage()       # no source: a white box
  frame(empty, ImageBg)
  root.place(empty, 410, 10, 380, 280)
  result = root

type
  LateAction = proc () {.closure.}
    # What scenes.py schedules at 0.2 s (Clock.schedule_once): run by
    # `shoot` after the first frames.
  Late = ref object
    action: nil LateAction

let late = Late(action: nil)

proc screenRelative(): Widget =
  # scenes.py screen_relative
  let root = newFloatLayout()
  let sm = newScreenManager()
  sm.sizeHint = (none[float](), none[float]())
  sm.size = (500.0, 400.0)
  sm.pos = (200.0, 100.0)
  let s = newScreen("one")
  s.addWidget(boxed(0.9, 0.9, 0.7))
  let box = newBoxLayout()
  box.padding = [20.0]
  box.spacing = 20
  box.addWidget(boxed(1, 0, 0))
  box.addWidget(boxed(0, 0, 1, proc (w: Widget) {.closure.} = w.sizeHintY = 0.5))
  s.addWidget(box)
  s.addWidget(boxed(0, 0.6, 0, proc (w: Widget) {.closure.} =     # local (0, 0)
    w.sizeHint = (none[float](), none[float]())
    w.size = (50.0, 50.0)
    w.pos = (0.0, 0.0)))
  s.addWidget(boxed(0.5, 0, 0.5, proc (w: Widget) {.closure.} =   # clipped
    w.sizeHint = (none[float](), none[float]())
    w.size = (80.0, 80.0)
    w.pos = (450.0, 350.0)))
  sm.addWidget(s)
  root.addWidget(sm)
  result = root

proc fadeHalf(): Widget =
  # scenes.py fade_half: FadeTransition frozen at progress 0.5.
  let sm = newScreenManager()
  let fade = newFadeTransition()
  fade.duration = 10
  sm.transition = fade
  let one = newScreen("one")
  let two = newScreen("two")
  one.addWidget(boxed(0.9, 0.2, 0.2))
  one.addWidget(boxed(1, 1, 1, proc (w: Widget) {.closure.} =
    w.sizeHint = (0.4, 0.4)
    w.posHint = {phX: 0.1, phY: 0.1}))
  two.addWidget(boxed(0.2, 0.2, 0.9, proc (w: Widget) {.closure.} =
    w.sizeHint = (0.6, 0.6)
    w.posHint = {phRight: 0.9, phTop: 0.9}))
  sm.addWidget(one)
  sm.addWidget(two)
  late.action = proc () {.closure.} =
    sm.current = "two"
    let tr = sm.transition
    let a = tr.anim
    if a != nil:
      a.cancel(tr)    # stop the clock-driven progress: deterministic picture
    tr.animProgress(0.5)
  result = sm

proc modalCustom(): Widget =
  # scenes.py modal_custom: the kiosk's picker style.
  let root = newWidget()
  root.addWidget(boxed(0.2, 0.6, 0.3, proc (w: Widget) {.closure.} =
    w.pos = (0.0, 0.0)
    w.size = (800.0, 600.0)))
  let mv = newModalView()
  mv.sizeHint = (none[float](), none[float]())
  mv.size = (420.0, 260.0)
  mv.autoDismiss = true
  mv.background = ""
  mv.backgroundColor = [0.0, 0, 0, 0]
  mv.overlayColor = [0.29, 0.18, 0.16, 0.45]
  let panel = newBoxLayout()
  panel.orientation = orientationVertical
  panel.padding = [20.0]
  panel.spacing = 10
  frame(panel, [0.98, 0.96, 0.94, 1])
  let title = newLabel("Choose language")
  title.color = [0.29, 0.18, 0.16, 1]
  title.fontSize = 24
  title.bold = true
  panel.addWidget(title)
  panel.addWidget(boxed(0.74, 0.65, 0.44))
  mv.addWidget(panel)
  late.action = proc () {.closure.} = mv.open(animation = false)
  result = root

proc modalDefault(): Widget =
  # scenes.py modal_default: Kivy's defaults (nimkivy's background is a
  # plain white box, not the atlas image: expected to differ).
  let root = newWidget()
  root.addWidget(boxed(0.9, 0.9, 0.9, proc (w: Widget) {.closure.} =
    w.pos = (0.0, 0.0)
    w.size = (800.0, 600.0)))
  let mv = newModalView()
  mv.sizeHint = (0.5, 0.4)
  mv.addWidget(newLabel("default ModalView"))
  late.action = proc () {.closure.} = mv.open(animation = false)
  result = root

proc build(name: string): Widget =
  case name
  of "graphics_basic", "graphics_basic_msaa": graphicsBasic()
  of "graphics_line": graphicsLine()
  of "graphics_smooth": graphicsSmooth()
  of "graphics_texture": graphicsTexture()
  of "canvas_order": canvasOrder()
  of "boxlayout_tests": boxlayoutTests()
  of "boxlayout_hints": boxlayoutHints()
  of "floatlayout_hints": floatlayoutHints()
  of "anchorlayout_tests": anchorlayoutTests()
  of "label_align": labelAlign()
  of "label_wrap": labelWrap()
  of "label_default": labelDefault()
  of "image_fit": imageFit()
  of "image_misc": imageMisc()
  of "screen_relative": screenRelative()
  of "fade_half": fadeHalf()
  of "modal_custom": modalCustom()
  of "modal_default": modalDefault()
  else: quit "unknown scene " & name

# ---------------------------------------------------------------- runner

proc fmt(p: (float, float)): string =
  # scenes.py fmt: "(x, y)" with 3 decimals.
  "(" & formatFloat(p[0], ffDecimal, 3) & ", " & formatFloat(p[1], ffDecimal, 3) & ")"

proc typeName(w: Widget): string =
  # The widget's type, as the geometry fixtures name it: most derived first.
  if w of ModalView: "ModalView"
  elif w of Screen: "Screen"
  elif w of ScreenManager: "ScreenManager"
  elif w of RelativeLayout: "RelativeLayout"
  elif w of AnchorLayout: "AnchorLayout"
  elif w of BoxLayout: "BoxLayout"
  elif w of FloatLayout: "FloatLayout"
  elif w of Label: "Label"
  elif w of Image: "Image"
  else: "Widget"

proc timeRedraws(name: string) =
  # With SCENES_REDRAW=<n> (tools/profile.sh): the scene is drawn n more
  # times, uncapped, and the frame times are printed: the drawing cost of a
  # settled tree (nothing changes but the redraw request).
  var n = 0
  try:
    n = getEnv("SCENES_REDRAW", "0").parseInt
  except:
    quit "SCENES_REDRAW is not a number"
  if n <= 0: return
  Clock.maxFps = 0
  var ms: seq[float] = @[]
  for _ in 0 ..< n:
    Window.canvas.askUpdate()
    let t0 = time()
    discard EventLoop.idle()
    ms.add (time() - t0) * 1000.0
  var total = 0.0
  for x in ms: total += x
  ms.sort()
  echo "redraw ", name, ": n ", n, " mean ", formatFloat(total / float(n), ffDecimal, 3),
    " p50 ", formatFloat(ms[n div 2], ffDecimal, 3),
    " p95 ", formatFloat(ms[min(n - 1, int(0.95 * float(n - 1) + 0.5))], ffDecimal, 3),
    " max ", formatFloat(ms[n - 1], ffDecimal, 3), " ms"

proc shoot(name: string) =
  # scenes.py shoot: the root widget in the window, a few frames, then the
  # screenshot (Window.screenshot numbers the file; it is renamed) and the
  # geometry of every widget.
  # scenes.py: multisamples 0, but 2 for the `_msaa` scenes.
  Config.graphics.multisamples = if name.endsWith("_msaa"): 2 else: 0
  let root = build(name)
  Window.addWidget(root)
  for _ in 0 ..< 5:
    discard EventLoop.idle()
  let act = late.action
  if act != nil:
    late.action = nil
    act()
    for _ in 0 ..< 5:
      discard EventLoop.idle()
  var cwd = ""
  try:
    cwd = getCurrentDir()
  except:
    quit "no current directory"
  let target = cwd / "tests" / "out" / (name & ".png")
  discard tryRemoveFile(path(target))
  let shot = Window.screenshot(cwd / "tests" / "out" / (name & ".png"))
  try:
    moveFile(path(shot), path(target))
  except:
    quit "cannot rename " & shot
  var lines: seq[string] = @[]
  for top in Window.children:
    if top of Widget:
      for wid in Widget(top).walk():
        var line = typeName(wid) & " pos=" & fmt(wid.pos) & " size=" & fmt(wid.size)
        # scenes.py: textureSize and normImageSize where the widget has them.
        if wid of Label:
          line.add " textureSize=" & fmt(Label(wid).textureSize)
        elif wid of Image:
          line.add " textureSize=" & fmt(Image(wid).textureSize)
          line.add " normImageSize=" & fmt(Image(wid).normImageSize)
        lines.add line
  try:
    writeFile(cwd / "tests" / "out" / (name & ".txt"), lines.join("\n") & "\n")
  except:
    quit "cannot write " & name & ".txt"
  timeRedraws(name)
  let tops = Window.children
  for top in tops:
    if top of ModalView: ModalView(top).dismiss(animation = false)
    else: Window.removeWidget(top)
  echo "wrote tests/out/", name, ".png and .txt"

proc main() =
  # scenes.py shoot's Config: 800 x 600, not resizable; multisamples are set
  # for each scene (shoot).
  Config.graphics.width = 800
  Config.graphics.height = 600
  Config.graphics.resizable = false
  EventLoop.ensureWindow()
  Window.clearcolor = [1.0, 1.0, 1.0, 1.0]
  for i in 1 .. paramCount():
    shoot(paramStr(i))
  EventLoop.exit()

main()
