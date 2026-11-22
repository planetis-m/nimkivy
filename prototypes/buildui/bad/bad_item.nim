# Expected: compile error from the plugin: a statement that is not a
# widget, a property, a binding or a handler.
import std/syncio
import ../ui
proc main() =
  buildUi:
    Label() as l:
      echo "no"
main()
