# Expected: compile error from the plugin at the value: a binding that
# reads nothing is a value set once.
import nimkivy/buildui
import nimkivy/uix/label
proc main() =
  buildUi:
    Label() as l:
      text <- "figs"
main()
