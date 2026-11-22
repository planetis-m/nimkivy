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
## The widget trees are written with `buildUi` (nimkivy/buildui), as a kv
## file would be; the components (`Pill`, `Panel`, `Tile`, `Caption`, ...)
## are procs named `newX`, as kv's class rules. The app's logic is in the
## procs on `Showcase`; the handlers in the trees reach it through the app
## (`app.show`), as kv's `app.`.
##
## Assets come from `tests/assets` and the fonts from `data/fonts`, so
## it runs from the repository root:
##
##   nimony c --mm:orc --path:src -o:bin/showcase examples/showcase.nim
##   bin/showcase
##
## `tests/tshowcase.nim` drives it with a scripted run.

import std/[math, syncio]
import nimkivy/[app, clock, config, animation, buildui]
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
  Sand = [0.93, 0.90, 0.85, 1.0]

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

# ------------------------------------------------------------------ components

type
  Pressable* = ref object of BoxLayout
    ## A BoxLayout that is a button (the kiosk's PillButton and PhotoTile):
    ## it owns a ButtonBehavior (PORTING.md, decision 4).
    button: ButtonBehavior

method onTouchDown(p: Pressable; t: MotionEvent): bool =
  result = procCall onTouchDown(BoxLayout(p), t)
  if not result: result = p.button.touchDown(p, t)

method onTouchMove(p: Pressable; t: MotionEvent): bool =
  result = p.button.grabbed(p, t)
  if not result: result = procCall onTouchMove(BoxLayout(p), t)
  if not result: result = p.button.touchMove(p, t)

method onTouchUp(p: Pressable; t: MotionEvent): bool =
  if p.button.grabbed(p, t): result = p.button.touchUp(p, t)
  else: result = procCall onTouchUp(BoxLayout(p), t)

proc newPressable*(): Pressable =
  ## A horizontal Pressable.
  result = Pressable(canvas: newCanvas(), button: newButtonBehavior())
  result.initProps()
  result.initBoxLayout()

proc newPill(fill: Rgba): Pressable =
  # A Pressable on a coloured background (the kiosk's paint()).
  buildUi:
    Pressable as p:
      canvas.before:
        Color(rgba = fill)
        Rectangle(pos <- self.pos, size <- self.size)
  result = p

proc newPanel(fill: Rgba): BoxLayout =
  # A BoxLayout on a coloured background.
  buildUi:
    BoxLayout as b:
      canvas.before:
        Color(rgba = fill)
        Rectangle(pos <- self.pos, size <- self.size)
  result = b

proc newTile(): Pressable =
  # A photo tile: dims while it is pressed (the kiosk's PhotoTile).
  buildUi:
    Pill(Linen, orientation = orientationVertical) as p:
      on button.press:
        newAnimation([opacityTo(Widget, 0.8)], duration = 0.08).start(self)
      on button.release:
        newAnimation([opacityTo(Widget, 1.0)], duration = 0.15).start(self)
  result = p

proc newCaption(text = ""): Label =
  # The kiosk's label(): Source Sans 3, centred in its own box.
  buildUi:
    Label(text, fontName = "SourceSans", halign = halignCenter, valign = valignMiddle) as l:
      textSize <- self.size
  result = l

proc newParagraph(): Label =
  # Source Sans 3 that wraps at the label's width and grows downwards.
  buildUi:
    Label(fontName = "SourceSans", valign = valignMiddle) as l:
      textSize <- (some(self.width), none[float]())
  result = l

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

proc show*(a: ShowcaseApp): Showcase =
  ## The app's state, once built.
  let s = a.state
  if s == nil: quit "the showcase is not built yet"
  result = s

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
    newAnimation([opacityTo(Widget, 1.0)], duration = 0.35).start(s.cardImage)
  s.drawDots()
  s.log.add "card " & $s.card

proc swipe(s: Showcase; card: Widget; t: MotionEvent): bool =
  # A horizontal swipe on the card turns it (the kiosk's on_touch_up).
  result = false
  let dx = t.x - t.ox
  if card.collidePoint(t.ox, t.oy) and abs(dx) > 80.0 * s.scale:
    s.showCard(s.card + (if dx < 0: 1 else: -1))
    result = true

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

