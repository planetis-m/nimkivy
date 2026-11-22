# Handoff to phase 2 step 9 (profile again)

Step 8 is done (REDESIGN.md, "Step 8 notes"; PORTING.md P2.8). #336, #290,
#175, #337 still open at `95afaa04` (= master).

- The word-width cache is `OpenFont.words` in `core/text/text_sdl3`
  (per open font, keyed by the text; emptied on a change of hinting,
  kerning, direction or style, on `register`, and at 4096 texts).
- `TTF_GetStringSize` calls, counted by an LD_PRELOAD wrapper on the
  uncapped run (`SDL_RENDER_DRIVER=opengl`, offscreen): tshowcase 1,073
  before, 508 after. PROFILE.md's 997 is the capped callgrind run; compare
  your callgrind count (`tools/callcounts.sh`) with 997, not with 1,073.
- The remaining calls are first measurements: a word at a new font size
  (resize, language change) or a font whose state a render just changed.
- `tools/callcounts.sh` still matches `TTF_GetStringSize`, `getExtents` and
  `textureUpdate`; `doDispatch` and `getPropertyStorage` no longer exist
  (step 6 note in REDESIGN.md).
