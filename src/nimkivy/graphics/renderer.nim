## The renderer: draws a canvas tree with SDL_Renderer. It replaces Kivy's
## OpenGL back end (`graphics/opengl*.pyx`, `shader.pyx`, `vbo.pyx`,
## `context.pyx`) and the `apply` methods of the instructions.
##
## `draw` walks the tree in order, as Kivy's RenderContext applies it. It
## keeps Kivy's render context state: the colour (set by Color, for every
## vertex instruction after it in the tree), the opacity (multiplied by each
## Canvas and restored after it), the translation (PushMatrix, Translate,
## PopMatrix), the bound texture (BindTexture) and the stencil layers, here a
## stack of clip rectangles. A flagged vertex instruction is rebuilt first.
## Its vertices, in Kivy's coordinates with y up, are moved by the
## translation and flipped to SDL's y down in one place (`toSdl`), then drawn
## with SDL_RenderGeometry in the colour times the opacity (Kivy's shader:
## `color * vec4(1, 1, 1, opacity)` times the texture). A Line of width 1 is
## drawn with SDL_RenderLines.
##
## Blending is Kivy's `glBlendFuncSeparate(SRC_ALPHA, ONE_MINUS_SRC_ALPHA,
## ONE, ONE)` (instructions.pyx `reset_gl_context`).
##
## An AntiAliasingLine drawn with a colour whose alpha is below 1 goes, in
## Kivy, through a stencil of its shape, so that it is drawn only outside
## the shape. SDL_Renderer has no stencil, so here it is not drawn and the
## translucent shape keeps a hard edge (Gaps).
##
## Two instructions exist only for FadeTransition (layer 8), because they
## need the SDL renderer: `Fbo` draws its children into a render-target
## texture with a fresh render context, cleared to its `clearColor` (Kivy's
## Fbo with ClearColor and ClearBuffers), and `FadeMix` draws two such
## textures mixed, `t*in + (1-t)*out`, as FadeTransition's shader does.

import std/math
import ../sdl3/sdl
import texture, instructions, context_instructions, vertex_instructions, stencil_instructions

type
  StencilPhase = enum
    # Where the stencil instructions are (stencil_instructions.pyx `op`).
    spNone      # no mask is being drawn or erased
    spMask      # between StencilPush and StencilUse: the drawing is the mask
    spUnmask    # between StencilUnUse and StencilPop: the drawing erases it

  Box = object
    # A bounding box in window coordinates, y up; empty when x0 > x1.
    x0, y0, x1, y1: float

  Fbo* = ref object of InstructionGroup
    ## Draws its children into a texture of `width` x `height`, cleared to
    ## `clearColor` first, when it or a child changed. Kivy's Fbo, only as
    ## FadeTransition uses it (graphics/fbo.pyx).
    width*, height*: int
    clearColor*: array[4, float]
    texture*: nil Texture          ## the render target, made on first draw

  FadeMix* = ref object of Instruction
    ## A rectangle showing `t*in + (1-t)*out` of two Fbo textures: the
    ## render context and shader of FadeTransition (uix/screenmanager.py).
    fboOut, fboIn: Fbo
    x, y, w, h: float
    t: float

  RenderState = object
    # The render context state an Fbo saves and restores.
    target: nil Texture
    height: float32
    color: array[4, float]
    opacity: float
    opacityStack: seq[float]
    tx, ty: float32
    matrixStack: seq[(float32, float32)]
    texture: nil Texture
    phase: StencilPhase
    mask: Box
    clipStack: seq[SDL_Rect]

  Renderer* = ref object
    ## Draws canvases on an SDL renderer it does not own.
    sdl: SDL_Renderer
    target: nil Texture               # the current render target; nil is the window
    blendMode: SDL_BlendMode
    height: float32                   # of the current target, for the y flip
    color: array[4, float]            # Kivy's 'color' state
    opacity: float                    # Kivy's 'opacity' state
    opacityStack: seq[float]
    tx, ty: float32                   # the translation (Kivy's modelview)
    matrixStack: seq[(float32, float32)]
    texture: nil Texture              # the bound texture; nil is the default
    phase: StencilPhase
    mask: Box                         # the mask being drawn
    clipStack: seq[SDL_Rect]          # the clip of each used stencil layer
    vbuf: seq[SDL_Vertex]
    ibuf: seq[cint]
    points: seq[SDL_FPoint]

