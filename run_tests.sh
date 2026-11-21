#!/bin/sh
# Builds and runs nimkivy's tests and traces, in debug and release.
# Run from anywhere; one Nimony build at a time. Needs NIMONY (default
# ~/Projects/nimony) and the kiosk's Python with Kivy for reference/compare.py.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
nimony=${NIMONY:-$HOME/Projects/nimony}/bin/nimony
python=${PY:-$HOME/Projects/philosykos-website/kiosk/.venv/bin/python}
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
    "./bin/$t-$mode"
    echo "$t ($mode): passed"
  done
  build traces "$mode" tests/traces.nim
  rm -rf tests/out/traces
  "./bin/traces-$mode"
  # Layer 1 traces must match exactly.
  "$python" reference/compare.py tests/out --traces events clock
  # The properties trace gets its Widget lines in layer 6: until then the
  # lines written so far must be the first lines of Kivy's.
  n=$(wc -l < tests/out/traces/properties.txt)
  if head -n "$n" reference/out/traces/properties.txt | cmp -s - tests/out/traces/properties.txt; then
    echo "ok   trace properties: first $n of $(wc -l < reference/out/traces/properties.txt) lines"
  else
    echo "FAIL trace properties"
    head -n "$n" reference/out/traces/properties.txt | diff - tests/out/traces/properties.txt | head -20
    exit 1
  fi
  # The scenes drawn so far, pixels only until Widget (layer 6) gives them
  # geometry. They use SDL's OpenGL renderer through the offscreen driver's
  # EGL: the software renderer rasterizes long thin triangles up to a pixel
  # off GL's and refuses Kivy's blend mode (PORTING.md, Gaps).
  build scenes "$mode" tests/scenes.nim
  SDL_RENDER_DRIVER=opengl "./bin/scenes-$mode" graphics_basic graphics_basic_msaa graphics_line \
    canvas_order
  "$python" reference/compare.py tests/out --pixels graphics_basic graphics_basic_msaa \
    graphics_line canvas_order
done
echo "all passed"
