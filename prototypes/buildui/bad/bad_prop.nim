# Expected: compile error, Label has no property `txt`.
import ../ui
proc main() =
  buildUi:
    Label(txt = "x") as l
main()
