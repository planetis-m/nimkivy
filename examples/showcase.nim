## A small kiosk-like app that uses every phase-1 piece of nimkivy together,
## after the exhibition kiosk (philosykos-website/kiosk/app/ui.py):
##
## - an attract screen: two photos (`fitCover`) crossfading with Animation
##   every `slideInterval` seconds (a Clock interval), and a title; a touch
##   anywhere goes to the home screen;
## - a home screen: a header (title and a language button) and a mosaic of
##   three photo tiles (ButtonBehavior on a BoxLayout, pressed with an
##   opacity Animation);
## - a topic screen: a card in a RelativeLayout with a photo (`fitContain`),
##   wrapped text, a Listen button that plays a WAV, and prev / dots / next
##   below; a horizontal swipe also turns the card;
## - a ModalView language picker (English, Greek, German);
## - a FadeTransition between the screens, and an idle reset to the attract
##   screen after `idleTimeout` seconds without a touch (a Clock interval);
## - the header and the type follow the window height (window resize).
##
## Assets come from `tests/assets` and the fonts from `data/fonts`, so
## it runs from the repository root:
##
##   nimony c --mm:orc --path:src -o:bin/showcase examples/showcase.nim
##   bin/showcase
##
## `tests/tshowcase.nim` drives it with a scripted run.

import std/[math, syncio]
import nimkivy/[app, clock, config, animation]
import nimkivy/core/text
import nimkivy/graphics/[context_instructions, vertex_instructions]
import nimkivy/core/audio
import nimkivy/uix/[boxlayout, floatlayout, anchorlayout, relativelayout, label, image,
  screenmanager, modalview]
import nimkivy/uix/behaviors/button

export app, clock, config, animation, audio, boxlayout, floatlayout, anchorlayout,
  relativelayout, label, image, screenmanager, modalview, button

const
  Assets* = "tests/assets/"
  Photos* = ["landscape.jpg", "portrait.png", "landscape.png"]
    ## The topics' photos; the attract screen cycles through them.
  Languages* = ["en", "el", "de"]
  Fig = [0.36, 0.18, 0.27, 1.0]
  Linen = [0.98, 0.96, 0.92, 1.0]
  Charcoal = [0.17, 0.17, 0.17, 1.0]
  Leaf = [0.42, 0.53, 0.30, 1.0]

type
  Texts* = object
    ## The visible strings of one language.
    title*, home*, pick*, listen*, stop*: string
    topics*: array[3, string]
    bodies*: array[3, string]

proc texts*(lang: string): Texts =
  ## The visible strings of `lang` ("en", "el" or "de").
  case lang
  of "el":
    Texts(title: "Σύκα της Κρήτης", home: "Αρχή", pick: "Γλώσσα",
      listen: "Άκουσε", stop: "Σταμάτα",
      topics: ["Ο κήπος", "Η συγκομιδή", "Το λιοπύρι"],
      bodies: ["Οι συκιές μεγαλώνουν σε ξερές πλαγιές, κοντά στη θάλασσα.",
        "Τα σύκα μαζεύονται με το χέρι, νωρίς το πρωί, πριν ζεστάνει ο ήλιος.",
        "Στεγνώνουν στον ήλιο για μέρες, πάνω σε καλάμια, και γλυκαίνουν."])
  of "de":
    Texts(title: "Feigen aus Kreta", home: "Start", pick: "Sprache",
      listen: "Anhören", stop: "Stopp",
      topics: ["Der Garten", "Die Ernte", "Die Sonne"],
      bodies: ["Feigenbäume wachsen an trockenen Hängen nahe am Meer.",
        "Die Feigen werden früh am Morgen von Hand gepflückt, bevor es heiß wird.",
        "Sie trocknen tagelang in der Sonne auf Schilfmatten und werden süßer."])
  else:
    Texts(title: "Figs of Crete", home: "Home", pick: "Language",
      listen: "Listen", stop: "Stop",
      topics: ["The garden", "The harvest", "The sun"],
      bodies: ["Fig trees grow on dry slopes close to the sea.",
        "The figs are picked by hand early in the morning, before the heat.",
        "They dry in the sun for days on reed mats and grow sweeter."])

