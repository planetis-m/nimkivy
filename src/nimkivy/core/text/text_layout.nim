## Text layout: Kivy's `kivy/core/text/text_layout.pyx`, all of it
## (`layout_text`, `LayoutWord`, `LayoutLine`), and the label options it
## reads.
##
## `layoutText` cuts a text into lines that fit `textSize`: at newlines, at
## spaces when the width is constrained, and inside a word that is wider than
## the line. It only measures, through the `getExtents` it is given, so the
## line breaks follow the font metrics of the text provider.
##
## Kivy indexes a string by characters (code points), Nim by bytes. Positions here
## are byte offsets: a space is one byte in UTF-8 and never part of another
## character, so searching for spaces gives the same cuts, and where Kivy
## steps one character (splitting a long word) the code steps one UTF-8
## character with `runeLenAt`.

import std/[strutils, unicode, sequtils, opt]

# Callers set `TextSize` with `some` and `none`. Exporting std/opt also lets
# a module that constructs an object with options compile: without it there,
# `default` is an "ambiguous call" (planetis-m/nimony-bugs-llms#33).
export opt

type
  Halign* = enum
    ## Horizontal alignment of the lines (Kivy's `halign` strings).
    halignLeft = "left"
    halignCenter = "center"
    halignRight = "right"
    halignJustify = "justify"
    halignAuto = "auto"       ## left, or right for right-to-left text

  Valign* = enum
    ## Vertical alignment of the text (Kivy's `valign` strings).
    valignBottom = "bottom"
    valignMiddle = "middle"
    valignCenter = "center"   ## the same as middle
    valignTop = "top"

  FontHinting* = enum
    ## The FreeType hinter (Kivy's `font_hinting`; `None` is `hintingNone`).
    hintingNormal = "normal"
    hintingLight = "light"
    hintingMono = "mono"
    hintingNone = "none"

  TextSize* = tuple[w, h: Opt[float]]
    ## The box the text is laid out in; `none` is Kivy's None (no limit).

  LabelOptionsObj* = object
    ## The options of a label; use `LabelOptions`. core/text/__init__.py
    ## LabelBase.options, for the keys in SCOPE.md.
    fontSize*: float          ## points, opened as `int(fontSize)`
    fontName*: string         ## a registered name, a file or a name in data/fonts
    fontNameR*: string        ## the resolved file (`resolveFontName`)
    bold*, italic*: bool
    halign*: Halign
    valign*: Valign
    lineHeight*: float        ## a multiplier on the font height
    strip*: bool              ## strip each line (always on with justify)
    stripReflow*: bool        ## strip lines made by wrapping
    maxLines*: int            ## 0 is no limit
    fontHinting*: FontHinting
    fontKerning*: bool
    fontBlended*: bool
    color*: array[4, float]
    padding*: array[4, float] ## left, top, right, bottom
    textSize*: TextSize       ## set by `render` from the label's text size
    spaceWidth*: int          ## set by `render`: the width of one space

  LabelOptions* = ref LabelOptionsObj
    ## Label options, shared by the words laid out with them, as Kivy's
    ## options dict is.

  LayoutWord* = ref object
    ## A piece of text in a line, with its size in pixels and options.
    ## text_layout.pyx LayoutWord
    text*: string
    lw*, lh*: int
    options*: LabelOptions

  LayoutLine* = ref object
    ## A line of text: its position in the texture (set when rendered), size
    ## and words. `h` is the tallest word times `lineHeight`.
    ## text_layout.pyx LayoutLine
    x*, y*, w*, h*: int
    isLastLine*: bool          ## the line ends a paragraph (a newline follows)
    lineWrap*: bool            ## the line continues the previous one
    words*: seq[LayoutWord]

  Extents* = proc (text: string): (int, int) {.closure.}
    ## Measures a text: its width and height in pixels.

proc newLabelOptions*(): LabelOptions =
  ## Kivy's defaults (LabelBase.__init__).
  LabelOptions(fontSize: 12, fontName: "Roboto", fontNameR: "", bold: false,
    italic: false, halign: halignLeft, valign: valignBottom, lineHeight: 1.0,
    strip: false, stripReflow: true, maxLines: 0, fontHinting: hintingNormal,
    fontKerning: true, fontBlended: true, color: [1.0, 1, 1, 1],
    padding: [0.0, 0, 0, 0], textSize: (none[float](), none[float]()), spaceWidth: 0)

