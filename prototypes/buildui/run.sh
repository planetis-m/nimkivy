#!/bin/sh
# Builds and runs the buildUi prototype in debug and release, and checks
# that the bad/ programs are rejected as their first comment says.
cd "$(dirname "$0")" || exit 1
NIMONY=${NIMONY:-nimony}
NC=../nimcache; BIN=../bin
mkdir -p $BIN
fail=0
for mode in debug release; do
  flag=""; [ $mode = release ] && flag="-d:release"
  $NIMONY c --mm:orc $flag --path:../../src --nimcache:$NC/tbuildui-$mode -o:$BIN/tbuildui-$mode tbuildui.nim > $BIN/tbuildui-$mode.log 2>&1 &&
    $BIN/tbuildui-$mode || { echo "tbuildui $mode: FAILED"; tail -5 $BIN/tbuildui-$mode.log; fail=1; }
done
check_compile_error() { # file, text the error must contain
  if $NIMONY c --mm:orc --path:../../src --nimcache:$NC/$(basename $1 .nim) -o:$BIN/bad $1 > $BIN/bad.log 2>&1; then
    echo "$1: compiled, expected an error"; fail=1
  elif grep -q "$2" $BIN/bad.log; then
    echo "$1: rejected: $(grep -m1 "$2" $BIN/bad.log)"
  else
    echo "$1: failed without '$2'"; tail -5 $BIN/bad.log; fail=1
  fi
}
check_compile_error bad/bad_prop.nim "undeclared field: 'txt='"
check_compile_error bad/bad_binding.nim "bindValu"
check_compile_error bad/bad_item.nim "expected a widget"
exit $fail
