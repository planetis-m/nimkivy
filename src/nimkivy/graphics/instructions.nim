## Graphics instructions: Kivy's `kivy/graphics/instructions.pyx`
## (Instruction, InstructionGroup, ContextInstruction, VertexInstruction,
## CanvasBase, Canvas), plus `BindTexture` from `context_instructions.pyx`,
## which every vertex instruction owns and which Python could import
## circularly but a Nim module cannot.
##
## A canvas is a list of instructions, drawn in order: `before`, then its own
## children (a child widget's canvas is one of them), then `after`. A vertex
## instruction is stored as two entries, its BindTexture and itself, as in
## Kivy, so `indexof` and `length` count the same. Changing an instruction
## flags it and its parents for update (`needsRedraw`); the renderer rebuilds
## flagged vertex instructions and clears the flags.
##
## There is no `with canvas:` (the active canvas): instructions are added with
## `add` or `insert`. The graphics compiler (`compiler.pyx`), which only skips
## redundant context instructions, is not ported.

import std/[assertions, sequtils]
import texture

type
  Instruction* = ref object of RootObj
    ## The smallest instruction. instructions.pyx Instruction
    parent: nil InstructionGroup
    needsUpdate: bool               # GI_NEEDS_UPDATE
    noRemove: bool                  # GI_NO_REMOVE: `clear` keeps it

  InstructionGroup* = ref object of Instruction
    ## A list of instructions. instructions.pyx InstructionGroup
    children*: seq[Instruction]     ## the instructions, in drawing order

  CanvasBase* = ref object of InstructionGroup
    ## A group used as `canvas.before` or `canvas.after`.

  Canvas* = ref object of CanvasBase
    ## A widget's canvas: a group with `before`, `after` and `opacity`.
    opacity: float32
    before, after: nil CanvasBase

  ContextInstruction* = ref object of Instruction
    ## An instruction that changes the drawing state (colour, matrix, texture).

  BindTexture* = ref object of ContextInstruction
    ## Binds the texture the next vertex instruction draws with; nil is
    ## Kivy's default texture (one white pixel), which leaves the colour
    ## unchanged. context_instructions.pyx BindTexture
    texture: nil Texture
    source: string

  VertexMode* = enum
    ## How `indices` make primitives (Kivy's VertexBatch modes).
    vmTriangles     ## every three indices are a triangle
    vmTriangleFan   ## indices[0] and each next pair are a triangle
    vmLineStrip     ## a polyline through the indices

  Vertex* = object
    ## One vertex in Kivy's coordinates (y up), with its texture coordinates.
    ## vertex.pxd vertex_t
    x*, y*, s0*, t0*: float32

  VertexInstruction* = ref object of Instruction
    ## An instruction with a visual representation. Its BindTexture is
    ## added to the canvas right before it. Subtypes compute `vertices` and
    ## `indices` in `build`, as Kivy's `build` fills its VertexBatch.
    textureBinding*: BindTexture    ## added to the canvas with the
                                    ## instruction; constructors set it to
                                    ## `newBindTexture()`
    texCoords: array[8, float32]
    vertices*: seq[Vertex]          ## the built vertices
    indices*: seq[int32]            ## the built indices into `vertices`
    mode*: VertexMode               ## how `indices` are drawn