proc emptyBox(): Box {.inline.} =
  Box(x0: Inf, y0: Inf, x1: -Inf, y1: -Inf)

proc newRenderer*(sdl: SDL_Renderer): Renderer =
  ## A renderer drawing on `sdl` (the window's).
  # GAP: no multisample antialiasing, where Kivy's default is
  # `multisamples = 2`: edges of ellipses, rounded corners and wide lines are
  # more jagged (graphics_basic_msaa: 0.27% of pixels differ), because
  # SDL_Renderer has no MSAA
  result = Renderer(sdl: sdl, target: nil, blendMode: SDL_BLENDMODE_BLEND, height: 0, color: [1.0, 1, 1, 1],
    opacity: 1, opacityStack: @[], tx: 0, ty: 0, matrixStack: @[], texture: nil, phase: spNone,
    mask: emptyBox(), clipStack: @[], vbuf: @[], ibuf: @[], points: @[])
  let kivyBlend = SDL_ComposeCustomBlendMode(SDL_BLENDFACTOR_SRC_ALPHA,
    SDL_BLENDFACTOR_ONE_MINUS_SRC_ALPHA, SDL_BLENDOPERATION_ADD, SDL_BLENDFACTOR_ONE,
    SDL_BLENDFACTOR_ONE, SDL_BLENDOPERATION_ADD)
  if SDL_SetRenderDrawBlendMode(sdl, kivyBlend):
    result.blendMode = kivyBlend
  else:
    # GAP: where the SDL driver refuses custom blend modes (the software
    # renderer of the headless tests), blending is SDL_BLENDMODE_BLEND: the
    # colour is Kivy's, but the target's alpha becomes
    # srcA + dstA * (1 - srcA) instead of srcA + dstA, because SDL's software
    # renderer does not support SDL_ComposeCustomBlendMode
    discard SDL_SetRenderDrawBlendMode(sdl, SDL_BLENDMODE_BLEND)

proc sdlRenderer*(r: Renderer): SDL_Renderer {.inline.} =
  ## The SDL renderer drawn on.
  r.sdl

proc updateHeight(r: Renderer) =
  # The y flip needs the height of the current target.
  var w = 0.cint
  var h = 0.cint
  if SDL_GetCurrentRenderOutputSize(r.sdl, addr w, addr h):
    r.height = float32(h)

proc toSdl(r: Renderer; x, y: float32): SDL_FPoint {.inline.} =
  # Kivy's window coordinates (y up), translated, to SDL's (y down). The only
  # place where y is flipped.
  SDL_FPoint(x: x + r.tx, y: r.height - (y + r.ty))

proc clipOf(r: Renderer; b: Box): SDL_Rect =
  # The pixels whose centres are inside the box, as GL rasterizes the mask.
  if b.x0 > b.x1 or b.y0 > b.y1:
    return SDL_Rect(x: 0, y: 0, w: 0, h: 0)
  let i0 = ceil(b.x0 - 0.5)
  let i1 = ceil(b.x1 - 0.5)
  let j0 = ceil(b.y0 - 0.5)
  let j1 = ceil(b.y1 - 0.5)
  result = SDL_Rect(x: cint(i0), y: cint(float(r.height) - j1), w: cint(max(0.0, i1 - i0)),
    h: cint(max(0.0, j1 - j0)))

proc intersect(a, b: SDL_Rect): SDL_Rect =
  let x0 = max(a.x, b.x)
  let y0 = max(a.y, b.y)
  let x1 = min(a.x + a.w, b.x + b.w)
  let y1 = min(a.y + a.h, b.y + b.h)
  result = SDL_Rect(x: x0, y: y0, w: max(0.cint, x1 - x0), h: max(0.cint, y1 - y0))

proc setClip(r: Renderer) =
  # The clip of the innermost used stencil layer, or none.
  if r.clipStack.len == 0:
    discard SDL_SetRenderClipRect(r.sdl, nil)
  else:
    var rect = r.clipStack[r.clipStack.len - 1]
    discard SDL_SetRenderClipRect(r.sdl, addr rect)

proc addToMask(r: Renderer; v: VertexInstruction) =
  # Between StencilPush and StencilUse the drawing becomes the mask.
  # GAP: the mask is the bounding box of what is drawn between StencilPush
  # and StencilUse, exact for one Rectangle (all Kivy's own uses) but not
  # for other shapes or several rectangles, because SDL_Renderer has no
  # stencil buffer, only a clip rectangle
  for k in 0 ..< v.vertices.len:
    let vert = v.vertices[k]
    let x = float(vert.x + r.tx)
    let y = float(vert.y + r.ty)
    r.mask = Box(x0: min(r.mask.x0, x), y0: min(r.mask.y0, y), x1: max(r.mask.x1, x),
      y1: max(r.mask.y1, y))

