# Expected: compile error, no such property (`opacty`).
import ../propwidgets
let w = newWidget()
w.opacty = 0.5
