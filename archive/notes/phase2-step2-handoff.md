# Handoff to phase 2 step 2 (layer 1 and 5 dispatchers)

Step 1 is done: `nimkivy/props` (`properties:`), `observers`, `plugins/propsplug`,
`plugins/codegen`. Read `props.nim`'s module doc first; `tests/tproperties.nim`
shows every kind in use, including aliases (`metrics`, `core/window`).

- A module: `import nimkivy/props`, one `properties:` block with its types and
  every proc/method whose signature names them (#290, #175 still open); the
  constructor calls `initProps()` once (it replaces `initEventDispatcher`).
- An alias's getter/setter are plain procs in the block: `get(w: T): V`,
  `set(w: T; v: V): bool` (true dispatches). `deps` and `refs` may name base
  properties. Kivy's `watch_before_use=True` (the default) is `eager`.
- A class's own `on_<prop>` / `on_<event>`: declare `method onPChanged*(w: T;
  v: V) {.base.}` / `method onE*(w: T; args): bool {.base.}` in the block.
- `Opt[T]` properties compare with `props.==`; `Rgba` is in props.
- `WidgetBase` (`parent`, `children`) is written by hand (#337): its typed
  observer lists are `Observers[proc (v: T) {.closure.}]` fields with hand-written
  `bindX`/`unbindX`. A base declared outside a block works: the init chain ends
  at the `RootRef` no-ops in props.
- Phase-1 `event`/`properties` still build the rest; a module can import both
  while it migrates (tests/traces.nim does).
- Nimony traps met: a proc literal inside an `{.untyped.}` template crashes
  nimsem (#338); `T(field: v)` for an inherited field inside an `{.untyped.}`
  template gives invalid C when a proc has the field's name (#339).
- Animation tracks (`pTo`, `pKey`) are step 5's.
