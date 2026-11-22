## Screen metrics and unit conversion: Kivy's `kivy/metrics.py` and
## `kivy/_metrics.pyx`.
##
## `Metrics` holds the screen's `dpi`, `density` and `fontscale` as alias
## properties, and the pixels per unit (`dp`, `sp`, ...) as aliases bound to
## them. `dp`, `sp`, `pt`, `inch`, `cm` and `mm` convert to pixels with
## `dpi2px`, in 32-bit floats as Kivy's Cython code does.
##
## The values come from the environment (`KIVY_DPI`, `KIVY_METRICS_DENSITY`,
## `KIVY_METRICS_FONTSCALE`), or else from the platform: the window sets
## `platformDpi` (and on Android `platformDensity`) and calls `resetMetrics`.
## Before that they are 96, 1 and 1, which is what Kivy's desktop window
## reports.

import std/[envvars, parseutils]
import props

type
  Unit* = enum
    ## The units Kivy converts (its unit suffixes).
    unitPx = "px", unitIn = "in", unitDp = "dp", unitSp = "sp", unitPt = "pt",
    unitCm = "cm", unitMm = "mm"

  PixelScale = ref object
    # _metrics.pyx g_dpi, g_density, g_fontscale: -1 until first dispatched.
    dpi, density, fontscale: float32

let pixelScale = PixelScale(dpi: -1, density: -1, fontscale: -1)

proc syncPixelScale(dpi, density, fontscale = -1.0) =
  # _metrics.pyx sync_pixel_scale: -1 leaves a factor as it is.
  if dpi != -1.0: pixelScale.dpi = float32(dpi)
  if density != -1.0: pixelScale.density = float32(density)
  if fontscale != -1.0: pixelScale.fontscale = float32(fontscale)

proc dispatchPixelScale*()

proc dpi2px*(value: float; unit: Unit): float =
  ## `value` in `unit` in pixels. _metrics.pyx dpi2px
  if pixelScale.dpi == -1: dispatchPixelScale()
  let rv = float32(value)
  let s = pixelScale
  var r = 0'f32
  case unit
  of unitIn: r = rv * s.dpi
  of unitPx: r = rv
  of unitDp: r = rv * s.density
  of unitSp: r = rv * s.density * s.fontscale
  of unitPt: r = rv * s.dpi / 72'f32
  of unitCm: r = rv * s.dpi / 2.54'f32
  of unitMm: r = rv * s.dpi / 25.4'f32
  result = float(r)

proc pt*(value: float): float =
  ## Points to pixels.
  dpi2px(value, unitPt)

proc inch*(value: float): float =
  ## Inches to pixels.
  dpi2px(value, unitIn)

proc cm*(value: float): float =
  ## Centimetres to pixels.
  dpi2px(value, unitCm)

proc mm*(value: float): float =
  ## Millimetres to pixels.
  dpi2px(value, unitMm)

proc dp*(value: float): float =
  ## Density-independent pixels to pixels.
  dpi2px(value, unitDp)

proc sp*(value: float): float =
  ## Scale-independent pixels (fonts) to pixels.
  dpi2px(value, unitSp)

proc envFloat(name: string; value: var float): bool =
  # An environment variable as a float; false when unset or not a number.
  let s = getEnv(name)
  result = s.len > 0 and parseFloat(s, value) == s.len

