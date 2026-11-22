# Expected: compile error at the handler: `touchDown` takes a MotionEvent,
# not a float.
import nimkivy/buildui
import nimkivy/uix/label
proc main() =
  var n = 0
  buildUi:
    Label() as l:
      on touchDown(x: float):
        inc n
main()
