# Expected: compile error at the handler: Label has no event `presss`.
import nimkivy/buildui
import nimkivy/uix/label
proc main() =
  var n = 0
  buildUi:
    Label() as l:
      on presss:
        inc n
main()
