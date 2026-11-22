## Tests of the buildUi prototype: a three-level tree, `as` handles, a
## binding to a property of an object outside the tree and one inside it,
## an event handler with and without arguments, and the update model (the
## tree is built once; bindings keep it current).

import std/[syncio, assertions]
import ui

proc main() =
  let slider = newSlider()
  var touches: seq[(float, float)] = @[]
  buildUi:
    Widget(name = "root") as root:
      Widget(name = "panel") as panel:
        Label(text = "volume") as title:
          opacity <- slider.value
        Button(text = "Go") as go:
          on press:
            title.text = "pressed"
          on touch(x, y: float):
            touches.add (x, y)
      Label(name = "footer") as footer:
        text <- title.text & "!"
      Widget()
  # the tree
  assert root.children.len == 3
  assert root.children[0] == WidgetBase(panel) and root.children[1] == WidgetBase(footer)
  assert panel.children.len == 2
  assert panel.children[0] == WidgetBase(title) and panel.children[1] == WidgetBase(go)
  assert root.children[2] of Widget and root.children[2].children.len == 0
  assert go.text == "Go" and panel.name == "panel"
  # bindings were evaluated once at build
  assert title.opacity == 0.0
  assert footer.text == "volume!"
  # and keep the tree current, without building it again
  slider.value = 0.75
  assert title.opacity == 0.75
  assert root.children[0] == WidgetBase(panel) and panel.children[0] == WidgetBase(title)
  # an event handler; the change it makes reaches the bound footer
  discard go.dispatchPress()
  assert title.text == "pressed"
  assert footer.text == "pressed!"
  discard go.dispatchTouch(1.0, 2.0)
  assert touches == @[(1.0, 2.0)]
  echo "tbuildui: ok"

main()
