# Tests nimkivy/buildui (REDESIGN.md, buildUi): a three-level tree of
# nimkivy widgets, `as` handles and unnamed widgets, constructor arguments
# and a component, canvas instructions bound to their widget (`self`),
# bindings to a property of an object outside the tree and of a sibling,
# a method call (evaluated, not followed), handlers with
# and without parameters, one that stops the dispatch, one of an owned
# ButtonBehavior and two of a property; generated callback parameters do
# not hide the caller's names; and the update model: the tree is built once
# and the bindings keep it current; `if` items (children, the widget's own
# items, a canvas instruction, nested, each condition evaluated once) and
# `place` (existing widgets and an instruction, with and without a block).
# The rejected programs are tests/bad/bad_ui_*.nim (run_tests.sh).

import std/[assertions, opt]
import nimkivy/[props, buildui]
import nimkivy/uix/[widget, boxlayout, label]
import nimkivy/uix/behaviors/button
import nimkivy/graphics/[instructions, context_instructions, vertex_instructions]

properties:
  type
    Slider* = ref object of Widget
      value* {.bounds: 0.0 .. 1.0.}: float = 0.0
    Knob* = ref object of Widget
      ## A widget with events of its own and an owned ButtonBehavior.
      button*: ButtonBehavior
      press* {.event.}: proc ()
      touch* {.event.}: proc (x, y: float)
    Topic* = ref object of RootObj
      ## Something the tree shows that is not a widget.
      title* {.prop.}: string = ""
      index* {.prop.}: int = 0
      views*: int                ## a plain field

  proc viewCount*(t: Topic): int = t.views

  proc newSlider*(): Slider =
    result = Slider(canvas: newCanvas())
    result.initProps()
    result.initWidget()

  proc newKnob*(): Knob =
    result = Knob(canvas: newCanvas(), button: newButtonBehavior())
    result.initProps()
    result.initWidget()

  proc newTopic*(title: string): Topic =
    result = Topic(views: 0)
    result.initProps()
    result.title = title

proc newCaption(text: string): Label =
  # A component: a Label whose text is laid out in its own box.
  buildUi:
    Label(text, halign = halignCenter) as l:
      textSize <- self.size
  result = l

proc main() =
  let slider = newSlider()
  let topic = newTopic("Figs")
  var touches: seq[(float, float)] = @[]
  var released = 0
  var widths: seq[float] = @[]
  var seen: seq[string] = @[]
  let v = "!"                    # a binding's callback does not hide it
  buildUi:
    BoxLayout(orientation = orientationVertical) as root:
      canvas.before:
        Color(rgba = [0.1, 0.2, 0.3, 1.0]) as paint
        Rectangle(pos <- self.pos, size <- self.size) as rect
      BoxLayout(spacing = 4) as panel:
        Label("volume") as title:
          opacity <- slider.value
        Knob() as go:
          on press:
            title.text = "pressed"
          on touch(x, y: float):
            touches.add (x, y)
            result = x > 10
          on button.release:
            inc released
          on width(v: float):
            widths.add v
          on height:                 # the value unnamed: `v` is main's
            seen.add v
      Caption("") as footer:
        text <- title.text & v
      Label as heading:
        text <- topic.title & " (" & $topic.index & ") " & $topic.viewCount()
      Widget()
  # The tree: Kivy's children are newest first.
  assert root.children.len == 4
  assert root.children[3] == WidgetBase(panel) and root.children[2] == WidgetBase(footer)
  assert root.children[1] == WidgetBase(heading)
  assert root.children[0] of Widget and root.children[0].children.len == 0
  assert panel.children == @[WidgetBase(go), WidgetBase(title)]
  assert root.orientation == orientationVertical and panel.spacing == 4
  assert title.text == "volume" and footer.halign == halignCenter
  # The canvas instructions, in canvas.before (a Rectangle comes with its
  # BindTexture), follow the widget.
  assert root.canvas.before.indexof(paint) == 0 and root.canvas.before.indexof(rect) == 2
  assert paint.rgba == [0.1, 0.2, 0.3, 1.0]
  assert rect.pos == root.pos and rect.size == root.size
  root.pos = (5.0, 6.0)
  root.size = (300.0, 200.0)
  assert rect.pos == (5.0, 6.0) and rect.size == (300.0, 200.0)
  # The component's own binding (`self`).
  footer.size = (120.0, 30.0)
  assert footer.textSize.w.get(0) == 120.0 and footer.textSize.h.get(0) == 30.0
  # The bindings were evaluated once at build.
  assert title.opacity == 0.0
  assert footer.text == "volume!"
  assert heading.text == "Figs (0) 0"
  # They keep the tree current, without building it again.
  slider.value = 0.75
  assert title.opacity == 0.75
  topic.index = 2
  assert heading.text == "Figs (2) 0"
  topic.views = 5                # not a property: read, not followed
  assert heading.text == "Figs (2) 0"
  topic.title = "Crete"
  assert heading.text == "Crete (2) 5"
  assert root.children[3] == WidgetBase(panel) and panel.children[1] == WidgetBase(title)
  # Handlers; the change one makes reaches the bound footer.
  discard go.dispatchPress()
  assert title.text == "pressed"
  assert footer.text == "pressed!"
  assert not go.dispatchTouch(1.0, 2.0)
  assert go.dispatchTouch(20.0, 3.0)     # the handler's result stops it
  assert touches == @[(1.0, 2.0), (20.0, 3.0)]
  discard go.button.dispatchRelease()
  assert released == 1
  go.width = 50
  assert widths == @[50.0]
  go.height = 40
  assert seen == @["!"]

