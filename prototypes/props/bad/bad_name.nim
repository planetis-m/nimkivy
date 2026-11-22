# Expected: compile error, no such property (`opacty`).
import ../widgets
let w = newWidget()
w.opacty = 0.5