# ------------------------------------------------------------------ widgets

type
  Pressable* = ref object of BoxLayout
    ## A BoxLayout that is a button (the kiosk's PillButton and PhotoTile):
    ## ButtonBehavior held as a field (PORTING.md, decision 4).
    button: nil ButtonBehavior

let PressableClass = newDispatcherClass("Pressable", BoxLayoutClass)
PressableClass.addButtonBehavior()

proc bb(p: Pressable): ButtonBehavior =
  let b = p.button
  if b == nil: quit "Pressable without its ButtonBehavior"
  result = b

method onTouchDown(p: Pressable; t: MotionEvent): bool =
  p.bb.onTouchDown(t, proc (t: MotionEvent): bool {.closure.} =
    procCall onTouchDown(BoxLayout(p), t))

method onTouchMove(p: Pressable; t: MotionEvent): bool =
  p.bb.onTouchMove(t, proc (t: MotionEvent): bool {.closure.} =
    procCall onTouchMove(BoxLayout(p), t))

method onTouchUp(p: Pressable; t: MotionEvent): bool =
  p.bb.onTouchUp(t, proc (t: MotionEvent): bool {.closure.} =
    procCall onTouchUp(BoxLayout(p), t))

proc paint(w: Widget; rgba: array[4, float]) =
  # A background rectangle in canvas.before that follows the widget (the
  # kiosk's paint()).
  w.canvas.before.add newColor(rgba[0], rgba[1], rgba[2], rgba[3])
  let rect = newRectangle(w.pos, w.size)
  w.canvas.before.add rect
  discard w.bindPos(proc (v: (float, float)) {.closure.} = rect.pos = v)
  discard w.bindSize(proc (v: (float, float)) {.closure.} = rect.size = v)

proc boxedText(l: Label) =
  # The text is wrapped and aligned in the label's own box.
  discard l.bindSize(proc (v: (float, float)) {.closure.} = l.textSize = v)

proc wrapText(l: Label) =
  # The text wraps at the label's width and grows downwards.
  discard l.bindWidth(proc (v: float) {.closure.} = l.textSize = (some(v), none[float]()))

proc label(text: string; size: float; color: array[4, float]; bold = false;
    halign = halignCenter; wrap = false): Label =
  # The kiosk's label(): Source Sans 3, aligned in its box.
  result = newLabel(text)
  result.fontName = "SourceSans"
  result.fontSize = size
  result.color = color
  result.bold = bold
  result.halign = halign
  result.valign = valignMiddle
  if wrap: result.wrapText()
  else: result.boxedText()

proc pressable(vertical = false): Pressable =
  result = Pressable(cls: PressableClass, canvas: newCanvas(), button: nil)
  result.initProps()
  result.initBoxLayout()
  result.button = newButtonBehavior(result)
  if vertical: result.orientation = orientationVertical

proc pill(text: Label; fill: array[4, float]): Pressable =
  # A button with a coloured background and a label.
  result = pressable()
  result.paint(fill)
  result.addWidget(text)

proc onRelease(p: Pressable; action: proc () {.closure.}) =
  p.bind("on_release", proc (d: EventDispatcher; args: seq[Value]): bool {.closure.} =
    action()
    result = false)

proc fixedHeight(w: Widget; h: float) =
  w.sizeHintY = none[float]()
  w.height = h

proc fixedWidth(w: Widget; width: float) =
  w.sizeHintX = none[float]()
  w.width = width

# ------------------------------------------------------------------ the app

