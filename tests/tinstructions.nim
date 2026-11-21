# Tests graphics/instructions, context_instructions, stencil_instructions and
# the renderer: the children of a canvas after add, insert, remove and clear
# against Kivy's (reference/out/graphics_points.txt, the `canvas` lines),
# update flags, and what the renderer draws: the opacity product, the colour
# state across canvases, translation and stencil clipping. Drawing is headless
# (run_tests.sh sets SDL_VIDEO_DRIVER=offscreen).

import std/[assertions, strutils, syncio]
import nimkivy/sdl3/sdl
import nimkivy/graphics/[instructions, context_instructions, vertex_instructions,
  stencil_instructions, renderer]

proc className(i: Instruction): string =
  # Kivy's type(x).__name__ for the instructions used here.
  if i of Canvas: "Canvas"
  elif i of CanvasBase: "CanvasBase"
  elif i of BindTexture: "BindTexture"
  elif i of Color: "Color"
  elif i of Ellipse: "Ellipse"
  elif i of Rectangle: "Rectangle"
  elif i of Triangle: "Triangle"
  else: "?"

proc names(c: InstructionGroup): string =
  var parts: seq[string] = @[]
  for i in 0 ..< c.children.len:
    parts.add className(c.children[i])
  result = parts.join(" ")

proc kivyCanvasLines(): seq[string] =
  # The `canvas ...` lines Kivy printed, without the `canvas ` prefix.
  var text = ""
  try:
    text = readFile("reference/out/graphics_points.txt")
  except:
    quit "cannot read reference/out/graphics_points.txt"
  result = @[]
  for line in text.splitLines():
    if line.startsWith("canvas "):
      result.add line.substr(7)

# The same steps as reference/graphics_points.py canvas_steps.
block canvas_children:
  let kivy = kivyCanvasLines()
  var got: seq[string] = @[]
  let c = newCanvas()
  c.add newColor(1, 0, 0)
  let rect = newRectangle()
  c.add rect
  got.add "add " & names(c)
  c.before.add newColor()
  got.add "before " & names(c)
  c.after.add newColor()
  got.add "after " & names(c)
  c.add newEllipse()
  got.add "add_with_after " & names(c)
  # A vertex instruction inserted at index >= 0 lands before its BindTexture.
  c.insert(1, newTriangle())
  got.add "insert_1 " & names(c)
  c.insert(-1, newTriangle())
  got.add "insert_minus_1 " & names(c)
  c.remove(rect)
  got.add "remove " & names(c)
  got.add "indexof_before " & $c.indexof(c.before) & " after " & $c.indexof(c.after) &
    " length " & $c.length
  c.clear()
  got.add "clear " & names(c)
  let g = newCanvas()
  g.add newRectangle()
  g.clear()
  got.add "clear_plain " & $g.children.len
  assert got == kivy, "\n" & got.join("\n") & "\nKivy:\n" & kivy.join("\n")

block update_flags:
  let root = newCanvas()
  let child = newCanvas()
  root.add child
  let rect = newRectangle()
  child.add rect
  assert root.needsRedraw and child.needsRedraw and rect.needsRedraw
  root.flagUpdateDone()
  child.flagUpdateDone()
  rect.flagUpdateDone()
  # Setting the same position does not flag (Rectangle.pos).
  rect.pos = (0.0, 0.0)
  assert not root.needsRedraw
  rect.pos = (1.0, 0.0)
  assert rect.needsRedraw and child.needsRedraw and root.needsRedraw
  assert rect.parent == InstructionGroup(child)

# Drawing: a 64 x 64 window, read back pixel by pixel.
proc pixel(s: ptr SDL_Surface; x, y: int): array[4, uint8] =
  let row = cast[ptr UncheckedArray[uint8]](s.pixels)
  let i = y * int(s.pitch) + x * 4
  result = [row[i], row[i + 1], row[i + 2], row[i + 3]]

proc near(a: array[4, uint8]; r, g, b: int): bool =
  abs(int(a[0]) - r) <= 1 and abs(int(a[1]) - g) <= 1 and abs(int(a[2]) - b) <= 1

assert SDL_Init(SDL_INIT_VIDEO), fromCString(SDL_GetError())
let window = SDL_CreateWindow("tinstructions", 64, 64, SDL_WINDOW_HIDDEN)
assert window != nil, fromCString(SDL_GetError())
let sdlRenderer = SDL_CreateRenderer(window, nil)
assert sdlRenderer != nil, fromCString(SDL_GetError())
let r = newRenderer(sdlRenderer)

proc render(c: Canvas): ptr SDL_Surface =
  # One frame on black; the pixels as RGBA bytes, y down.
  r.clear([0.0, 0, 0, 1])
  r.draw(c)
  let shot = r.readPixels()
  assert shot != nil, fromCString(SDL_GetError())
  let rgba = SDL_ConvertSurface(shot, SDL_PIXELFORMAT_RGBA32)
  assert rgba != nil
  SDL_DestroySurface(shot)
  result = rgba

