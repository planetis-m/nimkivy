## The label: Kivy's `kivy/uix/label.py` (Label), with its rule from
## `kivy/data/style.kv`.
##
## A label renders its text with a core label (`core/text`, through the
## SDL3_ttf provider) into `texture`, whose size is `textureSize`. Every
## property that changes the rendering schedules `textureUpdate` through a
## Clock trigger that runs before the next frame (timeout -1), as Kivy's
## does; call `textureUpdate` to render at once. Each font property is
## passed on to the core label by its own typed observer. The canvas draws
## the texture in white at its own size, centred on the widget (rounded
## down to whole pixels); the text is wrapped and aligned only inside
## `textSize`, which is `(none, none)` by default.
##
## Build a label with `newLabel()`; a subclass's constructor makes the
## object, calls `initProps`, then `initLabel`.
##
## Out of scope (SCOPE.md): markup, `refs`, `anchors` and `on_ref_press`,
## `shorten` and its options, `max_lines`, `strip`, outlines, underline,
## strikethrough, `mipmap`, `font_family`, `font_context`, `font_features`,
## `font_script_name`, `font_direction`, `base_direction`, `text_language`,
## `unicode_errors`, `limit_render_to_text_bbox`, `is_shortened`, and the
## deprecated `padding_x` and `padding_y`.

import std/[opt, syncio]
import ../[properties, props, clock, metrics]
import ../graphics/[texture, context_instructions, vertex_instructions]
import ../core/text
import ../core/text/text_sdl3
import widget

export widget, text

let LabelClass* = newDispatcherClass("Label", WidgetClass)
  ## The class of `Label`, a name only (see `WidgetClass`).

