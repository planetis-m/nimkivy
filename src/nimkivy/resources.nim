## Resource lookup: Kivy's `kivy/resources.py` (`resource_find`,
## `resource_add_path`) and `kivy_data_dir` from `kivy/__init__.py`.
##
## A relative file name is searched in the current directory, then in the
## resource paths, the last added first. The paths are Kivy's: `.`, the
## program's directory, and the parent of the data directory, so
## `data/fonts/Roboto-Regular.ttf` names nimkivy's copy of Kivy's font.
## `core/text` adds `<data>/fonts`, where Kivy adds every system font
## directory too (SCOPE.md: a font is a path or a name in `data/fonts`).
## Kivy caches the results for 60 seconds; this lookup is not cached.

import std/[os, envvars]

type
  ResourcePaths = ref object
    paths: seq[string]

proc defaultDataDir(): string =
  # kivy/__init__.py: `KIVY_DATA_DIR`, or `data` beside the package.
  # GAP: without KIVY_DATA_DIR the data directory is `data` under the current
  # directory, not beside the nimkivy sources, because Nimony has no
  # currentSourcePath (instantiationInfo gives only the file name).
  result = getEnv("KIVY_DATA_DIR", "data")
  try:
    result = absolutePath(result)
  except:
    discard

let kivyDataDir* = defaultDataDir()
  ## The directory of nimkivy's data files (`fonts/`).

proc initialPaths(): seq[string] =
  # resources.py resource_paths
  result = @[".", getAppDir(), kivyDataDir / ".."]

let resourcePaths = ResourcePaths(paths: initialPaths())

proc exists(path: string): bool =
  # os.path.exists: a file or a directory.
  fileExists(path) or dirExists(path)

proc abspath(path: string): string =
  # os.path.abspath: absolute and normalised.
  result = path
  try:
    result = absolutePath(path)
  except:
    discard
  result = normalizedPath(result)

proc resourceFind*(filename: string): string =
  ## The absolute path of `filename`, searched as a path and then in the
  ## resource paths, the last added first; "" if it is not found.
  ## resources.py resource_find
  result = ""
  if filename.len == 0:
    return ""
  let direct = abspath(filename)
  if exists(direct):
    return direct
  for i in countdown(resourcePaths.paths.high, 0):
    let candidate = abspath(resourcePaths.paths[i] / filename)
    if exists(candidate):
      return candidate

proc resourceAddPath*(path: string) =
  ## Adds a directory to search, unless it is already there.
  ## resources.py resource_add_path
  if path notin resourcePaths.paths:
    resourcePaths.paths.add path
