## The label: Kivy's `kivy/uix/label.py` (Label), with its rule from
## `kivy/data/style.kv`.
##
## A label renders its text with a core label (`core/text`, through the
## SDL3_ttf provider) into `texture`, whose size is `texture_size`. Every
## property that changes the rendering schedules `textureUpdate` through a
## Clock trigger that runs before the next frame (timeout -1), as Kivy's
## does; call `textureUpdate` to render at once. The canvas draws the
## texture in white at its own size, centred on the widget (rounded down to
## whole pixels); the text is wrapped and aligned only inside `text_size`,
## which is unset (None, None) by default.
##
## Out of scope (SCOPE.md): markup, `refs`, `anchors` and `on_ref_press`,
## `shorten` and its options, `max_lines`, `strip`, outlines, underline,
## strikethrough, `mipmap`, `font_family`, `font_context`, `font_features`,
## `font_script_name`, `font_direction`, `base_direction`, `text_language`,
## `unicode_errors`, `limit_render_to_text_bbox`, `is_shortened`, and the
## deprecated `padding_x` and `padding_y`.

import std/[opt, syncio]
import ../[properties, clock, metrics]
import ../graphics/[texture, context_instructions, vertex_instructions]
import ../core/text
import ../core/text/text_sdl3
import widget

export widget, text

type
  Label* = ref object of Widget
    ## uix/label.py Label
    core: nil LabelBase            # _label: the core label
    triggerTexture: nil ClockEvent # _trigger_texture

let LabelClass* = newDispatcherClass("Label", WidgetClass)
  ## The class of `Label`.

const fontProperties = ["text", "font_size", "font_name", "bold", "italic", "color",
  "disabled_color", "halign", "valign", "padding", "text_size", "line_height",
  "font_hinting", "font_kerning", "font_blended"]
  # Label._font_properties, for the properties in scope, in Kivy's order.

let pDisabledColor = LabelClass.addColor("disabled_color", @[1.0, 1, 1, 0.3])
let pText = LabelClass.addString("text", "")
let pTextSize = LabelClass.addList("text_size", @[noneValue(), noneValue()])
let pFontName = LabelClass.addString("font_name", "Roboto")
let pFontSize = LabelClass.addNumeric("font_size", 15)
let pLineHeight = LabelClass.addNumeric("line_height", 1.0)
let pBold = LabelClass.addBoolean("bold", false)
let pItalic = LabelClass.addBoolean("italic", false)
let pPadding = LabelClass.addVariableList("padding", @[0.0, 0, 0, 0], 4)
let pHalign = LabelClass.addOption("halign", "auto",
  @["left", "center", "right", "justify", "auto"])
let pValign = LabelClass.addOption("valign", "bottom",
  @["bottom", "middle", "center", "top"])
let pColor = LabelClass.addColor("color", @[1.0, 1, 1, 1])
let pTexture = LabelClass.addObject("texture", noneValue(), allowNone = true)
let pTextureSize = LabelClass.addList("texture_size", @[toValue(0.0), toValue(0.0)])
let pFontHinting = newOptionProperty("normal", @["normal", "light", "mono"],
  allowNone = true)
LabelClass.addProperty("font_hinting", pFontHinting)
let pFontKerning = LabelClass.addBoolean("font_kerning", true)
let pFontBlended = LabelClass.addBoolean("font_blended", true)

# ------------------------------------------------------------------ the core label

proc toTextSize(v: Value): TextSize =
  # `text_size` (a list of two numbers or None) as the core label's TextSize.
  var w = none[float]()
  var h = none[float]()
  if v.kind == vkList and v.items.len == 2:
    if v.items[0].kind == vkNumber: w = some(v.items[0].num)
    if v.items[1].kind == vkNumber: h = some(v.items[1].num)
  result = (w, h)

proc toArray4(v: Value): array[4, float] =
  # A colour or a padding: four numbers.
  let c = v.toFloats
  result = [c[0], c[1], c[2], c[3]]

proc toHinting(v: Value): FontHinting =
  # font_hinting: None is no hinting.
  if v.kind != vkString: hintingNone
  else:
    case v.str
    of "light": hintingLight
    of "mono": hintingMono
    else: hintingNormal

proc setOption(core: LabelBase; name: string; value: Value) =
  # `self._label.options[name] = value`, `.text` and `.usersize`, for the
  # names Label passes on. disabled_color is only read through `color`.
  let o = core.options
  case name
  of "text": core.text = value.str
  of "text_size": core.textSize = toTextSize(value)
  of "font_size": o.fontSize = value.num
  of "font_name": o.fontName = value.str
  of "bold": o.bold = value.flag
  of "italic": o.italic = value.flag
  of "color": o.color = toArray4(value)
  of "halign": o.halign = parseHalign(value.str)
  of "valign": o.valign = parseValign(value.str)
  of "padding": o.setPadding(value.toFloats)
  of "line_height": o.lineHeight = value.num
  of "font_hinting": o.fontHinting = toHinting(value)
  of "font_kerning": o.fontKerning = value.flag
  of "font_blended": o.fontBlended = value.flag
  else: discard