proc drawColor(r: Renderer): SDL_FColor {.inline.} =
  # Kivy's fragment colour: color * vec4(1, 1, 1, opacity).
  SDL_FColor(r: float32(r.color[0]), g: float32(r.color[1]), b: float32(r.color[2]),
    a: float32(r.color[3] * r.opacity))

proc drawLineStrip(r: Renderer; v: VertexInstruction) =
  # GAP: a Line of width 1 is drawn with SDL_RenderLines where Kivy uses
  # GL_LINE_STRIP, so pixels can differ at the ends and on diagonals,
  # because SDL_Renderer has no GL line primitive
  let c = r.drawColor()
  r.points.setLen(0)
  for k in 0 ..< v.indices.len:
    let vert = v.vertices[v.indices[k]]
    # SDL's line and point coordinates name pixels (x is the pixel whose
    # centre is x + 0.5), where GL's are continuous like the triangles'.
    let p = r.toSdl(vert.x, vert.y)
    r.points.add SDL_FPoint(x: p.x - 0.5'f32, y: p.y - 0.5'f32)
  if r.points.len >= 2:
    discard SDL_SetRenderDrawColorFloat(r.sdl, c.r, c.g, c.b, c.a)
    discard SDL_RenderLines(r.sdl, addr r.points[0], cint(r.points.len))

proc drawTriangles(r: Renderer; v: VertexInstruction) =
  # The vertex batch as SDL_RenderGeometry triangles; a fan is expanded.
  # GAP: on SDL's software renderer, long thin triangles (wide lines) cover
  # up to a pixel more or less than GL's pixel-centre rule (graphics_line:
  # 0.91% of pixels differ, against 0.10% on the OpenGL renderer, which
  # matches GL), because SDL's software triangle rasterizer is less precise;
  # the scenes run on the OpenGL renderer
  if v.vertices.len == 0 or v.indices.len < 3:
    return
  let c = r.drawColor()
  r.vbuf.setLen(0)
  for k in 0 ..< v.vertices.len:
    let vert = v.vertices[k]
    r.vbuf.add SDL_Vertex(position: r.toSdl(vert.x, vert.y), color: c,
      tex_coord: SDL_FPoint(x: vert.s0, y: vert.t0))
  r.ibuf.setLen(0)
  case v.mode
  of vmTriangleFan:
    for k in 1 ..< v.indices.len - 1:
      r.ibuf.add cint(v.indices[0])
      r.ibuf.add cint(v.indices[k])
      r.ibuf.add cint(v.indices[k + 1])
  else:
    for k in 0 ..< v.indices.len - v.indices.len mod 3:
      r.ibuf.add cint(v.indices[k])
  var handle: nil SDL_Texture = nil
  let t = r.texture
  if t != nil:
    handle = t.handle(r.sdl)
    if handle != nil:
      discard SDL_SetTextureBlendMode(handle, r.blendMode)
  discard SDL_RenderGeometry(r.sdl, handle, addr r.vbuf[0], cint(r.vbuf.len),
    addr r.ibuf[0], cint(r.ibuf.len))

proc drawVertex(r: Renderer; v: VertexInstruction) =
  # VertexInstruction.apply: rebuild if flagged, then draw the batch.
  if v.needsRedraw:
    v.build()
    v.flagUpdateDone()
  case r.phase
  of spMask:
    r.addToMask(v)
  of spUnmask:
    discard     # erasing the mask: nothing to draw
  of spNone:
    if v.mode == vmLineStrip:
      r.drawLineStrip(v)
    elif v of AntiAliasingLine and r.color[3] < 1:
      # Kivy draws an AntiAliasingLine whose colour is translucent (the
      # colour's alpha, not the opacity) only outside its shape, through a
      # stencil.
      # GAP: translucent smooth shapes have hard edges, because SDL_Renderer
      # has no stencil
      discard
    else:
      # GAP: a wide Line drawn with alpha below 1 blends its overlapping
      # triangles (joints, caps) twice, where Kivy draws it once through a
      # stencil, because SDL_Renderer has no stencil buffer
      r.drawTriangles(v)

