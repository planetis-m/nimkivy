# Expected: compile error at `txt`: Label has no property `txt`.
import nimkivy/buildui
import nimkivy/uix/label
proc main() =
  buildUi:
    Label(txt = "x") as l
main()
