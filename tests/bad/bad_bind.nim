# Expected: compile error, no such property to bind (`bindOpacty`), and a
# callback of the wrong type for `bindOpacity`.
import ../propwidgets
let w = newWidget()
discard w.bindOpacty(proc (v: float) {.closure.} = discard)
discard w.bindOpacity(proc (v: string) {.closure.} = discard)
