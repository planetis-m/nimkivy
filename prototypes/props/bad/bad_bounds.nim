# Expected: the program stops (exit code 1) when a value is out of bounds,
# where Kivy's BoundedNumericProperty raises ValueError.
import ../widgets
let w = newWidget()
w.opacity = 1.5
