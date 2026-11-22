# Tests nimkivy/buildui (REDESIGN.md, buildUi): a three-level tree of
# nimkivy widgets, `as` handles and unnamed widgets, constructor arguments
# and a component, canvas instructions bound to their widget (`self`),
# bindings to a property of an object outside the tree and of a sibling,
# a read that is not a property (evaluated, not followed), handlers with
# and without parameters, one that stops the dispatch, one of an owned
# ButtonBehavior and two of a property; generated callback parameters do
# not hide the caller's names; and the update model: the tree is built once
# and the bindings keep it current. The rejected programs are
# tests/bad/bad_ui_*.nim (run_tests.sh).

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
        text <- topic.title & " (" & $topic.index & ") " & $topic.views
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

main()