type
  Showcase* = ref object
    ## The app's state: its widgets and what is shown.
    sm*: ScreenManager
    lang*: string
    slides*: array[2, Image]     ## the attract photos; `front` is shown
    front*: int
    slide*: int                  ## the photo index the front shows
    attractTitle*: Label
    homeTitle*, topicTitle*: Label
    homeButton*, langButton*: Pressable
    langLabel*, homeLabel*: Label
    headers*: seq[BoxLayout]
    tiles*: seq[Pressable]
    tileLabels*: seq[Label]
    tileImages*: seq[Image]
    card*: int                   ## the topic shown
    cardImage*: Image
    cardText*: Label
    listen*: Pressable
    listenLabel*: Label
    prev*, next*: Pressable
    dots*: Widget
    sound*: nil Sound
    picker*: ModalView
    choices*: seq[Pressable]
    slideEv: nil ClockEvent
    lastTouch*: float            ## Clock time of the last touch down
    slideInterval*: float        ## seconds between attract photos
    fadeDuration*: float         ## the photo crossfade
    idleTimeout*: float          ## seconds without a touch before the reset
    log*: seq[string]            ## what happened, for the scripted run

  ShowcaseApp* = ref object of App
    ## The app: `build` makes the screens.
    state: nil Showcase
    slideInterval*: float        ## seconds between attract photos (6)
    fadeDuration*: float         ## the photo crossfade (1.6)
    idleTimeout*: float          ## seconds without a touch before the reset (60)

proc scale(s: Showcase): float =
  # The kiosk's sc(): sizes follow the window height (600 is 1).
  Window.height / 600.0

proc drawDots(s: Showcase) =
  # One dot per topic, the current one filled (the kiosk's draw_dots).
  let d = s.dots
  d.canvas.clear()
  let r = 7.0 * s.scale
  let gap = 4.0 * r
  let x0 = d.centerX - gap * float(Photos.len - 1) / 2.0
  for i in 0 ..< Photos.len:
    let c = if i == s.card: Fig else: [0.8, 0.8, 0.8, 1.0]
    d.canvas.add newColor(c[0], c[1], c[2], c[3])
    d.canvas.add newEllipse((x0 + float(i) * gap - r, d.centerY - r), (2.0 * r, 2.0 * r))

proc showCard*(s: Showcase; i: int; animate = true) =
  ## Shows topic `i`: its photo fades in, the text and dots follow.
  s.card = (i + Photos.len) mod Photos.len
  let t = texts(s.lang)
  s.topicTitle.text = t.topics[s.card]
  s.cardText.text = t.bodies[s.card]
  s.cardImage.source = Assets & Photos[s.card]
  if animate:
    s.cardImage.opacity = 0
    newAnimation({"opacity": 1.0}, duration = 0.35).start(s.cardImage)
  s.drawDots()
  s.log.add "card " & $s.card

proc stopVoice(s: Showcase) =
  let snd = s.sound
  if snd != nil and snd.state == statePlay: snd.stop()

proc toggleListen*(s: Showcase) =
  ## Plays the topic's clip, or stops it (the kiosk's toggle_listen).
  let snd = s.sound
  if snd == nil: return
  if snd.state == statePlay: snd.stop()
  else: snd.play()

proc applyLanguage(s: Showcase) =
  let t = texts(s.lang)
  s.attractTitle.text = t.title
  s.homeTitle.text = t.title
  s.langLabel.text = t.pick
  s.homeLabel.text = t.home
  for i in 0 ..< s.tileLabels.len: s.tileLabels[i].text = t.topics[i]
  let snd = s.sound
  s.listenLabel.text = if snd != nil and snd.state == statePlay: t.stop else: t.listen
  s.showCard(s.card, animate = false)

proc setLanguage*(s: Showcase; lang: string) =
  ## Switches every text to `lang` and closes the picker.
  s.lang = lang
  s.applyLanguage()
  s.picker.dismiss()
  s.log.add "lang " & lang

proc go*(s: Showcase; screen: string) =
  ## Changes screen (with the fade).
  if s.sm.current.get("") != screen:
    s.sm.current = screen

proc nextPhoto*(s: Showcase) =
  ## The attract crossfade: the back photo gets the next picture and fades
  ## in while the front fades out (the kiosk's next_photo).
  s.slide = (s.slide + 1) mod Photos.len
  let back = s.slides[1 - s.front]
  let front = s.slides[s.front]
  back.source = Assets & Photos[s.slide]
  newAnimation({"opacity": 1.0}, duration = s.fadeDuration).start(back)
  newAnimation({"opacity": 0.0}, duration = s.fadeDuration).start(front)
  s.front = 1 - s.front
  s.log.add "slide " & $s.slide

