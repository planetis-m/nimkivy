## Context instructions: the part of Kivy's
## `kivy/graphics/context_instructions.pyx` that nimkivy uses: Color,
## PushMatrix, PopMatrix and a 2D Translate. BindTexture is in
## `instructions`, because every vertex instruction owns one.
##
## Color sets the colour state for the vertex instructions drawn after it, in
## the whole canvas tree, until the next Color (Kivy keeps it in the render
## context, not per canvas). PushMatrix and PopMatrix save and restore the
## translation, which Translate moves. Out of scope (SCOPE.md): HSV, Rotate,
## Scale, MatrixInstruction, LoadIdentity, PushState and the other stacks.

import instructions

type
  Color* = ref object of ContextInstruction
    ## The colour state. context_instructions.pyx Color
    rgba: array[4, float]

  PushMatrix* = ref object of ContextInstruction
    ## Saves the translation. context_instructions.pyx PushMatrix

  PopMatrix* = ref object of ContextInstruction
    ## Restores the translation saved by the last PushMatrix.

  Translate* = ref object of ContextInstruction
    ## Moves the drawing origin by (x, y). context_instructions.pyx Translate
    x, y: float

proc newColor*(r, g, b: float; a = 1.0): Color =
  ## `Color(r, g, b)` or `Color(r, g, b, a)`; three values get alpha 1.
  result = Color(rgba: [r, g, b, a])
  result.flagUpdate()

proc newColor*(): Color =
  ## `Color()`: white.
  result = newColor(1.0, 1.0, 1.0, 1.0)

proc rgba*(c: Color): array[4, float] {.inline.} =
  ## The colour, 4 values (Kivy does not clamp them).
  c.rgba

proc `rgba=`*(c: Color; rgba: array[4, float]) =
  ## Sets the colour.
  c.rgba = rgba
  c.flagUpdate()

proc rgb*(c: Color): array[3, float] {.inline.} =
  ## The colour without alpha.
  [c.rgba[0], c.rgba[1], c.rgba[2]]

proc `rgb=`*(c: Color; rgb: array[3, float]) =
  ## Sets red, green and blue, keeping alpha.
  c.rgba = [rgb[0], rgb[1], rgb[2], c.rgba[3]]

proc r*(c: Color): float {.inline.} =
  ## Red.
  c.rgba[0]

proc g*(c: Color): float {.inline.} =
  ## Green.
  c.rgba[1]

proc b*(c: Color): float {.inline.} =
  ## Blue.
  c.rgba[2]

proc a*(c: Color): float {.inline.} =
  ## Alpha.
  c.rgba[3]

proc `r=`*(c: Color; v: float) =
  ## Sets red.
  c.rgba = [v, c.g, c.b, c.a]

proc `g=`*(c: Color; v: float) =
  ## Sets green.
  c.rgba = [c.r, v, c.b, c.a]

proc `b=`*(c: Color; v: float) =
  ## Sets blue.
  c.rgba = [c.r, c.g, v, c.a]

proc `a=`*(c: Color; v: float) =
  ## Sets alpha.
  c.rgba = [c.r, c.g, c.b, v]

proc newPushMatrix*(): PushMatrix =
  ## `PushMatrix()` of the modelview matrix.
  PushMatrix()

proc newPopMatrix*(): PopMatrix =
  ## `PopMatrix()` of the modelview matrix.
  PopMatrix()

proc newTranslate*(x = 0.0; y = 0.0): Translate =
  ## `Translate(x, y)`.
  result = Translate(x: x, y: y)
  result.flagUpdate()

proc x*(t: Translate): float {.inline.} =
  ## The translation along x.
  t.x

proc y*(t: Translate): float {.inline.} =
  ## The translation along y.
  t.y

proc xy*(t: Translate): (float, float) {.inline.} =
  ## The translation.
  (t.x, t.y)

proc `x=`*(t: Translate; x: float) =
  ## Sets the translation along x.
  t.x = x
  t.flagUpdate()

proc `y=`*(t: Translate; y: float) =
  ## Sets the translation along y.
  t.y = y
  t.flagUpdate()

proc `xy=`*(t: Translate; xy: (float, float)) =
  ## Sets the translation.
  t.x = xy[0]
  t.y = xy[1]
  t.flagUpdate()