# Every property is Kivy's AliasProperty with `cache=True` and the default
# `watch_before_use` (`eager`). `dpi`, `density` and `fontscale` read the
# value set (or from the environment), else the platform's; the others are
# pixels per unit.
properties:
  type
    MetricsBase* = ref object of RootObj
      ## The class of `Metrics`.
      dpiSet, densitySet, fontscaleSet: bool     # Kivy's _dpi etc. are not None
      dpiValue, densityValue, fontscaleValue: float
      platformDpi*: float          ## the window's dpi
      platformDensity*: float      ## the display's scale on Android, else 1
      platformFontscale*: float    ## the user's font scale on Android, else 1
      dpi* {.alias: (getDpi, setDpi), cache, eager.}: float
      dpiRounded* {.alias: getDpiRounded, deps: dpi, cache, eager.}: int
      density* {.alias: (getDensity, setDensity), deps: dpi, cache, eager.}: float
      fontscale* {.alias: (getFontscale, setFontscale), cache, eager.}: float
      inch* {.alias: getInch, deps: (dpi, density, fontscale), cache, eager.}: float
      dp* {.alias: getDp, deps: (dpi, density, fontscale), cache, eager.}: float
      sp* {.alias: getSp, deps: (dpi, density, fontscale), cache, eager.}: float
      pt* {.alias: getPt, deps: (dpi, density, fontscale), cache, eager.}: float
      cm* {.alias: getCm, deps: (dpi, density, fontscale), cache, eager.}: float
      mm* {.alias: getMm, deps: (dpi, density, fontscale), cache, eager.}: float

  proc platformDpiValue(m: MetricsBase): float =
    # MetricsBase.get_dpi(force_recompute=True)
    result = m.platformDpi
    syncPixelScale(dpi = result)

  proc platformDensityValue(m: MetricsBase): float =
    # MetricsBase.get_density(force_recompute=True). Kivy: Android's
    # scaledDensity, dpi / 96 on macOS and Windows, else 1.
    when defined(macosx) or defined(windows):
      result = m.dpi / 96.0
    else:
      result = m.platformDensity
    syncPixelScale(density = result)

  proc platformFontscaleValue(m: MetricsBase): float =
    # MetricsBase.get_fontscale(force_recompute=True)
    result = m.platformFontscale
    syncPixelScale(fontscale = result)

  proc getDpi(m: MetricsBase): float =
    if m.dpiSet: m.dpiValue else: m.platformDpiValue()

  proc setDpi(m: MetricsBase; v: float): bool =
    m.dpiSet = true
    m.dpiValue = v
    syncPixelScale(dpi = v)
    result = true

  proc getDpiRounded(m: MetricsBase): int =
    let dpi = m.dpi
    result = if dpi < 140: 120 elif dpi < 200: 160 elif dpi < 280: 240 else: 320

  proc getDensity(m: MetricsBase): float =
    if m.densitySet: m.densityValue else: m.platformDensityValue()

  proc setDensity(m: MetricsBase; v: float): bool =
    m.densitySet = true
    m.densityValue = v
    syncPixelScale(density = v)
    result = true

  proc getFontscale(m: MetricsBase): float =
    if m.fontscaleSet: m.fontscaleValue else: m.platformFontscaleValue()

  proc setFontscale(m: MetricsBase; v: float): bool =
    m.fontscaleSet = true
    m.fontscaleValue = v
    syncPixelScale(fontscale = v)
    result = true

  proc getInch(m: MetricsBase): float = dpi2px(1, unitIn)
  proc getDp(m: MetricsBase): float = dpi2px(1, unitDp)
  proc getSp(m: MetricsBase): float = dpi2px(1, unitSp)
  proc getPt(m: MetricsBase): float = dpi2px(1, unitPt)
  proc getCm(m: MetricsBase): float = dpi2px(1, unitCm)
  proc getMm(m: MetricsBase): float = dpi2px(1, unitMm)

  proc newMetricsBase*(): MetricsBase =
    ## Metrics from the environment, else the platform defaults.
    ## metrics.py module setup and MetricsBase.__init__
    result = MetricsBase(dpiSet: false, densitySet: false, fontscaleSet: false,
      dpiValue: 0.0, densityValue: 0.0, fontscaleValue: 0.0,
      platformDpi: 96.0, platformDensity: 1.0, platformFontscale: 1.0)
    result.dpiSet = envFloat("KIVY_DPI", result.dpiValue)
    result.densitySet = envFloat("KIVY_METRICS_DENSITY", result.densityValue)
    result.fontscaleSet = envFloat("KIVY_METRICS_FONTSCALE", result.fontscaleValue)
    result.initProps()
    discard result.bindDpi(proc (v: float) {.closure.} = dispatchPixelScale())
    discard result.bindDensity(proc (v: float) {.closure.} = dispatchPixelScale())
    discard result.bindFontscale(proc (v: float) {.closure.} = dispatchPixelScale())

  proc resetMetrics*(m: MetricsBase) =
    ## Takes dpi, density and font scale from the platform again, dropping
    ## values that were set.
    m.dpi = m.platformDpiValue()
    m.density = m.platformDensityValue()
    m.fontscale = m.platformFontscaleValue()

  proc resetDpi*(m: MetricsBase) =
    ## Takes the dpi from the platform again.
    m.dpi = m.platformDpiValue()

let Metrics* = newMetricsBase()
  ## The screen metrics.

proc dispatchPixelScale*() =
  ## Reads `Metrics` into the factors `dpi2px` uses.
  ## _metrics.pyx dispatch_pixel_scale (the observers it dispatches are the
  ## unit-string properties, which are out of scope)
  pixelScale.dpi = float32(Metrics.dpi)
  pixelScale.density = float32(Metrics.density)
  pixelScale.fontscale = float32(Metrics.fontscale)
