# Expected: compile error, the binding reads `slider.valu`, which is not a
# property (no `bindValu`).
import ../ui
proc main() =
  let slider = newSlider()
  buildUi:
    Label() as l:
      opacity <- slider.valu
main()
