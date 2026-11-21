## Screen metrics and unit conversion: Kivy's `kivy/metrics.py` and
## `kivy/_metrics.pyx`.
##
## `Metrics` holds the screen's `dpi`, `density` and `fontscale` as alias
## properties. `dp`, `sp`, `pt`, `inch`, `cm` and `mm` convert to pixels
## with `dpi2px`, in 32-bit floats as Kivy's Cython code does.
##
## The values come from the environment (`KIVY_DPI`, `KIVY_METRICS_DENSITY`,
## `KIVY_METRICS_FONTSCALE`), or else from the platform: the window sets
## `platformDpi` (and on Android `platformDensity`) and calls `resetMetrics`.
## Before that they are 96, 1 and 1, which is what Kivy's desktop window
## reports.

import std/[envvars, parseutils]
import properties

type
  PixelScale = ref object
    # _metrics.pyx g_dpi, g_density, g_fontscale: -1 until first dispatched.
    dpi, density, fontscale: float32

  MetricsBase* = ref object of EventDispatcher
    ## The class of `Metrics`.
    dpiSet, densitySet, fontscaleSet: bool     # Kivy's _dpi etc. are not None
    dpiValue, densityValue, fontscaleValue: float
    platformDpi*: float          ## the window's dpi
    platformDensity*: float      ## the display's scale on Android, else 1
    platformFontscale*: float    ## the user's font scale on Android, else 1

const NumericFormats* = ["in", "px", "dp", "sp", "pt", "cm", "mm"]
  ## The unit suffixes Kivy knows.

let pixelScale = PixelScale(dpi: -1, density: -1, fontscale: -1)

proc syncPixelScale(dpi, density, fontscale = -1.0) =
  # _metrics.pyx sync_pixel_scale: -1 leaves a factor as it is.
  if dpi != -1.0: pixelScale.dpi = float32(dpi)
  if density != -1.0: pixelScale.density = float32(density)
  if fontscale != -1.0: pixelScale.fontscale = float32(fontscale)

proc dispatchPixelScale*()

proc dpi2px*(value: float; ext: string): float =
  ## `value` in unit `ext` (one of `NumericFormats`) in pixels.
  ## _metrics.pyx dpi2px
  if pixelScale.dpi == -1: dispatchPixelScale()
  let rv = float32(value)
  let s = pixelScale
  var r = 0'f32
  case ext
  of "in": r = rv * s.dpi
  of "px": r = rv
  of "dp": r = rv * s.density
  of "sp": r = rv * s.density * s.fontscale
  of "pt": r = rv * s.dpi / 72'f32
  of "cm": r = rv * s.dpi / 2.54'f32
  of "mm": r = rv * s.dpi / 25.4'f32
  else: r = 0'f32
  result = float(r)

proc pt*(value: float): float =
  ## Points to pixels.
  dpi2px(value, "pt")

proc inch*(value: float): float =
  ## Inches to pixels.
  dpi2px(value, "in")

proc cm*(value: float): float =
  ## Centimetres to pixels.
  dpi2px(value, "cm")

proc mm*(value: float): float =
  ## Millimetres to pixels.
  dpi2px(value, "mm")

proc dp*(value: float): float =
  ## Density-independent pixels to pixels.
  dpi2px(value, "dp")

proc sp*(value: float): float =
  ## Scale-independent pixels (fonts) to pixels.
  dpi2px(value, "sp")

# ------------------------------------------------------------------ MetricsBase

proc getDpi(m: MetricsBase; forceRecompute = false): float =
  if not forceRecompute and m.dpiSet:
    result = m.dpiValue
  else:
    result = m.platformDpi
    syncPixelScale(dpi = result)

proc getDensity(m: MetricsBase; forceRecompute = false): float =
  if not forceRecompute and m.densitySet:
    result = m.densityValue
  else:
    # Kivy: Android's scaledDensity, dpi / 96 on macOS and Windows, else 1.
    when defined(macosx) or defined(windows):
      result = m.getDpi() / 96.0
    else:
      result = m.platformDensity
    syncPixelScale(density = result)

proc getFontscale(m: MetricsBase; forceRecompute = false): float =
  if not forceRecompute and m.fontscaleSet:
    result = m.fontscaleValue
  else:
    result = m.platformFontscale
    syncPixelScale(fontscale = result)

let MetricsClass* = newDispatcherClass("MetricsBase", EventDispatcherClass)
  ## The property declarations of `MetricsBase`.

let metricsDpi = MetricsClass.addAlias("dpi",
  proc (d: EventDispatcher): Value = toValue(MetricsBase(d).getDpi()),
  proc (d: EventDispatcher; v: Value): bool =
    let m = MetricsBase(d)
    m.dpiSet = true
    m.dpiValue = v.num
    syncPixelScale(dpi = v.num)
    result = true,
  cache = true)

let metricsDpiRounded = MetricsClass.addAlias("dpi_rounded",
  proc (d: EventDispatcher): Value =
    let dpi = metricsDpi.getNumber(d)
    result = toValue(if dpi < 140: 120 elif dpi < 200: 160 elif dpi < 280: 240 else: 320),
  nil, @["dpi"], cache = true)

let metricsDensity = MetricsClass.addAlias("density",
  proc (d: EventDispatcher): Value = toValue(MetricsBase(d).getDensity()),
  proc (d: EventDispatcher; v: Value): bool =
    let m = MetricsBase(d)
    m.densitySet = true
    m.densityValue = v.num
    syncPixelScale(density = v.num)
    result = true,
  @["dpi"], cache = true)

