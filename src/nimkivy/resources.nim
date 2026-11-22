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
##
## The data directory (nimkivy's `fonts/`) is, in this order:
## `KIVY_DATA_DIR` if it is set; the directory given to `setDataDir`; `data`
## beside the executable (`getAppDir()`), if it exists; `data` under the
## current directory. It is fixed when it is first used: by the first label,
## font or resource lookup, so `setDataDir` goes before the first widget.

import std/[assertions, os, envvars, sequtils]

type
  ResourcePaths = ref object
    paths: seq[string]
    dataDir: string            # "" until `setDataDir` or the first use
    fixed: bool                # the data directory is in use

let resourcePaths = ResourcePaths(paths: @[".", getAppDir()], dataDir: "", fixed: false)

proc setDataDir*(path: sink string) =
  ## Sets the data directory, for a program that does not run from the
  ## directory that holds `data` and does not have it beside its executable.
  ## `KIVY_DATA_DIR` still comes first. Call it before the first widget,
  ## label, font or resource lookup.
  assert not resourcePaths.fixed, "setDataDir: the data directory is already in use"
  resourcePaths.dataDir = path

proc fixDataDir() =
  # kivy/__init__.py: `KIVY_DATA_DIR`, or `data` beside the package. Then
  # resources.py adds the data directory's parent to the resource paths.
  # GAP: the last choice is `data` under the current directory, not beside
  # the nimkivy sources, because Nimony has no currentSourcePath
  # (instantiationInfo gives only the file name).
  if resourcePaths.fixed: return
  var dir = getEnv("KIVY_DATA_DIR", "")
  if dir.len == 0: dir = resourcePaths.dataDir
  if dir.len == 0:
    dir = getAppDir() / "data"
    if not dirExists(dir): dir = "data"
  try:
    dir = absolutePath(dir)
  except:
    discard
  resourcePaths.dataDir = dir
  resourcePaths.fixed = true
  # After `.` and the program's directory, before any added path.
  resourcePaths.paths.insert([dir / ".."], 2)

proc dataDir*(): string =
  ## The directory of nimkivy's data files (`fonts/`); see the module doc.
  fixDataDir()
  result = resourcePaths.dataDir

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
  fixDataDir()
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

proc resourceAddPath*(path: sink string) =
  ## Adds a directory to search, unless it is already there.
  ## resources.py resource_add_path
  if path notin resourcePaths.paths:
    resourcePaths.paths.add path