proc applyFbo(r: Renderer; f: Fbo)
proc applyFadeMix(r: Renderer; m: FadeMix)

proc apply(r: Renderer; i: Instruction) =
  # One instruction, as its Kivy `apply`.
  if i of Fbo:
    r.applyFbo(Fbo(i))
  elif i of FadeMix:
    r.applyFadeMix(FadeMix(i))
  elif i of VertexInstruction:
    r.drawVertex(VertexInstruction(i))
  elif i of Color:
    r.color = Color(i).rgba
  elif i of BindTexture:
    r.texture = BindTexture(i).texture
  elif i of Translate:
    let t = Translate(i)
    r.tx = r.tx + float32(t.x)
    r.ty = r.ty + float32(t.y)
  elif i of PushMatrix:
    r.matrixStack.add (r.tx, r.ty)
  elif i of PopMatrix:
    if r.matrixStack.len > 0:
      (r.tx, r.ty) = r.matrixStack.pop()
  elif i of StencilPush:
    r.phase = spMask
    r.mask = emptyBox()
  elif i of StencilUse:
    var clip = r.clipOf(r.mask)
    if r.clipStack.len > 0:
      clip = intersect(clip, r.clipStack[r.clipStack.len - 1])
    r.clipStack.add clip
    r.setClip()
    r.phase = spNone
  elif i of StencilUnUse:
    r.phase = spUnmask
  elif i of StencilPop:
    if r.clipStack.len > 0:
      discard r.clipStack.pop()
    r.setClip()
    r.phase = spNone
  elif i of InstructionGroup:
    let g = InstructionGroup(i)
    var opacity = 1.0
    if g of Canvas:
      opacity = Canvas(g).opacity
    # Canvas.apply: the opacity multiplies down the tree.
    if opacity != 1.0:
      r.opacityStack.add r.opacity
      r.opacity = r.opacity * opacity
    var k = 0
    while k < g.children.len:
      r.apply(g.children[k])
      inc k
    if opacity != 1.0:
      r.opacity = r.opacityStack.pop()
    g.flagUpdateDone()

proc draw*(r: Renderer; canvas: InstructionGroup) =
  ## Draws a canvas tree on the current target, starting from Kivy's
  ## initial render context state (white, opacity 1, no translation) as
  ## RenderContext.apply does each frame.
  r.updateHeight()
  r.color = [1.0, 1, 1, 1]
  r.opacity = 1
  r.opacityStack.setLen(0)
  r.tx = 0
  r.ty = 0
  r.matrixStack.setLen(0)
  r.texture = nil
  r.phase = spNone
  r.clipStack.setLen(0)
  r.setClip()
  r.apply(canvas)
  r.clipStack.setLen(0)
  r.setClip()

proc clear*(r: Renderer; rgba: array[4, float]) =
  ## Fills the current target with a colour (the window's clearcolor).
  discard SDL_SetRenderDrawColorFloat(r.sdl, float32(rgba[0]), float32(rgba[1]),
    float32(rgba[2]), float32(rgba[3]))
  discard SDL_RenderClear(r.sdl)

proc newRenderTarget*(r: Renderer; width, height: int): nil Texture =
  ## A texture to draw into with `setTarget`, or nil on failure. Its
  ## texture coordinates are flipped vertically, so that it is drawn
  ## upright as Kivy draws an Fbo's texture (SDL's first row is the top).
  let h = SDL_CreateTexture(r.sdl, SDL_PIXELFORMAT_RGBA32, SDL_TEXTUREACCESS_TARGET,
    cint(width), cint(height))
  if h == nil:
    return nil
  discard SDL_SetTextureScaleMode(h, SDL_SCALEMODE_LINEAR)
  let t = newTexture(r.sdl, h)
  t.flipVertical()
  result = t

proc setTarget*(r: Renderer; target: sink nil Texture): bool =
  ## Draws into `target` from now on (a texture from `newRenderTarget`), or
  ## into the window when nil; false on failure.
  if target == nil:
    result = SDL_SetRenderTarget(r.sdl, nil)
  else:
    result = SDL_SetRenderTarget(r.sdl, target.handle(r.sdl))
  if result:
    r.target = target

# ---------------------------------------------------------------- Fbo, FadeMix

proc newFbo*(width, height: int; clearColor: array[4, float]): Fbo =
  ## `Fbo(size=(width, height))` cleared to `clearColor` on each draw.
  Fbo(children: @[], width: width, height: height, clearColor: clearColor, texture: nil)