proc copy*(o: LabelOptions): LabelOptions =
  ## A copy of the options (Kivy's `copy(options)`).
  result = LabelOptions()
  result[] = o[]

proc newLayoutWord*(options: sink LabelOptions; lw, lh: int; text: sink string): LayoutWord =
  ## A word. text_layout.pyx LayoutWord.__cinit__
  LayoutWord(options: options, lw: lw, lh: lh, text: text)

proc newLayoutLine*(x = 0; y = 0; w = 0; h = 0; isLastLine = false;
    lineWrap = false; words: sink seq[LayoutWord] = @[]): LayoutLine =
  ## A line. text_layout.pyx LayoutLine.__cinit__
  LayoutLine(x: x, y: y, w: w, h: h, isLastLine: isLastLine, lineWrap: lineWrap,
    words: words)

const UnicodeSpace = [Rune(0x09), Rune(0x0A), Rune(0x0B), Rune(0x0C), Rune(0x0D),
  Rune(0x1C), Rune(0x1D), Rune(0x1E), Rune(0x1F), Rune(0x20), Rune(0x85), Rune(0xA0),
  Rune(0x1680), Rune(0x2000), Rune(0x2001), Rune(0x2002), Rune(0x2003), Rune(0x2004),
  Rune(0x2005), Rune(0x2006), Rune(0x2007), Rune(0x2008), Rune(0x2009), Rune(0x200A),
  Rune(0x2028), Rune(0x2029), Rune(0x202F), Rune(0x205F), Rune(0x3000)]
  # The white space characters Kivy's `str.strip()` removes (Unicode White_Space
  # and the separators U+001C .. U+001F).

# `unicode.strip(s, runes = ...)` with a string is an "ambiguous call"
# (planetis-m/nimony-bugs-llms#331), so the strips pass the string as an
# openArray, which is the same call.
proc stripUnicodeSpace*(s: string; leading = true; trailing = true): string {.inline.} =
  ## `s` without the `UnicodeSpace` characters at its start (`leading`) and
  ## its end (`trailing`): Kivy's `strip`, `lstrip` and `rstrip`, on which
  ## its layout depends.
  unicode.strip(s.toOpenArray(0, s.high), leading, trailing, UnicodeSpace)

proc charLen(s: string; i: int): int =
  # The bytes of the UTF-8 character at byte `i`: where Kivy steps one
  # character, the layout steps `charLen` bytes. `i` is never negative.
  if i >= 0: runeLenAt(s, i) else: 1

proc findSpace(s: string; start: int): int =
  # Kivy's `s.find(' ', start)`; `start` is never negative.
  if start >= 0: s.find(' ', start) else: -1

proc toInt(v: Opt[float]): int =
  # A size limit as Cython's `cdef int` gets it (truncated); -1 is None.
  if v.isSome: int(v.get(0)) else: -1

proc finalStrip(line: LayoutLine) =
  # text_layout.pyx final_strip: the line must not end in spaces. Its height
  # is kept, as in Kivy.
  while line.words.len > 0 and (line.words[^1].text.endsWith(' ') or
      line.words[^1].text.len == 0):
    let lastWord = line.words.pop()
    if lastWord.text.len == 0:
      line.w -= lastWord.lw
    else:
      let stripped = stripUnicodeSpace(lastWord.text, leading = false)
      # Kivy counts the stripped characters, not bytes.
      let diff = (runeLen(lastWord.text) - runeLen(stripped)) * lastWord.options.spaceWidth
      line.w = max(0, line.w - diff)
      line.words.add newLayoutWord(lastWord.options, max(0, lastWord.lw - diff),
        lastWord.lh, stripped)

