#!/bin/sh
# Builds and runs nimkivy's tests, traces and scenes, and compares the traces
# and scenes with Kivy's (tests/fixtures) through tests/compare.nim. Run from
# anywhere; one Nimony build at a time. Needs NIMONY (default
# ~/Projects/nimony), SDL3, SDL3_ttf and SDL3_image; no Python.
#
#   ./run_tests.sh [--debug | --release] [name ...]
#
# A name is a test (tbuildui, tshowcase, ...), bad, traces or scenes. Without
# a mode: debug and release; without names: all of them. The scenes (pixels)
# run in release only: rendering is the same in both modes.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
nimony=${NIMONY:-$HOME/Projects/nimony}/bin/nimony
cd "$here"
# Tests that open a window (tsdl3 and later) run headless and deterministic.
export SDL_VIDEO_DRIVER=offscreen SDL_RENDER_DRIVER=software SDL_AUDIO_DRIVER=dummy
mkdir -p tests/out

modes="debug release"
case "${1-}" in --debug|--release) modes=${1#--}; shift ;; esac
for n in "$@"; do
  [ -f "tests/$n.nim" ] || [ "$n" = bad ] || [ "$n" = scenes ] ||
    { echo "unknown test: $n"; exit 1; }
done
names=" $* "
# want <name>: no names were given, or <name> is one of them.
want() { [ "$names" = "  " ] || case "$names" in *" $1 "*) ;; *) false ;; esac; }

# build <program> <mode> <source>: bin/<program>-<mode>; one nimcache per mode.
build() {
  flag=""
  [ "$2" = release ] && flag="-d:release"
  "$nimony" c $flag --mm:orc --path:src --nimcache:"nimcache/$2" -o:"bin/$1-$2" "$3"
}

# The programs in tests/bad must not build (each must fail with the text
# given here), except bad_bounds, which must stop with exit code 1.
bad() { # <program> <text the error contains>
  if "$nimony" c --mm:orc --path:src --nimcache:nimcache/debug -o:"bin/$1" \
      "tests/bad/$1.nim" > "tests/out/$1.log" 2>&1; then
    echo "tests/bad/$1.nim: built, expected an error"; exit 1
  fi
  grep -q "$2" "tests/out/$1.log" ||
    { echo "tests/bad/$1.nim: failed without '$2'"; tail -5 "tests/out/$1.log"; exit 1; }
  echo "tests/bad/$1.nim: rejected"
}
if want bad; then
  bad bad_name "undeclared field: 'opacty='"
  bad bad_bind "undeclared identifier: 'bindOpacty'"
  bad bad_bind "bad_bind.nim(6, 22) Error: Type mismatch"
  bad bad_default "undeclared identifier: 'initOpacty'"
  bad bad_refs "undeclared field: 'h'"
  bad bad_readonly "undeclared field: 'half='"
  bad bad_pragma "bad_pragma.nim(7, 12) Error: properties: unsupported syntax"
  "$nimony" c --mm:orc --path:src --nimcache:nimcache/debug -o:bin/bad_bounds \
    tests/bad/bad_bounds.nim
  if ./bin/bad_bounds; then echo "bad_bounds: ran, expected exit code 1"; exit 1; fi
  echo "tests/bad/bad_bounds.nim: stopped"
fi

for mode in $modes; do
  for f in tests/t*.nim; do
    t=$(basename "$f" .nim)
    [ "$t" = traces ] && continue
    want "$t" || continue
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
  if want traces || { [ "$mode" = release ] && want scenes; }; then
    build compare "$mode" tests/compare.nim
    rm -rf tests/out/diff
  fi
  if want traces; then
    build traces "$mode" tests/traces.nim
    rm -rf tests/out/traces
    "./bin/traces-$mode"
    # The traces must match Kivy's exactly.
    "./bin/compare-$mode" tests/out --traces events clock label touch properties \
      animation screens modal
  fi
  { [ "$mode" = release ] && want scenes; } || continue
  # The scenes: geometry exact, pixels within budget. They use SDL's OpenGL
  # renderer through the offscreen driver's EGL: the software renderer
  # rasterizes long thin triangles up to a pixel off GL's and refuses Kivy's
  # blend mode (PORTING.md, Gaps).
  scenes="graphics_basic graphics_basic_msaa graphics_smooth graphics_line graphics_texture canvas_order
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
