# Handoff to phase 2 step 8 (word-width cache)

Step 7 is done (REDESIGN.md, "Step 7 notes"; PORTING.md P2.7). #336, #290,
#175, #337 were still open at `95afaa04` (= master).

- `buildUi` is `src/nimkivy/buildui.nim` + `plugins/builduiplug.nim`;
  `prototypes/` is gone (#336's reproduction is `bug-reports/09`).
  `run_tests.sh` builds 8 more rejected programs (`tests/bad/bad_ui_*.nim`),
  each matched with its file, line and column.
- `examples/showcase.nim` is now built with `buildUi`: same widgets and the
  same `Showcase` fields, but Labels come from the `Caption`/`Paragraph`
  components (a typed `textSize <- self.size` binding) and backgrounds from
  `canvas.before` blocks. tshowcase passes unchanged, so its label renders
  are the ones to compare for the cache (`TTF_GetStringSize` calls).
- Labels' text-size bindings and font sets now run in the DSL's order
  (all `prop = value` sets first, then the bindings), not phase 1's
  per-label order; one render per Clock trigger is unchanged.
- For step 9: the profiled run (tshowcase) builds its trees through
  `buildUi` now; the bindings per widget are the same as phase 1's
  hand-written ones (background rectangle to `pos`/`size`, label
  `textSize` to `size` or `width`, dots to `pos`/`size`), so the dispatch
  count per drawn frame should still match PROFILE.md's 8.1; if it does
  not, look there first.