proc addLine(text: sink string; lw, lh: int; line: sink LayoutLine; lines: var seq[LayoutLine];
    options: sink LabelOptions; lineHeight: float32; xpad: int; w, h: var int; pos: int;
    strip: bool): LayoutLine =
  # text_layout.pyx add_line: adds the text to the line, the line to `lines`
  # (at `pos`, or at the end when -1), grows w and h, and returns a new line.
  let oldLh = line.h
  let count = lines.len
  if lw != 0:
    line.words.add newLayoutWord(options, lw, lh, text)
    line.w += lw
  line.h = max(int(float32(lh) * lineHeight), line.h)
  # The first line always gets the full font height.
  let addH = if count != 0: line.h else: max(lh, line.h)
  # When appending to an existing line, its height is not added twice.
  h = h + addH - oldLh
  w = max(w, line.w + xpad)
  if strip:
    finalStrip(line)
  if pos < 0:
    lines.add line
  else:
    lines.insert([line], pos)
  result = newLayoutLine()

proc layoutTextUnrestricted(text: string; lines: var seq[LayoutLine]; w0, h0: int;
    uh: int; options: sink LabelOptions; getExtents: Extents; dwn, complete: bool;
    xpad, maxLines: int; lineHeight: float32; strip: bool): (int, int, bool) =
  # text_layout.pyx layout_text_unrestricted: no width limit, so each
  # paragraph is one line.
  var w = w0
  var h = h0
  let newLines = text.split('\n')
  let n = newLines.len
  var made: seq[LayoutLine] = @[]      # Kivy stores the lines in new_lines
  for j in 0 ..< n:
    made.add newLayoutLine()
  var s = 0
  var k = n
  var pos = lines.len
  var val = false
  # There is a last (or first) line to which the first (last) paragraph is
  # appended.
  if pos != 0:
    var line: LayoutLine
    var ln: string
    if dwn:
      line = lines[^1]
      ln = newLines[0]
      s = 1
    else:
      line = lines[0]
      ln = newLines[^1]
      k = n - 1
    let ends = complete or (dwn and n > 1) or (not dwn and pos > 1)
    if strip:
      if line.w == 0:
        ln = stripUnicodeSpace(ln, trailing = false)
      if ends:
        ln = stripUnicodeSpace(ln, leading = false)
    let (lw, lh) = getExtents(ln)
    let oldLh = line.h
    var addH = 0
    if lw != 0:
      # When adding to an existing line, uh is not checked.
      line.words.add newLayoutWord(options, lw, lh, ln)
      line.w += lw
      line.h = max(int(float32(lh) * lineHeight), line.h)
      addH = if pos == 1: max(lh, line.h) else: line.h
    elif strip and ends:
      finalStrip(line)
      addH = line.h
    else:
      addH = line.h
    w = max(w, line.w + xpad)
    h += addH - oldLh

  # Now the remaining paragraphs.
  var i = -1
  var j = if dwn: s else: k - 1
  while (dwn and j < k) or (not dwn and j >= s):
    i = j
    # The first line is always laid out, even if it is not shown.
    if (maxLines > 0 and pos + 1 > maxLines) or (pos != 0 and uh != -1 and h > uh):
      i += (if dwn: -1 else: 1)
      break
    var ln = newLines[i]
    if strip:
      if complete or (dwn and i < n - 1) or (not dwn and i > s):
        ln = stripUnicodeSpace(ln)
      else:
        # The last line is only stripped on the left.
        ln = stripUnicodeSpace(ln, trailing = false)
    let (lw, lh) = getExtents(ln)
    let lhh = int(float32(lh) * lineHeight)
    # The first line always gets the full font height.
    let addH = if pos != 0: lhh else: lh
    if uh != -1 and h + addH > uh and pos != 0:
      i += (if dwn: -1 else: 1)
      break
    inc pos
    w = max(w, lw + xpad)
    h += addH
    if lw != 0:
      made[i] = newLayoutLine(0, 0, lw, lhh, true, false, @[newLayoutWord(options, lw, lh, ln)])
    else:
      made[i] = newLayoutLine(0, 0, 0, lhh, true, false)
    j += (if dwn: 1 else: -1)

  if s != k:
    if dwn:
      for x in s .. i:
        lines.add made[x]
      val = i != k - 1
    else:
      if k != i:
        lines.insert(made.toOpenArray(i, k - 1), 0)
      val = i != 0
  result = (w, h, val)

