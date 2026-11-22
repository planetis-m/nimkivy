#!/bin/sh
# Runs the buildUi prototype (REDESIGN.md). The properties prototype became
# src/nimkivy/props.nim and its plugin (phase 2 step 1); its tests are
# tests/tprops.nim and tests/bad/, run by run_tests.sh.
cd "$(dirname "$0")" || exit 1
echo "== buildui"; ./buildui/run.sh
