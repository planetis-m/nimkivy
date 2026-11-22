## The widget tree's base, declared without the plugin: a type that refers
## to itself through `seq`, declared by a module-level template (plugin or
## not), fails in shoggoth (planetis-m/nimony-bugs-llms#337,
## bug-reports/10). nimkivy's `WidgetBase` has the same place (core/window,
## PORTING.md).

type
  WidgetBase* = ref object of RootObj
    ## A node of the tree.
    children*: seq[WidgetBase]

proc addWidget*(w, child: WidgetBase) =
  ## Adds `child` last.
  w.children.add child