proc conditional(home: bool; lang: int; checks: var int): BoxLayout =
  # `if` items, evaluated once when the tree is built: children, the
  # widget's own items, a canvas instruction, a nested `if`, `self` in a
  # condition and a name declared in an arm used in the same arm.
  proc counted(v: bool; checks: var int): bool =
    inc checks
    result = v
  let topic = newTopic("Figs")
  var pressed = 0
  buildUi:
    BoxLayout(spacing = 2) as box:
      canvas.before:
        Color(rgba = [1.0, 0, 0, 1]) as first
        if home:
          Color(rgba <- [self.x, 0, 0, 1]) as middle
        Color(rgba = [0.0, 0, 1, 1]) as last
      if counted(home, checks):
        Knob() as homeButton:
          on press:
            inc pressed
            homeButton.opacity = 0.5
        spacing = 8
        on spacing:
          inc pressed
      Label("logo") as logo
      if lang == 0:
        Label("en")
      elif lang == 1:
        Label("el"):
          text <- topic.title & "!"
        if self.spacing == 2:
          padding = [1.0, 1, 1, 1]
      else:
        Widget()
        Widget()
  # The instructions, in order: the conditional one between the others.
  assert box.canvas.before.indexof(first) == 0
  assert box.canvas.before.indexof(last) == (if home: 2 else: 1)
  # The home button first, before the logo.
  assert (if home: box.children[^1] of Knob else: box.children[^1] == WidgetBase(logo))
  if home:
    let homeButton = Knob(box.children[^1])
    assert box.children[^2] == WidgetBase(logo)
    assert box.spacing == 8
    discard homeButton.dispatchPress()
    assert pressed == 1 and homeButton.opacity == 0.5
    box.x = 0.25                 # the conditional instruction's binding
    let middle = Color(box.canvas.before.children[1])
    assert middle.rgba == [0.25, 0.0, 0.0, 1.0]
  else:
    assert box.spacing == 2
  # The language's item: one Label, a bound one, or two Widgets.
  let after = box.children.len - (if home: 2 else: 1)
  case lang
  of 0:
    assert after == 1 and Label(box.children[0]).text == "en"
    assert box.padding == [0.0, 0, 0, 0]
  of 1:
    assert after == 1 and Label(box.children[0]).text == "Figs!"
    topic.title = "Crete"
    assert Label(box.children[0]).text == "Crete!"
    assert box.padding == (if home: [0.0, 0, 0, 0] else: [1.0, 1, 1, 1])
  else:
    assert after == 2
  result = box

proc newHeaderBox(): BoxLayout =
  # A widget built separately, to be placed in another tree.
  buildUi:
    BoxLayout as h:
      Label("header")
  result = h

proc placed() =
  # `place`: existing widgets (and an instruction) at their place in a tree,
  # with or without `as name` and items of their own.
  let header = newHeaderBox()
  let paint = newColor(0.0, 1.0, 0.0)
  let slider = newSlider()
  var pressed = 0
  buildUi:
    BoxLayout(orientation = orientationVertical) as root:
      canvas:
        place paint
      Label("top")
      place header
      place newKnob() as knob:
        opacity <- slider.value
        on press:
          inc pressed
        Label("in the knob")
      if pressed == 0:
        place newSlider() as inner:
          value = 0.5
  assert root.children.len == 4
  assert root.children[2] == WidgetBase(header) and header.parent == WidgetBase(root)
  assert root.children[1] == WidgetBase(knob) and knob.children.len == 1
  assert root.children[0] of Slider and Slider(root.children[0]).value == 0.5
  assert root.canvas.indexof(paint) >= 0
  assert knob.opacity == 0.0
  slider.value = 0.25
  assert knob.opacity == 0.25
  discard knob.dispatchPress()
  assert pressed == 1

main()
for home in [false, true]:
  for lang in 0 .. 2:
    var checks = 0
    let box = conditional(home, lang, checks)
    assert checks == 1           # each condition evaluated once
    box.spacing = 3              # nothing is rebuilt
    assert checks == 1
placed()