proc coreLabel(l: Label): LabelBase =
  let c = l.core
  if c == nil:
    quit "Label: initLabel was not called"
  result = c

proc createLabel(l: Label) =
  # Label._create_label, without markup: a core label with every font
  # property; the disabled colour while disabled.
  let core = newLabelSDL3()
  for name in fontProperties:
    core.setOption(name, l.getProperty(name))
  if l.disabled:
    core.setOption("color", pDisabledColor.get(l))
  l.core = core

proc triggerTextureUpdate(l: Label; name: string; value: Value) =
  # Label._trigger_texture_update, called by the observer of `name`.
  let core = l.coreLabel
  case name
  of "disabled_color":
    if l.disabled: core.setOption("color", value)
  of "disabled":
    core.setOption("color", if value.flag: pDisabledColor.get(l) else: pColor.get(l))
  of "color":
    if l.disabled: return
    core.setOption(name, value)
  else:
    core.setOption(name, value)
  let t = l.triggerTexture
  if t != nil: t.trigger()

proc updateOn(l: Label; name: string): PropertyCallback =
  # `fbind(name, self._trigger_texture_update, name)`
  result = proc (d: EventDispatcher; v: Value) {.closure.} = l.triggerTextureUpdate(name, v)

# ------------------------------------------------------------------ accessors

proc text*(l: Label): string {.inline.} =
  ## The text to show.
  pText.getString(l)
proc `text=`*(l: Label; v: string) {.inline.} =
  ## Sets the text.
  discard pText.set(l, toValue(v))
proc fontName*(l: Label): string {.inline.} =
  ## A registered font name, a font file, or a name in data/fonts
  ## (default `Roboto`).
  pFontName.getString(l)
proc `fontName=`*(l: Label; v: string) {.inline.} =
  ## Sets the font.
  discard pFontName.set(l, toValue(v))
proc fontSize*(l: Label): float {.inline.} =
  ## The font size in pixels (default `sp(15)`).
  pFontSize.getNumber(l)
proc `fontSize=`*(l: Label; v: float) {.inline.} =
  ## Sets the font size in pixels.
  pFontSize.setNumber(l, v)
proc bold*(l: Label): bool {.inline.} =
  ## Whether the bold file of the font is used.
  pBold.getBool(l)
proc `bold=`*(l: Label; v: bool) {.inline.} =
  ## Uses the bold file of the font, or not.
  discard pBold.set(l, toValue(v))
proc italic*(l: Label): bool {.inline.} =
  ## Whether the italic file of the font is used.
  pItalic.getBool(l)
proc `italic=`*(l: Label; v: bool) {.inline.} =
  ## Uses the italic file of the font, or not.
  discard pItalic.set(l, toValue(v))
proc color*(l: Label): array[4, float] {.inline.} =
  ## The text colour (default white).
  toArray4(pColor.get(l))
proc `color=`*(l: Label; v: array[4, float]) {.inline.} =
  ## Sets the text colour.
  pColor.setFloats(l, v)
proc disabledColor*(l: Label): array[4, float] {.inline.} =
  ## The text colour while disabled (default white at 0.3 alpha).
  toArray4(pDisabledColor.get(l))
proc `disabledColor=`*(l: Label; v: array[4, float]) {.inline.} =
  ## Sets the text colour while disabled.
  pDisabledColor.setFloats(l, v)
proc halign*(l: Label): Halign {.inline.} =
  ## The horizontal alignment of the lines in `text_size` (default auto).
  parseHalign(pHalign.get(l).str)
proc `halign=`*(l: Label; v: Halign) {.inline.} =
  ## Sets the horizontal alignment.
  discard pHalign.set(l, toValue($v))
proc valign*(l: Label): Valign {.inline.} =
  ## The vertical alignment of the text in `text_size` (default bottom).
  parseValign(pValign.get(l).str)
proc `valign=`*(l: Label; v: Valign) {.inline.} =
  ## Sets the vertical alignment.
  discard pValign.set(l, toValue($v))
proc textSize*(l: Label): TextSize {.inline.} =
  ## The box the text is wrapped and aligned in; none is no limit.
  toTextSize(pTextSize.get(l))
proc `textSize=`*(l: Label; v: TextSize) =
  ## Sets the box the text is wrapped and aligned in.
  let w = if v.w.isSome: toValue(v.w.get(0)) else: noneValue()
  let h = if v.h.isSome: toValue(v.h.get(0)) else: noneValue()
  discard pTextSize.set(l, toValue(@[w, h]))
proc `textSize=`*(l: Label; v: (float, float)) =
  ## Sets the box the text is wrapped and aligned in.
  discard pTextSize.set(l, toValue([v[0], v[1]]))
proc lineHeight*(l: Label): float {.inline.} =
  ## The line height, as a multiple of the font height (default 1).
  pLineHeight.getNumber(l)
proc `lineHeight=`*(l: Label; v: float) {.inline.} =
  ## Sets the line height multiplier.
  pLineHeight.setNumber(l, v)