proc openTopic(s: Showcase; i: int) =
  # A tile was released: its topic, on the topic screen.
  s.showCard(i, animate = false)
  s.go("topic")

proc nextPhoto*(s: Showcase) =
  ## The attract crossfade: the back photo gets the next picture and fades
  ## in while the front fades out (the kiosk's next_photo).
  s.slide = (s.slide + 1) mod Photos.len
  let back = s.slides[1 - s.front]
  let front = s.slides[s.front]
  back.source = Assets & Photos[s.slide]
  newAnimation([opacityTo(Widget, 1.0)], duration = s.fadeDuration).start(back)
  newAnimation([opacityTo(Widget, 0.0)], duration = s.fadeDuration).start(front)
  s.front = 1 - s.front
  s.log.add "slide " & $s.slide

proc startSlides(s: Showcase) =
  # The attract screen came in: a new photo every slideInterval.
  s.slideEv = Clock.scheduleInterval(proc (dt: float) {.closure.} = s.nextPhoto(),
    s.slideInterval)

proc stopSlides(s: Showcase) =
  let ev = s.slideEv
  if ev != nil: ev.cancel()
  s.slideEv = nil

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

proc newChoice(app: ShowcaseApp; lang, name: string): Pressable =
  # One language of the picker: a flag and its name.
  buildUi:
    Pill(Linen, orientation = orientationVertical) as p:
      on button.release:
        app.show.setLanguage(lang)
      Image(Assets & "flag.png")
      Caption(name, fontSize = 22, color = Charcoal, sizeHintY = none[float](), height = 40)
  result = p