proc rescale(s: Showcase) =
  # The header and the type follow the window height (the kiosk's _rescale).
  let k = s.scale
  for i in 0 ..< s.headers.len: s.headers[i].height = 80.0 * k
  s.attractTitle.fontSize = 56.0 * k
  s.homeTitle.fontSize = 30.0 * k
  s.topicTitle.fontSize = 30.0 * k
  s.cardText.fontSize = 24.0 * k
  for i in 0 ..< s.tileLabels.len: s.tileLabels[i].fontSize = 22.0 * k
  s.drawDots()

# ------------------------------------------------------------------ screens

proc header(s: Showcase; title: Label; button: Pressable): BoxLayout =
  result = newBoxLayout()
  s.headers.add result
  result.fixedHeight(80)
  result.padding = [16.0, 8, 16, 8]
  result.paint(Linen)
  result.addWidget(title)
  button.fixedWidth(160)
  result.addWidget(button)

proc attractScreen(s: Showcase): Screen =
  # FloatLayout of two photos and a title; any touch goes home.
  result = newScreen("attract")
  let f = newFloatLayout()
  f.addWidget(s.slides[0])
  f.addWidget(s.slides[1])
  let shade = newAnchorLayout()
  shade.anchorY = anchorBottom
  shade.padding = [0.0, 0, 0, 40]
  s.attractTitle.fixedHeight(120)
  s.attractTitle.paint([0.0, 0, 0, 0.35])
  shade.addWidget(s.attractTitle)
  f.addWidget(shade)
  result.addWidget(f)
  discard result.bindTouchDown(proc (t: MotionEvent): bool {.closure.} =
    s.go("home")
    result = true)
  result.bind("on_enter", proc (d: EventDispatcher; args: seq[Value]): bool {.closure.} =
    s.slideEv = Clock.scheduleInterval(proc (dt: float) {.closure.} = s.nextPhoto(),
      s.slideInterval)
    result = false)
  result.bind("on_leave", proc (d: EventDispatcher; args: seq[Value]): bool {.closure.} =
    let ev = s.slideEv
    if ev != nil: ev.cancel()
    s.slideEv = nil
    result = false)

proc tile(s: Showcase; i: int): Pressable =
  # A photo tile: the photo covers its box, the caption is below.
  let p = pressable(vertical = true)
  p.paint(Linen)
  let im = newImage(Assets & Photos[i])
  im.fitMode = fitCover
  p.addWidget(im)
  let caption = label("", 22, Fig, bold = true)
  caption.fixedHeight(56)
  p.addWidget(caption)
  s.tiles.add p
  s.tileImages.add im
  s.tileLabels.add caption
  p.bind("on_press", proc (d: EventDispatcher; args: seq[Value]): bool {.closure.} =
    newAnimation({"opacity": 0.8}, duration = 0.08).start(p)
    result = false)
  p.onRelease(proc () {.closure.} =
    newAnimation({"opacity": 1.0}, duration = 0.15).start(p)
    s.showCard(i, animate = false)
    s.go("topic"))
  result = p

proc homeScreen(s: Showcase): Screen =
  result = newScreen("home")
  let col = newBoxLayout()
  col.orientation = orientationVertical
  col.addWidget(s.header(s.homeTitle, s.langButton))
  let mosaic = newBoxLayout()
  mosaic.spacing = 16
  mosaic.padding = [16.0, 16, 16, 16]
  for i in 0 ..< Photos.len: mosaic.addWidget(s.tile(i))
  col.addWidget(mosaic)
  col.paint([0.93, 0.90, 0.85, 1.0])
  result.addWidget(col)

