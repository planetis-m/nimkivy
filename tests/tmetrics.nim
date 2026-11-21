# Ports kivy/tests/test_metrics.py. Kivy's `kivy_metrics` fixture pushes a
# fresh Metrics; here the test sets every factor of the one `Metrics` itself.

import std/assertions
import nimkivy/metrics

proc approx(a, b: float): bool =
  # pytest.approx: relative 1e-6, absolute 1e-12.
  abs(a - b) <= max(1e-6 * abs(b), 1e-12)

proc factor(unit: string): float =
  # getattr(kivy_metrics, unit)
  case unit
  of "inch": Metrics.inch
  of "dp": Metrics.dp
  of "sp": Metrics.sp
  of "pt": Metrics.pt
  of "cm": Metrics.cm
  else: Metrics.mm

proc convert(unit: string; value: float): float =
  # getattr(kivy.metrics, unit)(value)
  case unit
  of "inch": inch(value)
  of "dp": dp(value)
  of "sp": sp(value)
  of "pt": pt(value)
  of "cm": cm(value)
  else: mm(value)

for unit in ["inch", "dp", "sp", "pt", "cm", "mm"]:
  block test_metrics_scale_factors:
    # kivy/tests/test_metrics.py::test_metrics_scale_factors
    let ext = unit.substr(0, 1)
    Metrics.density = 2
    Metrics.dpi = 101
    Metrics.fontscale = 3
    let f = factor(unit)
    assert approx(dpi2px(7, ext), 7 * f)
    assert approx(convert(unit, 7), 7 * f)
    Metrics.density = 5
    Metrics.dpi = 103
    Metrics.fontscale = 11
    let newFactor = factor(unit)
    assert not approx(newFactor, f)
    assert approx(dpi2px(7, ext), 7 * newFactor)
    assert approx(convert(unit, 7), 7 * newFactor)
    assert not approx(dpi2px(7, ext), 7 * f)
    assert not approx(convert(unit, 7), 7 * f)
    assert approx(dpi2px(100, ext), 100 * newFactor)
    assert approx(dpi2px(1000, ext), 1000 * newFactor)