proc padding*(l: Label): array[4, float] {.inline.} =
  ## Left, top, right and bottom padding around the text in the texture.
  toArray4(pPadding.get(l))
proc `padding=`*(l: Label; v: openArray[float]) =
  ## Sets the padding from 1, 2 (horizontal, vertical) or 4 values.
  discard pPadding.set(l, toValue(v))
proc fontHinting*(l: Label): FontHinting {.inline.} =
  ## The FreeType hinting (default normal; `hintingNone` is Kivy's None).
  toHinting(pFontHinting.get(l))
proc `fontHinting=`*(l: Label; v: FontHinting) =
  ## Sets the hinting.
  discard pFontHinting.set(l, if v == hintingNone: noneValue() else: toValue($v))
proc fontKerning*(l: Label): bool {.inline.} =
  ## Whether kerning is on (default true).
  pFontKerning.getBool(l)
proc `fontKerning=`*(l: Label; v: bool) {.inline.} =
  ## Turns kerning on or off.
  discard pFontKerning.set(l, toValue(v))
proc fontBlended*(l: Label): bool {.inline.} =
  ## Whether glyphs are antialiased (default true).
  pFontBlended.getBool(l)
proc `fontBlended=`*(l: Label; v: bool) {.inline.} =
  ## Turns antialiasing on or off.
  discard pFontBlended.set(l, toValue(v))
proc texture*(l: Label): nil Texture {.inline.} =
  ## The rendered text; nil before the first render and for empty text.
  toTexture(pTexture.get(l))
proc textureSize*(l: Label): (float, float) =
  ## The size of `texture`, padding included; (0, 0) without text.
  let v = pTextureSize.get(l)
  result = (v.items[0].num, v.items[1].num)
proc `textureSize=`*(l: Label; v: (float, float)) =
  ## Sets `texture_size` (Label sets it after each render).
  discard pTextureSize.set(l, toValue([v[0], v[1]]))

# ------------------------------------------------------------------ rendering

proc textureUpdate*(l: Label) =
  ## Renders the text now and sets `texture` and `texture_size`. Empty
  ## text, or only spaces with halign justify, has no texture and a size
  ## of (0, 0). Label.texture_update
  let core = l.coreLabel
  discard pTexture.set(l, noneValue())
  if core.text.len == 0 or (l.halign == halignJustify and pyStrip(core.text).len == 0):
    l.textureSize = (0.0, 0.0)
  else:
    core.refresh()
    let t = core.texture
    if t != nil:
      discard pTexture.set(l, toValue(t))
      let (w, h) = t.size
      l.textureSize = (float(w), float(h))

proc applyStyle(l: Label) =
  # data/style.kv <Label>: Color 1, 1, 1, 1, and a Rectangle with the
  # texture, size texture_size, at int(center - texture_size / 2). Each kv
  # binding becomes an observer.
  l.canvas.add newColor(1, 1, 1, 1)
  let rect = newRectangle()
  l.canvas.add rect
  proc place(l: Label; rect: Rectangle) =
    let (tw, th) = l.textureSize
    # Python's int() rounds toward zero, as Nim's conversion does.
    rect.pos = (float(int(l.centerX - tw / 2.0)), float(int(l.centerY - th / 2.0)))
  rect.texture = l.texture
  rect.size = l.textureSize
  place(l, rect)
  discard l.fbind("texture", proc (d: EventDispatcher; v: Value) {.closure.} =
    rect.texture = toTexture(v))
  discard l.fbind("texture_size", proc (d: EventDispatcher; v: Value) {.closure.} =
    rect.size = (v.items[0].num, v.items[1].num)
    place(l, rect))
  discard l.bindCenterX(proc (v: float) {.closure.} = place(l, rect))
  discard l.bindCenterY(proc (v: float) {.closure.} = place(l, rect))

proc initLabel*(l: Label) =
  ## Sets up a new label: the widget, the style.kv canvas, the observers
  ## that schedule a render, the core label, and a first render before the
  ## next frame. Build it with `Label(cls: LabelClass, canvas: newCanvas())`
  ## (or a subclass's class). Label.__init__
  # Phase 1 until step 4: the typed properties of the base types.
  l.initProps()
  l.initWidget()
  l.triggerTexture = Clock.createTrigger(proc (dt: float) {.closure.} = l.textureUpdate(),
    -1)
  l.applyStyle()
  # NumericProperty('15sp'): the unit is resolved when the instance is made,
  # once the window has set the metrics.
  l.fontSize = sp(15)
  discard l.bindDisabled(proc (v: bool) {.closure.} =
    l.triggerTextureUpdate("disabled", toValue(v)))
  for name in fontProperties:
    discard l.fbind(name, l.updateOn(name))
  l.createLabel()
  let t = l.triggerTexture
  if t != nil: t.trigger()

proc newLabel*(): Label =
  ## A label with no text, rendered before the next frame.
  result = Label(cls: LabelClass, canvas: newCanvas(), core: nil, triggerTexture: nil)
  result.initLabel()

proc newLabel*(text: string): Label =
  ## A label showing `text`.
  result = newLabel()
  result.text = text