proc newShowcase*(app: ShowcaseApp): Showcase =
  ## Makes the widgets and the screens; the attract screen is current.
  let fade = newFadeTransition()
  fade.duration = 0.25
  buildUi:
    Screen("attract") as attract:
      # Two photos and a title; any touch goes home.
      on touchDown(t: MotionEvent):
        app.show.go("home")
        result = true
      on enter:
        app.show.startSlides()
      on leave:
        app.show.stopSlides()
      FloatLayout:
        Image(Assets & Photos[0], fitMode = fitCover) as slide0
        Image(fitMode = fitCover, opacity = 0) as slide1
        AnchorLayout(anchorY = anchorBottom, padding = [0.0, 0, 0, 40]):
          Caption(fontSize = 56, color = Linen, bold = true,
              sizeHintY = none[float](), height = 120) as attractTitle:
            canvas.before:
              Color(rgba = [0.0, 0, 0, 0.35])
              Rectangle(pos <- self.pos, size <- self.size)

  buildUi:
    Screen("home") as home:
      Panel(Sand, orientation = orientationVertical):
        Panel(Linen, sizeHintY = none[float](), height = 80,
            padding = [16.0, 8, 16, 8]) as homeHeader:
          Caption(fontSize = 30, color = Fig, bold = true, halign = halignLeft) as homeTitle
          Pill(Fig, sizeHintX = none[float](), width = 160) as langButton:
            on button.release:
              app.show.picker.open()
            Caption(fontSize = 22, color = Linen) as langLabel
        BoxLayout(spacing = 16, padding = [16.0, 16, 16, 16]):
          Tile as tile0:
            on button.release:
              app.show.openTopic(0)
            Image(Assets & Photos[0], fitMode = fitCover) as tileImage0
            Caption(fontSize = 22, color = Fig, bold = true,
              sizeHintY = none[float](), height = 56) as tileLabel0
          Tile as tile1:
            on button.release:
              app.show.openTopic(1)
            Image(Assets & Photos[1], fitMode = fitCover) as tileImage1
            Caption(fontSize = 22, color = Fig, bold = true,
              sizeHintY = none[float](), height = 56) as tileLabel1
          Tile as tile2:
            on button.release:
              app.show.openTopic(2)
            Image(Assets & Photos[2], fitMode = fitCover) as tileImage2
            Caption(fontSize = 22, color = Fig, bold = true,
              sizeHintY = none[float](), height = 56) as tileLabel2

  buildUi:
    Screen("topic") as topic:
      # Header, then the card (photo | text and Listen), then prev, dots,
      # next.
      on leave:
        app.show.stopVoice()
      Panel(Sand, orientation = orientationVertical):
        Panel(Linen, sizeHintY = none[float](), height = 80,
            padding = [16.0, 8, 16, 8]) as topicHeader:
          Caption(fontSize = 30, color = Fig, bold = true, halign = halignLeft) as topicTitle
          Pill(Fig, sizeHintX = none[float](), width = 160) as homeButton:
            on button.release:
              app.show.go("home")
            Caption(fontSize = 22, color = Linen) as homeLabel
        RelativeLayout:
          on touchUp(t: MotionEvent):
            result = app.show.swipe(self, t)
          BoxLayout(padding = [24.0, 16, 24, 16], spacing = 24):
            Image(fitMode = fitContain, sizeHintX = 0.45) as cardImage
            BoxLayout(orientation = orientationVertical, spacing = 12):
              Paragraph(fontSize = 24, color = Charcoal, halign = halignLeft) as cardText
              AnchorLayout(sizeHintY = none[float](), height = 64, anchorX = anchorLeft):
                Pill(Leaf, sizeHintX = none[float](), width = 180,
                    sizeHintY = none[float](), height = 56) as listen:
                  on button.release:
                    app.show.toggleListen()
                  Caption(fontSize = 22, color = Linen, bold = true) as listenLabel
        BoxLayout(sizeHintY = none[float](), height = 64, padding = [24.0, 4, 24, 4]):
          Pill(Fig, sizeHintX = none[float](), width = 120) as prev:
            on button.release:
              app.show.showCard(app.show.card - 1)
            Caption("<", fontSize = 30, color = Linen, bold = true)
          Widget as dots:
            on pos:
              app.show.drawDots()
            on size:
              app.show.drawDots()
          Pill(Fig, sizeHintX = none[float](), width = 120) as next:
            on button.release:
              app.show.showCard(app.show.card + 1)
            Caption(">", fontSize = 30, color = Linen, bold = true)

  buildUi:
    ModalView(sizeHint = (0.7, 0.4), backgroundColor = Linen, animDuration = 0.1) as picker:
      BoxLayout(padding = [16.0, 16, 16, 16], spacing = 16):
        Choice(app, "en", "English") as english
        Choice(app, "el", "Ελληνικά") as greek
        Choice(app, "de", "Deutsch") as german

  let s = Showcase(sm: newScreenManager(), lang: "en", slides: [slide0, slide1], front: 0,
    slide: 0, attractTitle: attractTitle, homeTitle: homeTitle, topicTitle: topicTitle,
    homeButton: homeButton, langButton: langButton, langLabel: langLabel,
    homeLabel: homeLabel, headers: @[homeHeader, topicHeader],
    tiles: @[tile0, tile1, tile2], tileLabels: @[tileLabel0, tileLabel1, tileLabel2],
    tileImages: @[tileImage0, tileImage1, tileImage2], card: 0, cardImage: cardImage,
    cardText: cardText, listen: listen, listenLabel: listenLabel, prev: prev, next: next,
    dots: dots, sound: loadSound(Assets & "tone.wav"), picker: picker,
    choices: @[english, greek, german], slideEv: nil, lastTouch: 0,
    slideInterval: app.slideInterval, fadeDuration: app.fadeDuration,
    idleTimeout: app.idleTimeout, log: @[])
  app.state = s
  let snd = s.sound
  if snd != nil:
    discard snd.bindPlay(proc (): bool {.closure.} =
      s.listenLabel.text = texts(s.lang).stop
      s.log.add "play"
      result = false)
    discard snd.bindStop(proc (): bool {.closure.} =
      s.listenLabel.text = texts(s.lang).listen
      s.log.add "stop"
      result = false)
  # The screens are added once the state exists: adding the first one makes
  # it current, and its `enter` handler starts the slides.
  s.sm.transition = fade
  s.sm.addWidget(attract)
  s.sm.addWidget(home)
  s.sm.addWidget(topic)
  discard s.sm.bindCurrent(proc (v: Opt[string]) {.closure.} =
    if v.isSome: s.log.add "screen " & v.get(""))
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
  let s = newShowcase(a)
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

when isMainModule:
  Config.graphics.width = 1024
  Config.graphics.height = 600
  newShowcaseApp().run()
