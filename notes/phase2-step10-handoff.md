# Handoff after phase 2 step 9 (phase 2 complete)

Phase 2 is done (REDESIGN.md, summary at the top; PORTING.md P2.9;
PROFILE.md "After phase 2"). Next is the kiosk (philosykos-website),
written once on the result (REDESIGN.md, Step 7 notes).

- Profiling: `CPUS=4-11 tools/profile.sh` pins the timed runs (the
  scheduler otherwise mixes E- and LP-E-cores; frame times drift during a
  day, so compare builds with alternating runs). The callgrind run uses a
  `-d:countDispatches` build; `tools/callcounts.sh` lists
  `countPropertyDispatch` and `countEventDispatch`.
- A showcase run's dispatch totals vary with its frame count; compare
  dispatches on `tests/traces` and `tests/scenes` under callgrind
  (deterministic).
- Since step 7 the showcase renders 11 more label lines during its first
  layout (`buildUi` binding order). Harmless now; worth a look if the
  kiosk's start-up text renders matter.
- Word widths: the cache removes repeats only; first measurements at a new
  font size (resize, language change) are still 40% of the instructions.
- #336, #290, #175, #337 still open at Nimony `95afaa04` (master).