# GAP: `options` of `layoutText` is not sink, because
# planetis-m/nimony-bugs-llms#346 (`float32(options.lineHeight)`)
proc layoutText*(text: string; lines: var seq[LayoutLine]; size: (int, int);
    textSize: TextSize; options: LabelOptions; getExtents: Extents;
    appendDown, complete: bool): (int, int, bool) =
  ## Lays `text` out into `lines`, appending to the last line (or, when
  ## `appendDown` is false, the first) until a newline. `size` is the size
  ## laid out so far ((0, 0) at first), `textSize` the limit, padding
  ## included. `complete` says that no text follows, so every line is
  ## stripped. Returns the width and height laid out, padding included, and
  ## whether text was left out because it did not fit.
  ## text_layout.pyx layout_text
  let xpad = int(options.padding[0] + options.padding[2])
  let ypad = int(options.padding[1] + options.padding[3])
  let maxLines = options.maxLines
  let lineHeight = float32(options.lineHeight)
  let strip = options.strip or options.halign == halignJustify
  let refStrip = options.stripReflow
  var w = size[0]
  var h = size[1]
  let dwn = appendDown
  var uw = toInt(textSize.w)
  let uh = toInt(textSize.h)
  if h == 0:
    h = ypad
  if uw == -1:
    return layoutTextUnrestricted(text, lines, w, h, uh, options, getExtents, dwn,
      complete, xpad, maxLines, lineHeight, strip)

  let newLines = text.split('\n')
  let n = newLines.len
  uw = max(0, uw - xpad)   # the width left for the text
  let bareH = getExtents("")[1]
  var pos = 0
  if dwn:
    pos = -1   # lines are appended at the end
  var lw = -1
  var lh = -1
  var lwe = 0
  var lhe = 0
  var i = -1

  # Split into lines, and find how many wraps each line needs.
  var j = if dwn: 0 else: n - 1
  while (dwn and j < n) or (not dwn and j >= 0):
    i = j
    j += (if dwn: 1 else: -1)
    var isSpace = false
    var k = lines.len
    if (maxLines > 0 and k > maxLines) or (uh != -1 and h > uh and k > 1):
      break
    let isLastLine = not ((dwn and i < n - 1) or (not dwn and i != 0))
    # Whether this line is ended, or text may be appended to it later.
    let endsLine = complete or not isLastLine
    if not dwn:
      pos = 0   # a new line goes at the top, unless changed below
    var line: LayoutLine
    # The first (last, upwards) paragraph is appended to the previous line.
    if (i != 0 and dwn) or (not dwn and i != n - 1) or k == 0:
      line = newLayoutLine()
    elif dwn:
      line = lines.pop()
    else:
      # Append right before the first line ends, in case it wrapped.
      while pos + 1 < k and not lines[pos + 1].lineWrap:
        inc pos
      line = lines[pos]
      lines.delete(pos)

    var ln = newLines[i]
    # No text before it, so strip leading spaces.
    if line.w == 0 and (strip or (refStrip and line.lineWrap)):
      ln = stripUnicodeSpace(ln, trailing = false)
    if strip and endsLine:
      ln = stripUnicodeSpace(ln, leading = false)

    k = ln.len
    if k == 0:
      # An empty line, to which nothing will be appended; it must not keep
      # trailing spaces from before.
      line.isLastLine = endsLine
      line = addLine("", 0, bareH, line, lines, options, lineHeight, xpad, w, h, pos,
        line.w != 0 and endsLine)
      continue

    # A non-empty line: add the next word if it fits, else start a new line.
    # A word that does not fit on a line by itself is split over as many
    # lines as it needs. `s` is the start of the current line in `ln`, `e`
    # the next space (or the end), `m` the end of what still fits.
    var s = 0
    var m = 0
    var e = 0
    while s != k:
      # Find the next space or the end; at the end, stop looking.
      if e != k:
        # Leading spaces.
        if s == m and line.w == 0 and ln[s] == ' ' and
            (strip or (refStrip and line.lineWrap)):
          s = s + 1
          m = s
          # Trailing spaces were stripped, so the end is never a space.
          continue
        # When not stripping and a space was found last, move past that
        # space instead of to the next one, so the space can fit on this
        # line.
        if strip or not isSpace:
          e = findSpace(ln, m + 1)
          isSpace = true
        else:
          e = m + charLen(ln, m)
          isSpace = false
        if e == -1:
          e = k

      (lwe, lhe) = getExtents(ln.substr(s, e - 1))   # does the next word fit?
      if lwe + line.w > uw:   # too wide
        var text = ""
        var lww = 0
        var lhh = bareH
        var doLastLine = false
        # If there is already text, commit it and go to the next line.
        if s != m:
          doLastLine = true
          if (strip or refStrip) and ln[m - 1] == ' ':
            text = stripUnicodeSpace(ln.substr(s, m - 1), leading = false)
            (lww, lhh) = getExtents(text)
          else:
            text = ln.substr(s, m - 1)
            lww = lw
            lhh = lh
          s = m
        elif line.w != 0:
          doLastLine = true

        if doLastLine:
          # With text before it and an empty `text`, strip trailing spaces.
          line = addLine(text, lww, lhh, line, lines, options, lineHeight, xpad, w, h,
            pos, line.w != 0 and lww == 0)
          line.lineWrap = true
          if not dwn:
            inc pos

        # Try to fit the word on the new line; if it does not fit, break it
        # over as many lines as needed.
        if strip or (refStrip and line.lineWrap):
          s = e - stripUnicodeSpace(ln.substr(s, e - 1), trailing = false).len
        if s == e:   # it was only a stripped space
          m = s
          continue

        # Break the single word over as many lines as needed.
        m = s
        while s != e:
          # Does the rest fit on one line?
          (lwe, lhe) = getExtents(ln.substr(s, e - 1))
          if lwe + line.w <= uw:
            m = e
            break
          # If not, fit as much as possible on this line.
          while m != e and
              getExtents(ln.substr(s, m + charLen(ln, m) - 1))[0] + line.w <= uw:
            m += charLen(ln, m)
          # Not enough room for a single character: put it there anyway.
          if m == s:
            m += charLen(ln, m)
          line.isLastLine = m == k
          (lww, lhh) = getExtents(ln.substr(s, m - 1))
          line = addLine(ln.substr(s, m - 1), lww, lhh, line, lines, options, lineHeight,
            xpad, w, h, pos, false)
          line.lineWrap = true
          if not dwn:
            inc pos
          s = m
        m = s   # done with the long word, back to normal

      else:   # the word fits
        # No leading spaces on an empty line.
        if (strip or (refStrip and line.lineWrap)) and ln.substr(s, e - 1) == " " and
            line.w == 0:
          s = e
          m = e
          continue
        m = e

      if m == k:   # done
        if s != k or line.w != 0:
          line.isLastLine = endsLine   # the line ends here
          line = addLine(ln.substr(s), lwe, lhe, line, lines, options, lineHeight,
            xpad, w, h, pos, false)
        break
      # Keep this width and height, then fit more on the line.
      lw = lwe
      lh = lhe

  var val = (dwn and i != n - 1) or (not dwn and i != 0)
  # Not more lines than asked for: the loop above may have gone a few over.
  if maxLines > 0 and lines.len > maxLines:
    val = true
    if dwn:
      for x in maxLines ..< lines.len:
        h -= lines[x].h
      lines.delete(maxLines, lines.len - 1)
    else:
      let cut = max(0, lines.len - maxLines)
      for x in 0 ..< cut:
        h -= lines[x].h
      if cut > 0:
        lines.delete(0, cut - 1)

  # No lines outside the height limit.
  let k = lines.len
  if k > 1 and uh != -1 and h > uh:
    val = true
    if dwn:
      # Remove lines from the last one up, keeping the first.
      var x = k - 1
      while x > 0 and h > uh:
        h -= lines[x].h
        dec x
      if x >= 0 and x + 1 < k:
        lines.delete(x + 1, k - 1)
    else:
      # Remove lines from the first one down, keeping the last.
      var x = 0
      while x < k - 1 and h > uh:
        h -= lines[x].h
        inc x
      if x > 0:
        lines.delete(0, x - 1)
  result = (w, h, val)
