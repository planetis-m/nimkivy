# Expected: compile error at the binding: it reads `title.txt`, which does
# not exist.
import nimkivy/buildui
import nimkivy/uix/[boxlayout, label]
proc main() =
  buildUi:
    BoxLayout() as root:
      Label() as title
      Label() as footer:
        text <- title.txt & "!"
main()
