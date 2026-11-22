# Expected: compile error from the plugin at `echo`: a statement that is
# not a widget, a property, a binding, a handler or a canvas.
import std/syncio
import nimkivy/buildui
import nimkivy/uix/label
proc main() =
  buildUi:
    Label() as l:
      echo "no"
main()
