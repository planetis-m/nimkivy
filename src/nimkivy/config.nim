## The configuration: Kivy's `kivy/config.py`, in memory only.
##
## `Config` holds the settings nimkivy reads, as typed fields grouped like
## Kivy's sections, with Kivy's defaults: `Config.graphics.width = 1024`
## where Kivy writes `Config.set('graphics', 'width', '1024')`. Set them
## before the window opens. There is no `config.ini` file (SCOPE.md).

type
  MouseOption* = enum
    ## The options of the mouse provider (Kivy's `[input] mouse = mouse,<options>`).
    disableMultitouch     ## no multitouch simulation
    multitouchOnDemand    ## simulation only on request (no effect: there is none)
    disableOnActivity     ## other providers and hover are out of scope: no effect
    disableHover          ## no effect, as above

  KivySection* = object
    ## Kivy's `[kivy]` section.
    exitOnEscape*: bool          ## Escape (Android's Back) stops the app

  GraphicsSection* = object
    ## Kivy's `[graphics]` section.
    width*, height*: int         ## the window size at start
    resizable*: bool             ## the user may resize the window
    fullscreen*: bool            ## fullscreen at start (Kivy's `1` and `auto`)
    maxfps*: int                 ## frames per second the event loop paces to; 0 does not wait
    multisamples*: int           ## above 0, shapes get smooth edges for that many samples
                                 ## (graphics/vertex_instructions, msaaEdge)
    minStateTime*: float         ## ButtonBehavior's shortest pressed state, in seconds

  InputSection* = object
    ## Kivy's `[input]` section: only the mouse provider is in scope.
    mouse*: bool                 ## the mouse makes touches
    mouseOptions*: set[MouseOption]

  Configuration* = ref object
    ## The settings, by section.
    kivy*: KivySection
    graphics*: GraphicsSection
    input*: InputSection

proc newConfiguration*(): Configuration =
  ## Kivy's defaults for the settings in SCOPE.md (config.py, the upgrade
  ## steps).
  Configuration(
    kivy: KivySection(exitOnEscape: true),
    graphics: GraphicsSection(width: 800, height: 600, resizable: true, fullscreen: false,
      maxfps: 60, multisamples: 2, minStateTime: 0.035),
    input: InputSection(mouse: true, mouseOptions: {}))

let Config* = newConfiguration()
  ## The application's configuration. Set it before the window opens.
