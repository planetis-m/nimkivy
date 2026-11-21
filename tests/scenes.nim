# Renders the reference scenes of reference/scenes.py that nimkivy can build
# so far, into tests/out/<scene>.png, for `reference/compare.py --pixels`:
#
#   bin/scenes-<mode> graphics_basic graphics_line ...
#
# Layer 3 has no Widget yet: the scenes are bare canvases drawn by the
# renderer into a temporary 800 x 600 window (SDL3 offscreen, the renderer
# SDL_RENDER_DRIVER names; run_tests.sh uses opengl) cleared white, as Kivy's
# Window with clearcolor white. A widget's canvas is a Canvas with the same
# instructions, and `add_widget` is the canvas insertion Widget.add_widget
# does. The `.txt` geometry follows with Widget in layer 6.

import std/[assertions, cmdline, sequtils, syncio]
import nimkivy/sdl3/[sdl, image]
import nimkivy/graphics/[instructions, context_instructions, vertex_instructions, renderer]

const
  W = 800.cint
  H = 600.cint

proc graphicsBasic(): Canvas =
  # scenes.py graphics_basic
  let c = newCanvas()
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
  result = c

proc shifted(pts: openArray[float]; x, y: float): seq[float] =
  # scenes.py: [x + p if k % 2 == 0 else y + p for k, p in enumerate(pts)]
  result = @[]
  for k, p in pts:
    result.add(if k mod 2 == 0: x + p else: y + p)

proc graphicsLine(): Canvas =
  # scenes.py graphics_line
  let c = newCanvas()
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
  result = c

proc widgetCanvas(): Canvas =
  # A Widget's canvas, without the Widget.
  newCanvas()

proc addWidget(parent: Canvas; children: var seq[Canvas]; child: Canvas; index: Natural = 0) =
  # uix/widget.py Widget.add_widget, on canvases: `children` is the widget's
  # children list, newest first.
  if index == 0 or children.len == 0:
    children.insert([child], 0)
    parent.add child
  else:
    var nextIndex = 0
    var i: Natural = index
    if i >= children.len:
      i = children.len
      nextIndex = parent.indexof(children[children.len - 1])
    else:
      nextIndex = parent.indexof(children[i])
      if nextIndex == -1:
        nextIndex = parent.length
      else:
        inc nextIndex
    children.insert([child], i)
    # never before canvas.before
    if nextIndex == 0 and parent.hasBefore:
      nextIndex = 1
    parent.insert(nextIndex, child)

proc boxed(r, g, b: float; pos, size: (float, float)): Canvas =
  # scenes.py boxed: a widget with a coloured rectangle.
  result = widgetCanvas()
  result.add newColor(r, g, b)
  result.add newRectangle(pos, size)

proc canvasOrder(): Canvas =
  # scenes.py canvas_order
  let root = widgetCanvas()
  var rootChildren: seq[Canvas] = @[]
  let parent = widgetCanvas()
  parent.before.add newColor(0.8, 0.8, 0.2)
  parent.before.add newRectangle((50.0, 100.0), (500.0, 400.0))
  parent.add newColor(0.2, 0.2, 0.8)
  parent.add newRectangle((100.0, 150.0), (300.0, 300.0))
  parent.after.add newColor(0.8, 0.2, 0.2)
  parent.after.add newRectangle((150.0, 200.0), (100.0, 100.0))
  let child = widgetCanvas()
  child.add newColor(0.2, 0.7, 0.2)
  child.add newRectangle((200.0, 250.0), (300.0, 150.0))
  var parentChildren: seq[Canvas] = @[]
  parent.addWidget(parentChildren, child)
  root.addWidget(rootChildren, parent)

  let faded = widgetCanvas()
  faded.opacity = 0.5
  faded.add newColor(0, 0, 0)
  faded.add newRectangle((580.0, 100.0), (200.0, 400.0))
  let inner = widgetCanvas()
  inner.opacity = 0.5
  inner.add newColor(1, 1, 1)
  inner.add newRectangle((600.0, 300.0), (160.0, 160.0))
  var fadedChildren: seq[Canvas] = @[]
  faded.addWidget(fadedChildren, inner)
  root.addWidget(rootChildren, faded)

  let gone = widgetCanvas()
  gone.add newColor(1, 0, 1)
  gone.add newRectangle((0.0, 0.0), (800.0, 600.0))
  gone.clear()
  root.addWidget(rootChildren, gone)

  root.addWidget(rootChildren, boxed(0.5, 0.5, 0.5, (60.0, 20.0), (200.0, 60.0)))
  root.addWidget(rootChildren, boxed(0.1, 0.1, 0.1, (160.0, 40.0), (200.0, 60.0)))
  root.addWidget(rootChildren, boxed(0.9, 0.5, 0.0, (110.0, 30.0), (200.0, 60.0)), index = 2)
  result = root

proc build(name: string): Canvas =
  case name
  of "graphics_basic", "graphics_basic_msaa": graphicsBasic()
  of "graphics_line": graphicsLine()
  of "canvas_order": canvasOrder()
  else: quit "unknown scene " & name

proc shoot(r: Renderer; name: string) =
  # Kivy's frame: clear with clearcolor white, draw the window's canvas
  # (the root widget's canvas in it), then Window.screenshot.
  let window = newCanvas()
  window.add build(name)
  r.clear([1.0, 1, 1, 1])
  r.draw(window)
  let shot = r.readPixels()
  assert shot != nil, fromCString(SDL_GetError())
  var path = "tests/out/" & name & ".png"
  assert IMG_SavePNG(shot, path.toCString), fromCString(SDL_GetError())
  SDL_DestroySurface(shot)
  echo "wrote ", path

proc main() =
  assert SDL_Init(SDL_INIT_VIDEO), fromCString(SDL_GetError())
  let window = SDL_CreateWindow("scenes", W, H, SDL_WINDOW_HIDDEN)
  assert window != nil, fromCString(SDL_GetError())
  let sdlRenderer = SDL_CreateRenderer(window, nil)
  assert sdlRenderer != nil, fromCString(SDL_GetError())
  let r = newRenderer(sdlRenderer)
  for i in 1 .. paramCount():
    r.shoot(paramStr(i))
  SDL_DestroyRenderer(sdlRenderer)
  SDL_DestroyWindow(window)
  SDL_Quit()

main()
