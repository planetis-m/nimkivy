# Handoff to phase 2 step 7 (buildUi)

Step 6 is done (REDESIGN.md, "Step 6 notes"; PORTING.md P2.6). #336, #290,
#175, #337 were still open at `95afaa04` (= master).

- Phase 1 is gone: no `event.nim`, `properties.nim`, `Value`, class tables
  or `cls`. A widget subclass is built as `T(canvas: newCanvas())`, then
  `initProps()`, then its base's `init` proc (the showcase's `pressable`).
  `buildUi` can generate exactly that for a type without a `newT`.
- A layout derived directly from `Layout` must override `isAbstract` (to
  return false) besides `doLayout`.
- Nimony has no run-time type name (`$typeof` is static, #340): code that
  needs one uses an `of` chain (tests/scenes.nim, tests/tinstructions.nim).
- Text helpers: `stripUnicodeSpace(s, leading, trailing)`; canvas lists:
  `insertAt`, `removeFirst`.
- Step 9: `tools/callcounts.sh` no longer counts `doDispatch` or
  `getPropertyStorage` (they do not exist); typed dispatch is inlined in the
  generated setters, so count it another way against PROFILE.md's "before".