properties:
  type
    Label* = ref object of Widget
      ## uix/label.py Label
      core: nil LabelBase            # _label: the core label
      triggerTexture: nil ClockEvent # _trigger_texture
      disabledColor* {.color.}: Rgba = [1.0, 1, 1, 0.3]  ## the text colour while disabled
      text* {.prop.}: string = ""   ## the text to show
      textSize* {.prop.}: TextSize = (none[float](), none[float]())
        ## the box the text is wrapped and aligned in; none is no limit
      fontName* {.prop.}: string = "Roboto"
        ## a registered font name, a font file, or a name in data/fonts
      fontSize* {.prop.}: float = 15.0  ## the font size in pixels (`sp(15)` when made)
      lineHeight* {.prop.}: float = 1.0  ## the line height, a multiple of the font height
      bold* {.prop.}: bool = false   ## the bold file of the font is used
      italic* {.prop.}: bool = false ## the italic file of the font is used
      padding* {.varlist: 4.}: array[4, float] = [0.0, 0.0, 0.0, 0.0]
        ## left, top, right and bottom padding around the text in the texture
      halign* {.prop.}: Halign = halignAuto  ## the alignment of the lines in `textSize`
      valign* {.prop.}: Valign = valignBottom  ## the alignment of the text in `textSize`
      color* {.color.}: Rgba = [1.0, 1, 1, 1]  ## the text colour
      texture* {.prop.}: nil Texture = nil
        ## the rendered text; nil before the first render and for empty text
      textureSize* {.prop.}: (float, float) = (0.0, 0.0)
        ## the size of `texture`, padding included; (0, 0) without text
      fontHinting* {.prop.}: FontHinting = hintingNormal
        ## the FreeType hinting (`hintingNone` is Kivy's None)
      fontKerning* {.prop.}: bool = true  ## kerning is on
      fontBlended* {.prop.}: bool = true  ## glyphs are antialiased

  proc `textSize=`*(l: Label; v: (float, float)) =
    ## Sets the box the text is wrapped and aligned in.
    l.textSize = (some(v[0]), some(v[1]))

  # ---------------------------------------------------------------- the core label

  proc coreLabel(l: Label): LabelBase =
    let c = l.core
    if c == nil:
      quit "Label: initLabel was not called"
    result = c

  proc createLabel(l: Label) =
    # Label._create_label, without markup: a core label with every font
    # property; the disabled colour while disabled.
    let core = newLabelSDL3()
    let o = core.options
    core.text = l.text
    core.textSize = l.textSize
    o.fontSize = l.fontSize
    o.fontName = l.fontName
    o.bold = l.bold
    o.italic = l.italic
    o.color = if l.disabled: l.disabledColor else: l.color
    o.halign = l.halign
    o.valign = l.valign
    o.padding = l.padding
    o.lineHeight = l.lineHeight
    o.fontHinting = l.fontHinting
    o.fontKerning = l.fontKerning
    o.fontBlended = l.fontBlended
    l.core = core

  proc scheduleRender(l: Label) =
    # Label._trigger_texture(): a render before the next frame.
    let t = l.triggerTexture
    if t != nil: t.trigger()

  proc bindFontProperties(l: Label) =
    # Label._trigger_texture_update bound to each font property, in Kivy's
    # order (Label._font_properties): passes the value on to the core label
    # and schedules a render. While disabled, the core label's colour is
    # `disabledColor`, so a change of `color` does nothing.
    discard l.bindText(proc (v: string) {.closure.} =
      l.coreLabel.text = v
      l.scheduleRender())
    discard l.bindFontSize(proc (v: float) {.closure.} =
      l.coreLabel.options.fontSize = v
      l.scheduleRender())
    discard l.bindFontName(proc (v: string) {.closure.} =
      l.coreLabel.options.fontName = v
      l.scheduleRender())
    discard l.bindBold(proc (v: bool) {.closure.} =
      l.coreLabel.options.bold = v
      l.scheduleRender())
    discard l.bindItalic(proc (v: bool) {.closure.} =
      l.coreLabel.options.italic = v
      l.scheduleRender())
    discard l.bindColor(proc (v: Rgba) {.closure.} =
      if not l.disabled:
        l.coreLabel.options.color = v
        l.scheduleRender())
    discard l.bindDisabledColor(proc (v: Rgba) {.closure.} =
      if l.disabled: l.coreLabel.options.color = v
      l.scheduleRender())
    discard l.bindHalign(proc (v: Halign) {.closure.} =
      l.coreLabel.options.halign = v
      l.scheduleRender())
    discard l.bindValign(proc (v: Valign) {.closure.} =
      l.coreLabel.options.valign = v
      l.scheduleRender())
    discard l.bindPadding(proc (v: array[4, float]) {.closure.} =
      l.coreLabel.options.padding = v
      l.scheduleRender())
    discard l.bindTextSize(proc (v: TextSize) {.closure.} =
      l.coreLabel.textSize = v
      l.scheduleRender())
    discard l.bindLineHeight(proc (v: float) {.closure.} =
      l.coreLabel.options.lineHeight = v
      l.scheduleRender())
    discard l.bindFontHinting(proc (v: FontHinting) {.closure.} =
      l.coreLabel.options.fontHinting = v
      l.scheduleRender())
    discard l.bindFontKerning(proc (v: bool) {.closure.} =
      l.coreLabel.options.fontKerning = v
      l.scheduleRender())
    discard l.bindFontBlended(proc (v: bool) {.closure.} =
      l.coreLabel.options.fontBlended = v
      l.scheduleRender())

  # ---------------------------------------------------------------- rendering

  proc textureUpdate*(l: Label) =
    ## Renders the text now and sets `texture` and `textureSize`. Empty
    ## text, or only spaces with halign justify, has no texture and a size
    ## of (0, 0). Label.texture_update
    let core = l.coreLabel
    l.texture = nil
    if core.text.len == 0 or (l.halign == halignJustify and pyStrip(core.text).len == 0):
      l.textureSize = (0.0, 0.0)
    else:
      core.refresh()
      let t = core.texture
      if t != nil:
        l.texture = t
        let (w, h) = t.size
        l.textureSize = (float(w), float(h))

  proc place(l: Label; rect: Rectangle) =
    # The texture's position: int(center - texture_size / 2). Python's int()
    # rounds toward zero, as Nim's conversion does.
    let (tw, th) = l.textureSize
    rect.pos = (float(int(l.centerX - tw / 2.0)), float(int(l.centerY - th / 2.0)))

  proc applyStyle(l: Label) =
    # data/style.kv <Label>: Color 1, 1, 1, 1, and a Rectangle with the
    # texture, size texture_size, at int(center - texture_size / 2). Each kv
    # binding becomes an observer.
    l.canvas.add newColor(1, 1, 1, 1)
    let rect = newRectangle()
    l.canvas.add rect
    rect.texture = l.texture
    rect.size = l.textureSize
    l.place(rect)
    discard l.bindTexture(proc (v: nil Texture) {.closure.} = rect.texture = v)
    discard l.bindTextureSize(proc (v: (float, float)) {.closure.} =
      rect.size = v
      l.place(rect))
    discard l.bindCenterX(proc (v: float) {.closure.} = l.place(rect))
    discard l.bindCenterY(proc (v: float) {.closure.} = l.place(rect))

  proc initLabel*(l: Label) =
    ## Sets up a new label whose properties `initProps` has set: the widget,
    ## the style.kv canvas, the observers that schedule a render, the core
    ## label, and a first render before the next frame. Label.__init__
    l.initWidget()
    l.triggerTexture = Clock.createTrigger(proc (dt: float) {.closure.} = l.textureUpdate(),
      -1)
    l.applyStyle()
    # NumericProperty('15sp'): the unit is resolved when the instance is made,
    # once the window has set the metrics.
    l.fontSize = sp(15)
    discard l.bindDisabled(proc (v: bool) {.closure.} =
      l.coreLabel.options.color = if v: l.disabledColor else: l.color
      l.scheduleRender())
    l.bindFontProperties()
    l.createLabel()
    l.scheduleRender()

  proc newLabel*(): Label =
    ## A label with no text, rendered before the next frame.
    result = Label(cls: LabelClass, canvas: newCanvas(), core: nil, triggerTexture: nil)
    result.initProps()
    result.initLabel()

  proc newLabel*(text: string): Label =
    ## A label showing `text`.
    result = newLabel()
    result.text = text