let metricsFontscale = MetricsClass.addAlias("fontscale",
  proc (d: EventDispatcher): Value = toValue(MetricsBase(d).getFontscale()),
  proc (d: EventDispatcher; v: Value): bool =
    let m = MetricsBase(d)
    m.fontscaleSet = true
    m.fontscaleValue = v.num
    syncPixelScale(fontscale = v.num)
    result = true,
  cache = true)

let scaleDeps = @["dpi", "density", "fontscale"]
let metricsInch = MetricsClass.addAlias("inch",
  proc (d: EventDispatcher): Value = toValue(dpi2px(1, "in")), nil, scaleDeps, cache = true)
let metricsDp = MetricsClass.addAlias("dp",
  proc (d: EventDispatcher): Value = toValue(dpi2px(1, "dp")), nil, scaleDeps, cache = true)
let metricsSp = MetricsClass.addAlias("sp",
  proc (d: EventDispatcher): Value = toValue(dpi2px(1, "sp")), nil, scaleDeps, cache = true)
let metricsPt = MetricsClass.addAlias("pt",
  proc (d: EventDispatcher): Value = toValue(dpi2px(1, "pt")), nil, scaleDeps, cache = true)
let metricsCm = MetricsClass.addAlias("cm",
  proc (d: EventDispatcher): Value = toValue(dpi2px(1, "cm")), nil, scaleDeps, cache = true)
let metricsMm = MetricsClass.addAlias("mm",
  proc (d: EventDispatcher): Value = toValue(dpi2px(1, "mm")), nil, scaleDeps, cache = true)

proc envFloat(name: string; value: var float): bool =
  # An environment variable as a float; false when unset or not a number.
  let s = getEnv(name)
  result = s.len > 0 and parseFloat(s, value) == s.len

proc pixelScaleCallback(): PropertyCallback =
  result = proc (d: EventDispatcher; v: Value) {.closure.} = dispatchPixelScale()

proc newMetricsBase*(): MetricsBase =
  ## Metrics from the environment, else the platform defaults.
  ## metrics.py module setup and MetricsBase.__init__
  result = MetricsBase(cls: MetricsClass, dpiSet: false, densitySet: false,
    fontscaleSet: false, dpiValue: 0.0, densityValue: 0.0, fontscaleValue: 0.0,
    platformDpi: 96.0, platformDensity: 1.0, platformFontscale: 1.0)
  result.dpiSet = envFloat("KIVY_DPI", result.dpiValue)
  result.densitySet = envFloat("KIVY_METRICS_DENSITY", result.densityValue)
  result.fontscaleSet = envFloat("KIVY_METRICS_FONTSCALE", result.fontscaleValue)
  result.initEventDispatcher()
  discard result.fbind("dpi", pixelScaleCallback())
  discard result.fbind("density", pixelScaleCallback())
  discard result.fbind("fontscale", pixelScaleCallback())

let Metrics* = newMetricsBase()
  ## The screen metrics.

proc dispatchPixelScale*() =
  ## Reads `Metrics` into the factors `dpi2px` uses.
  ## _metrics.pyx dispatch_pixel_scale (the observers it dispatches are the
  ## unit-string properties, which are out of scope)
  pixelScale.dpi = float32(metricsDpi.getNumber(Metrics))
  pixelScale.density = float32(metricsDensity.getNumber(Metrics))
  pixelScale.fontscale = float32(metricsFontscale.getNumber(Metrics))

proc dpi*(m: MetricsBase): float =
  ## The screen's dots per inch.
  metricsDpi.getNumber(m)

proc `dpi=`*(m: MetricsBase; v: float) =
  ## Overrides the dpi.
  metricsDpi.setNumber(m, v)

proc dpiRounded*(m: MetricsBase): float =
  ## The dpi rounded to 120, 160, 240 or 320.
  metricsDpiRounded.getNumber(m)

proc density*(m: MetricsBase): float =
  ## Pixels per density-independent pixel.
  metricsDensity.getNumber(m)

proc `density=`*(m: MetricsBase; v: float) =
  ## Overrides the density.
  metricsDensity.setNumber(m, v)

proc fontscale*(m: MetricsBase): float =
  ## The user's font scale.
  metricsFontscale.getNumber(m)

proc `fontscale=`*(m: MetricsBase; v: float) =
  ## Overrides the font scale.
  metricsFontscale.setNumber(m, v)

proc inch*(m: MetricsBase): float =
  ## Pixels per inch.
  metricsInch.getNumber(m)

proc dp*(m: MetricsBase): float =
  ## Pixels per dp.
  metricsDp.getNumber(m)

proc sp*(m: MetricsBase): float =
  ## Pixels per sp.
  metricsSp.getNumber(m)

proc pt*(m: MetricsBase): float =
  ## Pixels per point.
  metricsPt.getNumber(m)

proc cm*(m: MetricsBase): float =
  ## Pixels per centimetre.
  metricsCm.getNumber(m)

proc mm*(m: MetricsBase): float =
  ## Pixels per millimetre.
  metricsMm.getNumber(m)

proc resetMetrics*(m: MetricsBase) =
  ## Takes dpi, density and font scale from the platform again, dropping
  ## values that were set.
  m.dpi = m.getDpi(forceRecompute = true)
  m.density = m.getDensity(forceRecompute = true)
  m.fontscale = m.getFontscale(forceRecompute = true)

proc resetDpi*(m: MetricsBase) =
  ## Takes the dpi from the platform again.
  m.dpi = m.getDpi(forceRecompute = true)
