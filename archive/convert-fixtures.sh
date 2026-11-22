#!/bin/sh
# Converted the outputs Kivy wrote (Python's formatting) to the fixture
# format of REDESIGN.md, once, on 2026-11-22, when they moved from
# reference/out/ to tests/fixtures/. Kept as a record; running it again on
# the converted files changes nothing.
#
#   sh archive/convert-fixtures.sh tests/fixtures
set -eu
dir=$1

# Traces: Kivy's snake_case names in Nim's camelCase (on_touch_down ->
# onTouchDown, is_open -> isOpen), Python's literals in Nim's. A handler's
# None return is a false bool in Nim; a missing widget (grab_current None) is
# nil, a missing number (text_size) none. Python's lists become seq literals.
for f in "$dir"/traces/*.txt; do
  sed -i \
    -e 's/\([a-z0-9]\)_\([a-z]\)/\1\U\2/g' \
    -e 's/\([a-z0-9]\)_\([a-z]\)/\1\U\2/g' \
    -e 's/\bTrue\b/true/g; s/\bFalse\b/false/g' \
    -e 's/grabCurrent None/grabCurrent nil/g' \
    -e 's/-> None$/-> false/' \
    -e 's/(animation=false)/(animation = false)/' \
    -e 's/minStateTime \.035/minStateTime 0.035/' \
    -e 's/posHint {}/posHint @[]/' \
    "$f"
done
# Python's lists of names in the screens trace: ['a', 'b'] -> @["a", "b"].
sed -i -e "s/\['\([^]]*\)'\]/@[\"\1\"]/g; s/', '/\", \"/g; s/ \[\]/ @[]/g" \
  "$dir"/traces/screens.txt

# The label trace: Label(**kw) as Nim's named arguments, `text = "Hello",
# fontSize = 40`; strings quoted the Nim way, enum values by their Nim names.
sed -i \
  -e "s/^{\(.*\)} -> /\1 -> /" \
  -e "s/'valign': 'middle'/'valign': valignMiddle/; s/'halign': 'justify'/'halign': halignJustify/" \
  -e "s/'\([a-zA-Z]*\)': /\1 = /g" \
  -e "s/'\([^']*\)'/\"\1\"/g" \
  -e 's/None/none/g' \
  "$dir"/traces/label.txt

# Scene geometry and its known differences: attribute names in camelCase.
sed -i -e 's/texture_size=/textureSize=/g; s/norm_image_size=/normImageSize=/g' \
  "$dir"/scenes/*.txt "$dir"/known-geometry-diffs.txt

# Vertex geometry: Line.rounded_rectangle's Nim name, an empty value as none,
# Line.close as a bool. The numbers stay as Python's repr wrote them: the
# shortest text that reads back as the same float, which Nim's `$` writes too.
sed -i \
  -e 's/ rounded_rectangle / roundedRectangle /' \
  -e 's/ None$/ none/' \
  -e 's/ close 1\.0$/ close true/; s/ close 0\.0$/ close false/' \
  "$dir"/graphics_points.txt
