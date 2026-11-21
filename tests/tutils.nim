# Ports the colour tests of kivy/tests/test_utils.py.

import std/assertions
import nimkivy/utils

proc almostEqual(a, b: float): bool =
  # unittest's assertAlmostEqual: equal to 7 decimal places.
  abs(a - b) < 0.5e-7

block test_get_hex_from_color_noalpha:
  # kivy/tests/test_utils.py::UtilsTest::test_get_hex_from_color_noalpha
  assert getHexFromColor([0.0, 1, 0]) == "#00ff00"

block test_get_hex_from_color_alpha:
  # kivy/tests/test_utils.py::UtilsTest::test_get_hex_from_color_alpha
  assert getHexFromColor([0.25, 0.77, 0.90, 0.5]) == "#3fc4e57f"

block test_get_color_from_hex_noalpha:
  # kivy/tests/test_utils.py::UtilsTest::test_get_color_from_hex_noalpha
  let actual = getColorFromHex("#d1a9c4")
  let expected = [0.81960784, 0.66274509, 0.76862745, 1.0]
  assert actual.len == 4
  for i in 0 ..< 4: assert almostEqual(actual[i], expected[i])

block test_get_color_from_hex_alpha:
  # kivy/tests/test_utils.py::UtilsTest::test_get_color_from_hex_alpha
  let actual = getColorFromHex("#00FF7F7F")
  let expected = [0.0, 1.0, 0.49803921, 0.49803921]
  assert actual.len == 4
  for i in 0 ..< 4: assert almostEqual(actual[i], expected[i])
