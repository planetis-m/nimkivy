# Expected: compile error from the plugin at the second widget: a tree has
# one root.
import nimkivy/buildui
import nimkivy/uix/label
proc main() =
  buildUi:
    Label() as a
    Label() as b
main()