const DefaultTexCoords = [0'f32, 0, 1, 0, 1, 1, 0, 1]

# ---------------------------------------------------------------- Instruction

proc flagUpdate*(i: Instruction) =
  ## Marks `i` and its parents for update (Kivy's `flag_update` and
  ## `flag_data_update`).
  var cur: nil Instruction = i
  while cur != nil:
    cur.needsUpdate = true
    cur = cur.parent

proc flagUpdateDone*(i: Instruction) {.inline.} =
  ## Clears the update mark; the renderer calls it after drawing `i`.
  i.needsUpdate = false

proc needsRedraw*(i: Instruction): bool {.inline.} =
  ## Whether `i` changed since it was last drawn. The window draws a frame
  ## only when its canvas needs a redraw.
  i.needsUpdate

proc parent*(i: Instruction): nil InstructionGroup {.inline.} =
  ## The group `i` is in, or nil.
  i.parent

proc pyInsert[T](s: var seq[T]; index: int; x: T) =
  # Python's list.insert: a negative index counts from the end, and an index
  # out of range is clamped.
  var i = index
  if i < 0:
    i = max(0, s.len + i)
  elif i > s.len:
    i = s.len
  s.insert([x], i)

proc pyRemove(s: var seq[Instruction]; x: Instruction) =
  # Python's list.remove for an instruction (identity): the first one.
  let i = s.find(x)
  if i >= 0:
    s.delete(i)

method radd*(i: Instruction; ig: InstructionGroup) {.base.} =
  ## Appends `i` to `ig`'s children (Kivy's `radd`).
  ig.children.add i
  i.parent = ig

method rinsert*(i: Instruction; ig: InstructionGroup; index: int) {.base.} =
  ## Inserts `i` into `ig`'s children at a Python index (Kivy's `rinsert`).
  ig.children.pyInsert(index, i)
  i.parent = ig

method rremove*(i: Instruction; ig: InstructionGroup) {.base.} =
  ## Removes `i` from `ig`'s children (Kivy's `rremove`).
  if i.parent != nil:
    ig.children.pyRemove(i)
    i.parent = nil

# ---------------------------------------------------------------- InstructionGroup

proc newInstructionGroup*(): InstructionGroup =
  ## An empty group.
  InstructionGroup(parent: nil, children: @[])

proc add*(ig: InstructionGroup; c: Instruction) =
  ## Appends an instruction. instructions.pyx InstructionGroup.add; for a
  ## Canvas, see the `add` below.
  c.radd(ig)
  ig.flagUpdate()

proc insert*(ig: InstructionGroup; index: int; c: Instruction) =
  ## Inserts an instruction at a Python index.
  c.rinsert(ig, index)
  ig.flagUpdate()

proc remove*(ig: InstructionGroup; c: Instruction) =
  ## Removes an instruction.
  c.rremove(ig)
  ig.flagUpdate()

proc indexof*(ig: InstructionGroup; c: Instruction): int =
  ## The index of `c` in the children, or -1.
  result = ig.children.find(c)

proc length*(ig: InstructionGroup): int {.inline.} =
  ## The number of children (a vertex instruction counts two).
  ig.children.len

proc clear*(ig: InstructionGroup) =
  ## Removes every instruction (InstructionGroup.clear).
  let snapshot = ig.children    # Kivy iterates over a copy
  for c in snapshot:
    if not c.noRemove:
      ig.remove(c)

# ---------------------------------------------------------------- Canvas

proc newCanvasBase*(): CanvasBase =
  ## An empty group for `before` or `after`.
  CanvasBase(parent: nil, children: @[])

proc newCanvas*(): Canvas =
  ## An empty canvas with opacity 1.
  Canvas(parent: nil, children: @[], opacity: 1, before: nil, after: nil)

proc add*(c: Canvas; i: Instruction) =
  ## Appends an instruction, before the `after` group if there is one.
  ## instructions.pyx Canvas.add
  if c.after == nil:
    i.radd(c)
  else:
    i.rinsert(c, -1)
  c.flagUpdate()

proc clear*(c: Canvas) =
  ## Removes every instruction except `before` and `after`. Canvas.clear
  let snapshot = c.children
  for i in snapshot:
    if i != Instruction(c.before) and i != Instruction(c.after) and not i.noRemove:
      c.remove(i)

proc before*(c: Canvas): CanvasBase =
  ## The group drawn before the canvas, created at index 0 on first use.
  if c.before == nil:
    let b = newCanvasBase()
    c.insert(0, b)
    c.before = b
  let b = c.before
  assert b != nil
  result = b

proc after*(c: Canvas): CanvasBase =
  ## The group drawn after the canvas, created on first use; it stays last.
  if c.after == nil:
    let a = newCanvasBase()
    c.add(a)
    c.after = a
  let a = c.after
  assert a != nil
  result = a

proc hasBefore*(c: Canvas): bool {.inline.} =
  ## Whether `before` was created.
  c.before != nil

proc hasAfter*(c: Canvas): bool {.inline.} =
  ## Whether `after` was created.
  c.after != nil

proc opacity*(c: Canvas): float {.inline.} =
  ## The opacity; it multiplies down the canvas tree.
  float(c.opacity)

proc `opacity=`*(c: Canvas; value: float) =
  ## Sets the opacity.
  c.opacity = float32(value)
  c.flagUpdate()

proc askUpdate*(c: Canvas) =
  ## Asks for a redraw on the next frame.
  c.flagUpdate()

# ---------------------------------------------------------------- BindTexture

proc newBindTexture*(): BindTexture =
  ## A BindTexture of the default texture.
  # Created with `noadd`, so it has GI_NO_REMOVE: `clear` leaves it to its
  # vertex instruction's `rremove`.
  BindTexture(parent: nil, noRemove: true, texture: nil, source: "")

proc texture*(b: BindTexture): nil Texture {.inline.} =
  ## The bound texture; nil is the default texture.
  b.texture

proc `texture=`*(b: BindTexture; t: nil Texture) =
  ## Sets the bound texture.
  if b.texture != t:
    b.texture = t
    b.flagUpdate()

proc source*(b: BindTexture): string {.inline.} =
  ## The file the texture was loaded from ("" when none).
  b.source

proc `source=`*(b: BindTexture; filename: string) =
  ## Records the file name. Loading it is `core/image`'s `source=`, because
  ## a graphics module cannot import the image loader above it.
  b.source = filename

# ---------------------------------------------------------------- VertexInstruction

proc initVertexInstruction*(v: VertexInstruction; mode: VertexMode) =
  ## Sets up a new vertex instruction's texture coordinates and geometry.
  ## Subtype constructors create the object with
  ## `textureBinding: newBindTexture()`, then call it. instructions.pyx
  ## VertexInstruction.__init__
  v.texCoords = DefaultTexCoords
  v.vertices = @[]
  v.indices = @[]
  v.mode = mode

method radd*(v: VertexInstruction; ig: InstructionGroup) =
  ## Appends the BindTexture, then the instruction.
  ig.children.add v.textureBinding
  ig.children.add v
  v.textureBinding.parent = ig
  v.parent = ig

method rinsert*(v: VertexInstruction; ig: InstructionGroup; index: int) =
  ## Inserts the BindTexture, then the instruction at the same index. As in
  ## Kivy, the instruction ends up before its BindTexture when the index is
  ## not negative, and then draws with the texture bound before it.
  ig.children.pyInsert(index, Instruction(v.textureBinding))
  ig.children.pyInsert(index, Instruction(v))
  v.textureBinding.parent = ig
  v.parent = ig

method rremove*(v: VertexInstruction; ig: InstructionGroup) =
  ## Removes the BindTexture and the instruction.
  ig.children.pyRemove(v.textureBinding)
  ig.children.pyRemove(v)
  v.textureBinding.parent = nil
  v.parent = nil

method build*(v: VertexInstruction) {.base.} =
  ## Computes `vertices` and `indices` (Kivy's `build`). The renderer calls
  ## it before drawing a flagged instruction.
  discard

proc texture*(v: VertexInstruction): nil Texture {.inline.} =
  ## The texture drawn with; nil is the default texture.
  v.textureBinding.texture

proc `texture=`*(v: VertexInstruction; t: nil Texture) =
  ## Sets the texture, and the texture coordinates to the texture's.
  ## instructions.pyx VertexInstruction.texture
  v.textureBinding.texture = t
  if t != nil:
    v.texCoords = t.texCoords
  else:
    v.texCoords = DefaultTexCoords
  v.flagUpdate()

proc source*(v: VertexInstruction): string {.inline.} =
  ## The file the texture was loaded from ("" when none).
  v.textureBinding.source

proc texCoords*(v: VertexInstruction): array[8, float32] {.inline.} =
  ## The texture coordinates of the four corners.
  v.texCoords

proc `texCoords=`*(v: VertexInstruction; tc: array[8, float32]) =
  ## Sets the texture coordinates.
  v.texCoords = tc
  v.flagUpdate()
