# Brief for every phase 2 migration step

You do one row of the Migration plan in `REDESIGN.md`. Project: `/home/ageralis/Projects/nimkivy`, branch `phase2`. Do NOT commit; the coordinator reviews, runs the tests and commits.

## Read first

`ROADMAP.md` (goals and the phase 2 decisions), `REDESIGN.md` (the design and your row), `PORTING.md` (gaps, design differences, progress), the notes left by the previous step in `notes/` if any, `run_tests.sh`, `bug-reports/` (known Nimony issues: do not re-file), and the code your row touches.

Skills (read before writing code): `.claude/skills/{nimony-porting,nimony-plugins,nim-code-organization,nimony-nim2-differences,nimony-error-handling,nim-style-guide,nim-doc-comments,nim-testing,nim-string-parsing,nimony-bug-reporting}/SKILL.md`. Nimony: `/home/ageralis/Projects/nimony` (`bin/nimony`), commit 95afaa04; first check whether the issues REDESIGN.md lists (#336, #290, #175, #337) are fixed on origin/master and say so.

## Goals (owner)

- No Pythonisms in the code: Nim names and idioms, typed properties and events, no `Value` boxing or name lookups once a module is migrated, no Python-style helpers or output.
- Behaviour unchanged: every test, trace, scene and `tshowcase` in `run_tests.sh` passes in debug and release after your step. Tests change in syntax only; a test may not be weakened to make a step pass.
- Standalone: nothing may need Python.

## Rules

- Standard library plus the SDL3 bindings and nimkivy's own plugins. When Nimony cannot do something cleanly: write the simplest form that compiles, mark `# GAP: <what is inaccurate>, because <what is missing or bug-reports/NN>`, add a Gaps row in PORTING.md, and move on. No workarounds, no forcing unsupported features, no effort spent circumventing known limitations.
- Nimony bugs: confirm per nimony-bug-reporting (rule out documented differences incl. `{.feature: "v2".}`; minimal reproducer importing only lib/std (plus the plugin API for plugin bugs); empty dir, fresh `--nimcache`; `git -C /home/ageralis/Projects/nimony fetch origin` and say whether master is ahead; note stale tools in bin/). Search first: `gh issue list -R planetis-m/nimony-bugs-llms --search "<text>" --state all`. File NEW ones to **planetis-m/nimony-bugs-llms** (owner's instruction; never nim-lang/nimony) in the format of `bug-reports/01..`, labels: one of bug/miscompile/crash/rejects-valid/accepts-invalid/bad-diagnostic, a fitting `phase:*`, `found:llm-agents`; copy in `bug-reports/NN-name.md`. Existing issue: comment only with new information.
- Only one Nimony build at a time on this machine; you are the only agent building.
- Paths: never reference anything outside the nimkivy repo in src/, tests/ or examples/.

## Finish

Update PORTING.md (progress row `P2.<n>`, Gaps both ways, design differences) and REDESIGN.md (mark your row done; note anything that changed). Write `notes/phase2-step<n+1>-handoff.md` (short) for the next step. Report briefly: what changed, test results (debug/release), GAPs, issues filed (URLs), anything the next step must know.