proc topicScreen(s: Showcase): Screen =
  # Header, then the card (RelativeLayout: photo | text and Listen), then
  # prev, dots, next.
  result = newScreen("topic")
  let col = newBoxLayout()
  col.orientation = orientationVertical
  col.paint([0.93, 0.90, 0.85, 1.0])
  col.addWidget(s.header(s.topicTitle, s.homeButton))
  let card = newRelativeLayout()
  let row = newBoxLayout()
  row.padding = [24.0, 16, 24, 16]
  row.spacing = 24
  s.cardImage.fitMode = fitContain
  s.cardImage.sizeHintX = 0.45
  row.addWidget(s.cardImage)
  let right = newBoxLayout()
  right.orientation = orientationVertical
  right.spacing = 12
  right.addWidget(s.cardText)
  let anchor = newAnchorLayout()
  anchor.fixedHeight(64)
  anchor.anchorX = anchorLeft
  s.listen.fixedWidth(180)
  s.listen.fixedHeight(56)
  anchor.addWidget(s.listen)
  right.addWidget(anchor)
  row.addWidget(right)
  card.addWidget(row)
  col.addWidget(card)
  let nav = newBoxLayout()
  nav.fixedHeight(64)
  nav.padding = [24.0, 4, 24, 4]
  s.prev.fixedWidth(120)
  s.next.fixedWidth(120)
  nav.addWidget(s.prev)
  nav.addWidget(s.dots)
  nav.addWidget(s.next)
  col.addWidget(nav)
  result.addWidget(col)
  # A horizontal swipe on the card turns it (the kiosk's on_touch_up).
  discard card.bindTouchUp(proc (t: MotionEvent): bool {.closure.} =
    result = false
    let dx = t.x - t.ox
    if card.collidePoint(t.ox, t.oy) and abs(dx) > 80.0 * s.scale:
      s.showCard(s.card + (if dx < 0: 1 else: -1))
      result = true)
  result.bind("on_leave", proc (d: EventDispatcher; args: seq[Value]): bool {.closure.} =
    s.stopVoice()
    result = false)

proc choice(s: Showcase; lang, name: string): Pressable =
  # One language: a flag and its name. A proc of its own, so each closure
  # has its own `lang` (closures made in a loop share the loop's variables).
  let p = pressable(vertical = true)
  p.paint(Linen)
  p.addWidget(newImage(Assets & "flag.png"))
  let l = label(name, 22, Charcoal)
  l.fixedHeight(40)
  p.addWidget(l)
  p.onRelease(proc () {.closure.} = s.setLanguage(lang))
  s.choices.add p
  result = p

proc languagePicker(s: Showcase): ModalView =
  # A row of three choices, each a flag and a name.
  let m = newModalView()
  m.sizeHint = (0.7, 0.4)
  m.backgroundColor = Linen
  m.animDuration = 0.1
  let row = newBoxLayout()
  row.padding = [16.0, 16, 16, 16]
  row.spacing = 16
  for (lang, name) in [("en", "English"), ("el", "Ελληνικά"), ("de", "Deutsch")]:
    row.addWidget(s.choice(lang, name))
  m.addWidget(row)
  result = m

