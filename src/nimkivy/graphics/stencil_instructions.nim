## Stencil instructions: Kivy's `kivy/graphics/stencil_instructions.pyx`,
## as clip rectangles.
##
## Kivy draws the instructions between StencilPush and StencilUse into the
## stencil buffer as a mask, clips what follows StencilUse to it, and erases
## the mask again between StencilUnUse and StencilPop. Nested masks
## intersect. nimkivy has no stencil buffer: the renderer takes the Rectangle
## drawn between StencilPush and StencilUse as a clip rectangle, intersects
## it with the enclosing one, skips the drawing between StencilUnUse and
## StencilPop, and restores the enclosing clip at StencilPop. Kivy's own uses
## (Image and ScreenManager in `style.kv`) mask with one Rectangle.

import instructions

type
  StencilPush* = ref object of Instruction
    ## Starts a mask: what follows, up to StencilUse, is the mask.
  StencilUse* = ref object of Instruction
    ## Clips what follows to the mask.
  StencilUnUse* = ref object of Instruction
    ## Stops clipping: what follows, up to StencilPop, erases the mask.
  StencilPop* = ref object of Instruction
    ## Ends the mask and restores the enclosing one.

proc newStencilPush*(): StencilPush =
  ## `StencilPush()`. `clear_stencil` has no counterpart (no stencil buffer).
  StencilPush()

proc newStencilUse*(): StencilUse =
  ## `StencilUse()` with Kivy's default `func_op` 'equal'; other operators
  ## are out of scope.
  StencilUse()

proc newStencilUnUse*(): StencilUnUse =
  ## `StencilUnUse()`.
  StencilUnUse()

proc newStencilPop*(): StencilPop =
  ## `StencilPop()`.
  StencilPop()
