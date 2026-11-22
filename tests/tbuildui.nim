# Tests nimkivy/buildui (DSL.md): a three-level tree of nimkivy widgets,
# `as` handles and unnamed widgets, positional and named arguments, a
# component called with its keyword arguments, a widget made before
# (a bare name and a dot path) and a plain call added as written; canvas
# instructions in canvas, canvas.before and canvas.after, following their
# widget through property handlers; handlers of an event with and without
# `: bool` (one that stops the dispatch), of an event not in the list, and
# of a property; their order; code lines among the widgets; and control
# flow (`if`, `case`, `for`, `when`, a handler and a canvas instruction
# inside it), evaluated once when the tree is built.

import std/[assertions, opt]
import nimkivy/[props, buildui]
import nimkivy/uix/[widget, boxlayout, label]
import nimkivy/graphics/[instructions, context_instructions, vertex_instructions]

properties:
  type
    Knob* = ref object of Widget
      ## A widget with events of its own.
      press* {.event.}: proc ()
      touch* {.event.}: proc (x, y: float)

  proc newKnob*(): Knob =
    result = Knob(canvas: newCanvas())
    result.initProps()
    result.initWidget()

type
  Holder = object
    box: BoxLayout

proc caption(text: string; bold = false): Label =
  # A component: a Label whose text is laid out in its own box.
  buildUi:
    label(text, halign = halignCenter) as l:
      l.bold = bold
      proc onSize(s: (float, float)) = l.textSize = s
  result = l

proc main() =
  var touches: seq[(float, float)] = @[]
  var widths: seq[float] = @[]
  var order: seq[string] = @[]
  var labels: seq[Label] = @[]
  var built = 0
  let header = newLabel("header")
  let holder = Holder(box: newBoxLayout())
  buildUi:
    boxLayout(orientation = orientationVertical) as root:
      canvas.before:
        color(rgba = [0.1, 0.2, 0.3, 1.0]) as paint
        rectangle(pos = root.pos, size = root.size) as rect
      canvas.after:
        line(width = 2) as edge
      proc onPos(v: (float, float)) = rect.pos = v
      proc onSize(v: (float, float)) = rect.size = v
      proc onSize(s: (float, float)) = edge.rectangle = [root.x, root.y, s[0], s[1]]
      header
      boxLayout(spacing = 4) as panel:
        label("volume") as title
        labels.add title
        newKnob() as go:
          proc onPress() =
            title.text = "pressed"
            order.add "first"
          proc onPress() = order.add "second"
          proc onTouch(x, y: float): bool =
            touches.add (x, y)
            result = x > 10
          proc onWidth(v: float) = widths.add v
        inc built
      caption("", bold = true) as footer
      holder.box
      newLabel("plain")
      widget()
  # The tree: Kivy's children are newest first.
  assert root.children.len == 6
  assert root.children[5] == WidgetBase(header) and root.children[4] == WidgetBase(panel)
  assert root.children[3] == WidgetBase(footer)
  assert root.children[2] == WidgetBase(holder.box)
  assert Label(root.children[1]).text == "plain"
  assert root.children[0] of Widget and root.children[0].children.len == 0
  assert panel.children == @[WidgetBase(go), WidgetBase(title)]
  assert root.orientation == orientationVertical and panel.spacing == 4
  assert title.text == "volume" and footer.halign == halignCenter and footer.bold
  assert labels == @[title] and built == 1
  # The canvas groups, each in order (a Rectangle comes with its
  # BindTexture), following the widget (handlers).
  assert root.canvas.before.indexof(paint) == 0 and root.canvas.before.indexof(rect) == 2
  assert root.canvas.after.indexof(edge) >= 0 and edge.width == 2
  assert paint.rgba == [0.1, 0.2, 0.3, 1.0]
  root.pos = (5.0, 6.0)
  root.size = (300.0, 200.0)
  assert rect.pos == (5.0, 6.0) and rect.size == (300.0, 200.0)
  # The component's own handler.
  footer.size = (120.0, 30.0)
  assert footer.textSize.w.get(0) == 120.0 and footer.textSize.h.get(0) == 30.0
  # Handlers: an event's run last bound first; an event not in the list and
  # a property's.
  discard go.dispatchPress()
  assert title.text == "pressed" and order == @["second", "first"]
  assert not go.dispatchTouch(1.0, 2.0)
  assert go.dispatchTouch(20.0, 3.0)     # the handler's result stops it
  assert touches == @[(1.0, 2.0), (20.0, 3.0)]
  go.width = 50
  assert widths == @[50.0]

proc conditional(home: bool; lang: int): BoxLayout =
  # Control flow in a block and in a canvas, evaluated once at build: a
  # handler and an instruction inside an `if`.
  var pressed = 0
  buildUi:
    boxLayout(spacing = 2) as box:
      canvas.before:
        color(rgba = [1.0, 0, 0, 1]) as first
        if home:
          color(rgba = [0.5, 0, 0, 1])
        color(rgba = [0.0, 0, 1, 1]) as last
      if home:
        newKnob() as homeButton:
          proc onPress() = inc pressed
        box.spacing = 8
        proc onSpacing(v: float) = inc pressed
      label("logo") as logo
      case lang
      of 0:
        label("en")
      of 1:
        label("el")
        box.padding = [1.0, 1, 1, 1]
      else:
        for i in 0 ..< 2:
          widget()
      when false:
        label("never")
  assert box.canvas.before.indexof(first) == 0
  assert box.canvas.before.indexof(last) == (if home: 2 else: 1)
  if home:
    let homeButton = Knob(box.children[^1])
    assert box.children[^2] == WidgetBase(logo)
    assert box.spacing == 8
    discard homeButton.dispatchPress()
    assert pressed == 1
    box.spacing = 3                      # the handler inside the `if`
    assert pressed == 2
  else:
    assert box.children[^1] == WidgetBase(logo) and box.spacing == 2
  let after = box.children.len - (if home: 2 else: 1)
  case lang
  of 0: assert after == 1 and Label(box.children[0]).text == "en"
  of 1:
    assert after == 1 and Label(box.children[0]).text == "el"
    assert box.padding == [1.0, 1, 1, 1]
  else: assert after == 2
  result = box

main()
for home in [false, true]:
  for lang in 0 .. 2:
    discard conditional(home, lang)