proc newShowcase*(slideInterval = 6.0; fadeDuration = 1.6; idleTimeout = 60.0): Showcase =
  ## Makes the widgets and the screens; the attract screen is current.
  let slides = [newImage(Assets & Photos[0]), newImage()]
  for im in slides: im.fitMode = fitCover
  slides[1].opacity = 0
  let s = Showcase(sm: newScreenManager(), lang: "en", slides: slides, front: 0, slide: 0,
    attractTitle: label("", 56, Linen, bold = true),
    homeTitle: label("", 30, Fig, bold = true, halign = halignLeft),
    topicTitle: label("", 30, Fig, bold = true, halign = halignLeft),
    homeButton: pressable(), langButton: pressable(),
    langLabel: label("", 22, Linen), homeLabel: label("", 22, Linen),
    headers: @[], tiles: @[], tileLabels: @[], tileImages: @[], card: 0,
    cardImage: newImage(), cardText: label("", 24, Charcoal, halign = halignLeft, wrap = true),
    listen: pressable(), listenLabel: label("", 22, Linen, bold = true),
    prev: pill(label("<", 30, Linen, bold = true), Fig),
    next: pill(label(">", 30, Linen, bold = true), Fig),
    dots: newWidget(), sound: loadSound(Assets & "tone.wav"), picker: newModalView(),
    choices: @[], slideEv: nil, lastTouch: 0, slideInterval: slideInterval,
    fadeDuration: fadeDuration, idleTimeout: idleTimeout, log: @[])
  s.homeButton.paint(Fig)
  s.homeButton.addWidget(s.homeLabel)
  s.langButton.paint(Fig)
  s.langButton.addWidget(s.langLabel)
  s.listen.paint(Leaf)
  s.listen.addWidget(s.listenLabel)
  s.picker = s.languagePicker()
  s.homeButton.onRelease(proc () {.closure.} = s.go("home"))
  s.langButton.onRelease(proc () {.closure.} = s.picker.open())
  s.listen.onRelease(proc () {.closure.} = s.toggleListen())
  s.prev.onRelease(proc () {.closure.} = s.showCard(s.card - 1))
  s.next.onRelease(proc () {.closure.} = s.showCard(s.card + 1))
  discard s.dots.bindPos(proc (v: (float, float)) {.closure.} = s.drawDots())
  discard s.dots.bindSize(proc (v: (float, float)) {.closure.} = s.drawDots())
  let snd = s.sound
  if snd != nil:
    snd.bind("on_play", proc (d: EventDispatcher; args: seq[Value]): bool {.closure.} =
      s.listenLabel.text = texts(s.lang).stop
      s.log.add "play"
      result = false)
    snd.bind("on_stop", proc (d: EventDispatcher; args: seq[Value]): bool {.closure.} =
      s.listenLabel.text = texts(s.lang).listen
      s.log.add "stop"
      result = false)
  let fade = newFadeTransition()
  fade.duration = 0.25
  s.sm.transition = fade
  s.sm.addWidget(s.attractScreen())
  s.sm.addWidget(s.homeScreen())
  s.sm.addWidget(s.topicScreen())
  s.sm.bind("current", proc (d: EventDispatcher; v: Value) {.closure.} =
    if v.kind == vkString: s.log.add "screen " & v.str)
  s.applyLanguage()
  result = s

proc idleCheck(s: Showcase) =
  # The kiosk's tick: back to the attract screen after idleTimeout.
  if s.sm.current.get("") != "attract" and Clock.getTime() - s.lastTouch > s.idleTimeout:
    s.stopVoice()
    if s.picker.isOpen: s.picker.dismiss(animation = false)
    s.log.add "idle reset"
    s.go("attract")

method build(a: ShowcaseApp): nil WidgetBase =
  register("SourceSans", Assets & "fonts/SourceSans3-Regular.ttf",
    fnBold = Assets & "fonts/SourceSans3-SemiBold.ttf")
  let s = newShowcase(a.slideInterval, a.fadeDuration, a.idleTimeout)
  a.state = s
  s.lastTouch = Clock.getTime()
  Window.clearcolor = [0.0, 0.0, 0.0, 1.0]
  discard Window.bindTouchDown(proc (t: MotionEvent): bool {.closure.} =
    s.lastTouch = Clock.getTime()
    result = false)
  discard Window.bindSize(proc (v: (float, float)) {.closure.} = s.rescale())
  s.rescale()
  discard Clock.scheduleInterval(proc (dt: float) {.closure.} = s.idleCheck(), 0.25)
  result = s.sm

proc newShowcaseApp*(): ShowcaseApp =
  ## The app; `run` opens the window and shows the attract screen.
  result = ShowcaseApp(state: nil, slideInterval: 6, fadeDuration: 1.6, idleTimeout: 60)
  result.initApp("ShowcaseApp")

proc show*(a: ShowcaseApp): Showcase =
  ## The app's state, once built.
  let s = a.state
  if s == nil: quit "the showcase is not built yet"
  result = s

when isMainModule:
  Config.graphics.width = 1024
  Config.graphics.height = 600
  newShowcaseApp().run()
