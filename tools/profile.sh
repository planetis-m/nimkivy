#!/bin/sh
# The profiling baseline of PROFILE.md, again: frame times of the showcase's
# scripted run and of the busiest reference scenes, then where the time goes
# (perf, callgrind). Outputs go to tests/out/profile/. Run from anywhere;
# one Nimony build at a time.
#
#   tools/profile.sh                    # offscreen window (EGL), OpenGL renderer
#   VIDEO=x11 tools/profile.sh          # a real window (the script checks sizes
#                                       # at density 1: a scaled Wayland desktop fails)
#   RUNS=5 SKIP_CALLGRIND=1 tools/profile.sh
#   CPUS=4-11 tools/profile.sh         # pinned (taskset): the scheduler otherwise
#                                       # moves the run between core types
#
# Needs NIMONY (default ~/Projects/nimony), perf and valgrind.
set -eu
here=$(cd "$(dirname "$0")/.." && pwd)
nimony=${NIMONY:-$HOME/Projects/nimony}/bin/nimony
cd "$here"
# Runs a timed program, pinned to CPUS when set.
pinned() {
  if [ -n "${CPUS:-}" ]; then taskset -c "$CPUS" "$@"; else "$@"; fi
}
out=tests/out/profile
mkdir -p "$out"
export SDL_VIDEO_DRIVER=${VIDEO:-offscreen} SDL_RENDER_DRIVER=opengl SDL_AUDIO_DRIVER=dummy
runs=${RUNS:-3}
# Valgrind and perf otherwise ask debuginfod for the system libraries' debug
# info, which hangs without network.
export DEBUGINFOD_URLS=

# Release, with debug info and frame pointers for perf's call graphs.
build() {
  name=$1; shift
  "$nimony" c -d:release --mm:orc --path:src --passC:-g --passC:-fno-omit-frame-pointer \
    --nimcache:"nimcache/$name-profile" -o:"bin/$name-profile" "$@"
}
build tshowcase tests/tshowcase.nim
build scenes tests/scenes.nim
# For callgrind: the same, plus one counted call per dispatch of an observer
# list (the dispatch loops are inlined in the generated setters).
if [ -z "${SKIP_CALLGRIND:-}" ]; then
  build tshowcase-count -d:countDispatches tests/tshowcase.nim
fi

# 1. Frame times: the scripted run, uncapped (maxfps 0), every frame that
# drew; one file of milliseconds per run.
for i in $(seq "$runs"); do
  SHOWCASE_PROFILE="$out/frames-$i.txt" pinned ./bin/tshowcase-profile 2>/dev/null | grep '^frames'
done

# 2. The busiest reference scenes, drawn 1000 times each once settled.
SCENES_REDRAW=1000 pinned ./bin/scenes-profile graphics_line graphics_basic label_wrap image_fit \
  boxlayout_tests fade_half modal_custom 2>/dev/null | grep '^redraw'

# 3. perf: the same run capped at 60 fps as Kivy's default, so the time
# between frames is sleep, not the event pump spinning. User space only
# (perf_event_paranoid 2).
SHOWCASE_PROFILE="$out/frames-perf.txt" SHOWCASE_MAXFPS=60 pinned perf record -q -e cycles:u \
  -F 9999 --call-graph fp --user-callchains -o "$out/perf.data" ./bin/tshowcase-profile \
  >/dev/null 2>&1
perf report -i "$out/perf.data" --no-children --sort dso --stdio -g none 2>/dev/null \
  > "$out/perf-dso.txt"
perf report -i "$out/perf.data" --no-children --sort dso,symbol --stdio -g none 2>/dev/null \
  > "$out/perf-self.txt"
perf report -i "$out/perf.data" --children --sort symbol --stdio -g none 2>/dev/null \
  > "$out/perf-children.txt"
echo "perf: $out/perf-{dso,self,children}.txt"

# 4. callgrind: exact instruction counts and call counts, the same capped
# run. Slow (several minutes).
if [ -z "${SKIP_CALLGRIND:-}" ]; then
  SHOWCASE_PROFILE="$out/frames-callgrind.txt" SHOWCASE_MAXFPS=60 valgrind --tool=callgrind \
    --fair-sched=yes --callgrind-out-file="$out/callgrind.out" ./bin/tshowcase-count-profile \
    2>/dev/null | grep '^frames'
  callgrind_annotate --inclusive=yes "$out/callgrind.out" > "$out/callgrind-inclusive.txt"
  callgrind_annotate "$out/callgrind.out" > "$out/callgrind-self.txt"
  sh tools/callcounts.sh "$out/callgrind.out" > "$out/callgrind-calls.txt"
  echo "callgrind: $out/callgrind-{inclusive,self,calls}.txt"
fi
