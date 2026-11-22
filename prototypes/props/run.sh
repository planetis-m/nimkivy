#!/bin/sh
# Builds and runs the property prototype in debug and release, and checks
# that the bad/ programs fail as their first comment says.
cd "$(dirname "$0")" || exit 1
NIMONY=${NIMONY:-nimony}
NC=../nimcache; BIN=../bin
mkdir -p $BIN
fail=0
for mode in debug release; do
  flag=""; [ $mode = release ] && flag="-d:release"
  $NIMONY c --mm:orc $flag --nimcache:$NC/tprops-$mode -o:$BIN/tprops-$mode tprops.nim > $BIN/tprops-$mode.log 2>&1 &&
    $BIN/tprops-$mode || { echo "tprops $mode: FAILED"; tail -5 $BIN/tprops-$mode.log; fail=1; }
done
check_compile_error() { # file, text the error must contain
  if $NIMONY c --mm:orc --nimcache:$NC/$(basename $1 .nim) -o:$BIN/bad $1 > $BIN/bad.log 2>&1; then
    echo "$1: compiled, expected an error"; fail=1
  elif grep -q "$2" $BIN/bad.log; then
    echo "$1: rejected: $(grep -m1 "$2" $BIN/bad.log)"
  else
    echo "$1: failed without '$2'"; tail -5 $BIN/bad.log; fail=1
  fi
}
check_compile_error bad/bad_name.nim "undeclared field: 'opacty='"
check_compile_error bad/bad_bind.nim "undeclared identifier: 'bindOpacty'"
check_compile_error bad/bad_bind.nim "Type mismatch"
check_compile_error bad/bad_default.nim "initOpacty"
check_compile_error bad/bad_refs.nim "refs: h is not a property of Box"
$NIMONY c --mm:orc --nimcache:$NC/bad_bounds -o:$BIN/bad_bounds bad/bad_bounds.nim > $BIN/bad.log 2>&1 || { echo "bad_bounds: build failed"; fail=1; }
if out=$($BIN/bad_bounds 2>&1); then echo "bad_bounds: ran, expected exit 1"; fail=1
else echo "bad/bad_bounds.nim: stopped: $out"; fi
exit $fail
