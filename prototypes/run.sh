#!/bin/sh
# Runs both phase-2 prototypes (REDESIGN.md): typed properties and buildUi.
cd "$(dirname "$0")" || exit 1
fail=0
echo "== props"; ./props/run.sh || fail=1
echo "== buildui"; ./buildui/run.sh || fail=1
exit $fail
