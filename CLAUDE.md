# nimkivy

A narrow subset of Kivy (Python UI framework) ported to Nimony on SDL3. Read `PORTING.md` first.

Nimony work: use the installed skills in `.claude/skills/` (nimony-porting, nim-code-organization, nimony-bug-reporting, nim-string-parsing, nimony-plugins, nim-c-bindings, nim-c-wrappers, nimony-error-handling, nimony-nim2-differences, nim-testing, nim-style-guide, nim-doc-comments) before writing or reviewing code.

Bugs: Nimony compiler/stdlib bugs are reported to `planetis-m/nimony-bugs-llms` (not nim-lang/nimony). Known limitations are tracked as GAPs in `PORTING.md`, never worked around.

## Scope rules (owner, 2026-11-22)

- Do only what the owner asked. If something else seems needed, stop and report it; do not build it.
- Faithful to the source, or a recorded GAP. No workarounds, no emulations, no custom diagnostics, no generated extras.
- No metric targets: measure and report numbers, never tune code to reach one.
- When in doubt, delete rather than add. A change adding over ~150 lines needs a line-by-line reason.
- Reports list separately anything added that the owner did not ask for.
- While working, build and run only the tests your change touches (run_tests.sh with names and one mode); run the full suite once before committing.
