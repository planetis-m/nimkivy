#!/bin/sh
# Builds and runs nimkivy's tests, traces and scenes, in debug and release,
# and compares the traces and scenes with Kivy's (tests/fixtures) through
# tests/compare.nim. Run from anywhere; one Nimony build at a time. Needs
# NIMONY (default ~/Projects/nimony), SDL3, SDL3_ttf and SDL3_image; no Python.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
nimony=${NIMONY:-$HOME/Projects/nimony}/bin/nimony
cd "$here"
# Tests that open a window (tsdl3 and later) run headless and deterministic.
export SDL_VIDEO_DRIVER=offscreen SDL_RENDER_DRIVER=software SDL_AUDIO_DRIVER=dummy
mkdir -p tests/out

# build <program> <mode> <source>: bin/<program>-<mode>, with its own nimcache.
build() {
  flag=""
  [ "$2" = release ] && flag="-d:release"
  "$nimony" c $flag --mm:orc --path:src --nimcache:"nimcache/$1-$2" -o:"bin/$1-$2" "$3"
}

for mode in debug release; do
  for f in tests/t*.nim; do
    t=$(basename "$f" .nim)
    [ "$t" = traces ] && continue
    build "$t" "$mode" "$f"
    if [ "$t" = tshowcase ]; then
      # The whole-stack run (examples/showcase.nim) draws on the OpenGL
      # renderer, like the scenes.
      SDL_RENDER_DRIVER=opengl "./bin/$t-$mode"
    else
      "./bin/$t-$mode"
    fi
    echo "$t ($mode): passed"
  done
  build compare "$mode" tests/compare.nim
  build traces "$mode" tests/traces.nim
  rm -rf tests/out/traces tests/out/diff
  "./bin/traces-$mode"
  # The traces must match Kivy's exactly.
  "./bin/compare-$mode" tests/out --traces events clock label touch properties \
    animation screens modal
  # The scenes: geometry exact, pixels within budget. They use SDL's OpenGL
  # renderer through the offscreen driver's EGL: the software renderer
  # rasterizes long thin triangles up to a pixel off GL's and refuses Kivy's
  # blend mode (PORTING.md, Gaps).
  scenes="graphics_basic graphics_basic_msaa graphics_line graphics_texture canvas_order
    boxlayout_tests boxlayout_hints floatlayout_hints anchorlayout_tests
    label_align image_fit image_misc label_wrap label_default
    screen_relative fade_half modal_custom"
  # Known geometry differences (one label a pixel narrower: SDL3_ttf) are
  # listed exactly in tests/fixtures/known-geometry-diffs.txt; any other fails.
  build scenes "$mode" tests/scenes.nim
  SDL_RENDER_DRIVER=opengl "./bin/scenes-$mode" $scenes modal_default
  "./bin/compare-$mode" tests/out $scenes
  # Kivy's default ModalView background is an atlas image, which is out of
  # scope: nimkivy draws a plain white box, so only the geometry must match.
  diff tests/fixtures/scenes/modal_default.txt tests/out/modal_default.txt
  echo "ok   modal_default geometry (pixels differ as expected: SCOPE.md, ModalView)"
done
echo "all passed"
