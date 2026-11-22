## Colour helpers from Kivy's `kivy/utils.py`.

import std/[strutils, syncio]

proc isHexDigit(c: char): bool {.inline.} =
  c in {'0'..'9', 'a'..'f'}

proc getColorFromHex*(s: string): seq[float] =
  ## The colour of a hex string such as `#rrggbb` or `rrggbbaa`, as 3 or 4
  ## numbers in 0..1; three get alpha 1.
  ##
  ## Like Kivy, the string is cut into pairs of hex digits
  ## (`re.split('([0-9a-f]{2})')`), so `#rgb` gives two numbers (`rg` and
  ## `b`), not a short CSS colour. A part that is not hex stops the program,
  ## where Kivy raises ValueError.
  var t = s
  while t.startsWith("#"): t = t.substr(1)
  t = t.toLowerAscii
  # The pieces re.split keeps: each hex pair, and the non-empty text between.
  var pieces: seq[string] = @[]
  var gap = ""
  var i = 0
  while i < t.len:
    if i + 1 < t.len and isHexDigit(t[i]) and isHexDigit(t[i + 1]):
      if gap.len > 0:
        pieces.add gap
        gap = ""
      pieces.add t.substr(i, i + 1)
      i += 2
    else:
      gap.add t[i]
      inc i
  if gap.len > 0: pieces.add gap
  result = @[]
  for p in pieces:
    var n = 0
    for c in p:
      if not isHexDigit(c):
        quit "not a hex colour: '" & p & "'"
      n = n * 16 + (if c <= '9': ord(c) - ord('0') else: ord(c) - ord('a') + 10)
    result.add float(n) / 255.0
  if result.len == 3:
    result.add 1.0

proc getHexFromColor*(color: openArray[float]): string =
  ## The hex string of a colour, `#` and two lowercase digits per component
  ## (`int(x * 255)`, rounded towards zero).
  result = "#"
  for x in color:
    let n = int(x * 255)
    var h = toHex(BiggestInt(n), 8).toLowerAscii
    while h.len > 2 and h[0] == '0': h = h.substr(1)
    result.add h
