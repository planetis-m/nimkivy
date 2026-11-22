# Expected: compile error from the plugin at `canvas.before`: a canvas inside
# an `if` (the `if` goes inside the canvas).
import nimkivy/buildui
import nimkivy/uix/label
import nimkivy/graphics/context_instructions
proc main(framed: bool) =
  buildUi:
    Label() as l:
      if framed:
        canvas.before:
          Color(rgba = [1.0, 0, 0, 1])
main(true)
