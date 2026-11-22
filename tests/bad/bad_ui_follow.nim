# Expected: compile error at the binding: `topic.name` is a plain field, so
# the binding would never update.
import nimkivy/buildui
import nimkivy/uix/label
type Topic = ref object
  name: string
proc main() =
  let topic = Topic(name: "figs")
  buildUi:
    Label() as l:
      text <- topic.name
main()