proc saveState(r: Renderer): RenderState =
  RenderState(target: r.target, height: r.height, color: r.color, opacity: r.opacity,
    opacityStack: r.opacityStack, tx: r.tx, ty: r.ty, matrixStack: r.matrixStack,
    texture: r.texture, phase: r.phase, mask: r.mask, clipStack: r.clipStack)

proc restoreState(r: Renderer; s: sink RenderState) =
  discard r.setTarget(s.target)
  r.height = s.height
  r.color = s.color
  r.opacity = s.opacity
  r.opacityStack = s.opacityStack
  r.tx = s.tx
  r.ty = s.ty
  r.matrixStack = s.matrixStack
  r.texture = s.texture
  r.phase = s.phase
  r.mask = s.mask
  r.clipStack = s.clipStack
  r.setClip()

proc applyFbo(r: Renderer; f: Fbo) =
  # Fbo.apply: when flagged (or new), bind the texture, clear it, draw the
  # children with Kivy's initial render context, and go back.
  var t = f.texture
  if t == nil or t.width != f.width or t.height != f.height:
    t = r.newRenderTarget(f.width, f.height)
    f.texture = t
    f.flagUpdate()
  if t != nil and f.needsRedraw:
    let saved = r.saveState()
    if r.setTarget(t):
      r.updateHeight()
      r.clipStack = @[]
      r.setClip()
      r.clear(f.clearColor)
      r.color = [1.0, 1, 1, 1]
      r.opacity = 1
      r.opacityStack = @[]
      r.tx = 0
      r.ty = 0
      r.matrixStack = @[]
      r.texture = nil
      r.phase = spNone
      var k = 0
      while k < f.children.len:
        r.apply(f.children[k])
        inc k
      r.restoreState(saved)
  f.flagUpdateDone()

proc newFadeMix*(fboOut, fboIn: sink Fbo; pos, size: (float, float)): FadeMix =
  ## The mix of the two textures in a rectangle at `pos` of `size`, at t 0.
  result = FadeMix(fboOut: fboOut, fboIn: fboIn, x: pos[0], y: pos[1], w: size[0],
    h: size[1], t: 0)
  result.flagUpdate()

proc t*(m: FadeMix): float {.inline.} =
  ## How far the mix is: 0 shows `out`, 1 shows `in`.
  m.t

proc `t=`*(m: FadeMix; t: float) =
  ## Sets how far the mix is (FadeTransition's `render_ctx['t']`).
  m.t = t
  m.flagUpdate()

proc applyFadeMix(r: Renderer; m: FadeMix) =
  # FadeTransition's shader, `mix(cout, cin, t)` written over the target, in
  # two copies: `out` times 1-t replacing what is there (its alpha is 1, as
  # the Fbo was cleared to opaque black, so Kivy's blending replaces too),
  # then `in` times t added.
  let tOut = m.fboOut.texture
  let tIn = m.fboIn.texture
  if tOut != nil and tIn != nil:
    let hOut = tOut.handle(r.sdl)
    let hIn = tIn.handle(r.sdl)
    if hOut != nil and hIn != nil:
      let topLeft = r.toSdl(float32(m.x), float32(m.y + m.h))
      var dst = SDL_FRect(x: topLeft.x, y: topLeft.y, w: float32(m.w), h: float32(m.h))
      let k = float32(1.0 - m.t)
      discard SDL_SetTextureBlendMode(hOut, SDL_BLENDMODE_NONE)
      discard SDL_SetTextureColorModFloat(hOut, k, k, k)
      discard SDL_SetTextureAlphaModFloat(hOut, 1)
      discard SDL_RenderTexture(r.sdl, hOut, nil, addr dst)
      discard SDL_SetTextureBlendMode(hIn, SDL_BLENDMODE_ADD)
      discard SDL_SetTextureColorModFloat(hIn, 1, 1, 1)
      discard SDL_SetTextureAlphaModFloat(hIn, float32(m.t))
      discard SDL_RenderTexture(r.sdl, hIn, nil, addr dst)
  m.flagUpdateDone()

proc readPixels*(r: Renderer): nil ptr SDL_Surface =
  ## The pixels of the current target in a new surface (free it with
  ## SDL_DestroySurface), or nil on failure.
  SDL_RenderReadPixels(r.sdl, nil)

proc present*(r: Renderer) =
  ## Shows the frame drawn on the window.
  discard SDL_RenderPresent(r.sdl)