block opacity_product:
  # Opacity multiplies down the tree (0.5 x 0.5) and applies to alpha.
  let outer = newCanvas()
  outer.opacity = 0.5
  let inner = newCanvas()
  inner.opacity = 0.5
  inner.add newColor(1, 1, 1)
  inner.add newRectangle((0.0, 0.0), (32.0, 64.0))
  outer.add inner
  # After the inner canvas the outer opacity applies again.
  outer.add newRectangle((32.0, 0.0), (32.0, 64.0))
  let root = newCanvas()
  root.add outer
  let s = render(root)
  assert near(pixel(s, 8, 8), 64, 64, 64), $pixel(s, 8, 8)
  assert near(pixel(s, 40, 8), 128, 128, 128), $pixel(s, 40, 8)
  SDL_DestroySurface(s)
  assert not root.needsRedraw and not inner.needsRedraw

block color_state_crosses_canvases:
  # A Color in one canvas applies to what the next canvas draws, until the
  # next Color (Kivy's colour lives in the render context).
  let root = newCanvas()
  let a = newCanvas()
  a.add newColor(1, 0, 0)
  let b = newCanvas()
  b.add newRectangle((0.0, 0.0), (64.0, 64.0))
  root.add a
  root.add b
  let s = render(root)
  assert near(pixel(s, 10, 10), 255, 0, 0), $pixel(s, 10, 10)
  SDL_DestroySurface(s)

block translate_push_pop:
  # Kivy's y is up: (0, 0) is the bottom-left pixel.
  let root = newCanvas()
  root.add newColor(0, 1, 0)
  root.add newPushMatrix()
  root.add newTranslate(32, 32)
  root.add newRectangle((0.0, 0.0), (16.0, 16.0))     # top right quarter's corner
  root.add newPopMatrix()
  root.add newColor(0, 0, 1)
  root.add newRectangle((0.0, 0.0), (16.0, 16.0))     # bottom left
  let s = render(root)
  assert near(pixel(s, 40, 24), 0, 255, 0), $pixel(s, 40, 24)
  assert near(pixel(s, 8, 56), 0, 0, 255), $pixel(s, 8, 56)
  assert near(pixel(s, 8, 24), 0, 0, 0), $pixel(s, 8, 24)
  SDL_DestroySurface(s)

block stencil_clip:
  # StencilPush, a Rectangle mask, StencilUse: what follows is clipped to
  # the mask, nested masks intersect, and StencilPop restores the clip.
  let root = newCanvas()
  root.add newStencilPush()
  root.add newRectangle((0.0, 0.0), (32.0, 64.0))      # left half
  root.add newStencilUse()
  root.add newStencilPush()
  root.add newRectangle((0.0, 0.0), (64.0, 32.0))      # bottom half
  root.add newStencilUse()
  root.add newColor(1, 0, 0)
  root.add newRectangle((0.0, 0.0), (64.0, 64.0))      # red: bottom left quarter only
  root.add newStencilUnUse()
  root.add newRectangle((0.0, 0.0), (64.0, 32.0))
  root.add newStencilPop()
  root.add newColor(0, 1, 0)
  root.add newRectangle((16.0, 48.0), (48.0, 16.0))    # green: clipped to the left half
  root.add newStencilUnUse()
  root.add newRectangle((0.0, 0.0), (32.0, 64.0))
  root.add newStencilPop()
  root.add newColor(0, 0, 1)
  root.add newRectangle((56.0, 0.0), (8.0, 8.0))       # blue: not clipped
  let s = render(root)
  assert near(pixel(s, 8, 56), 255, 0, 0), $pixel(s, 8, 56)
  assert near(pixel(s, 40, 56), 0, 0, 0), $pixel(s, 40, 56)
  assert near(pixel(s, 8, 24), 0, 0, 0), $pixel(s, 8, 24)
  assert near(pixel(s, 24, 8), 0, 255, 0), $pixel(s, 24, 8)
  assert near(pixel(s, 40, 8), 0, 0, 0), $pixel(s, 40, 8)
  assert near(pixel(s, 60, 60), 0, 0, 255), $pixel(s, 60, 60)
  SDL_DestroySurface(s)

block wide_line_and_fan:
  # A wide Line and an Ellipse go through SDL_RenderGeometry.
  let root = newCanvas()
  root.add newColor(1, 1, 0)
  root.add newLine([4.0, 32, 60, 32], width = 4, cap = capNone)
  root.add newColor(0, 1, 1)
  root.add newEllipse((24.0, 44.0), (16.0, 16.0))
  let s = render(root)
  assert near(pixel(s, 30, 31), 255, 255, 0), $pixel(s, 30, 31)
  assert near(pixel(s, 30, 37), 0, 0, 0), $pixel(s, 30, 37)
  assert near(pixel(s, 32, 12), 0, 255, 255), $pixel(s, 32, 12)
  SDL_DestroySurface(s)

SDL_DestroyRenderer(sdlRenderer)
SDL_DestroyWindow(window)
SDL_Quit()
