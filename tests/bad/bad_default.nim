# Expected: compile error, a default override for a property that does not
# exist (`opacty`).
import ../propwidgets
properties:
  type
    Faded* {.defaults: (opacty: 0.5).} = ref object of Widget
