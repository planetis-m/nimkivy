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
## Files are looked up through SDL (`SDL_GetPathInfo`), which also reads the
## files SDL opens: on the desktop the file system, on Android a relative
## path in the APK's assets. The program's directory is SDL's base path
## (on Android "./", the assets' root), and a path found stays as it was
## given, normalised, not made absolute: an absolute path on Android would
## leave the assets.
##
## The data directory (nimkivy's `fonts/`) is, in this order:
## the directory given to `setDataDir`; `data`
## in the program's directory, if it exists; `data` under the current
## directory. It is fixed when it is first used: by the first label, font or
## resource lookup, so `setDataDir` goes before the first widget.

import std/[assertions, sequtils, strutils]
import sdl3/sdl

type
  ResourcePaths = ref object
    paths: seq[string]
    dataDir: string            # "" until `setDataDir` or the first use
    fixed: bool                # the data directory is in use

proc `/`*(head, tail: string): string =
  ## `head` and `tail` joined with one "/"; `tail` if `head` is "".
  ## os.path.join
  if head.len == 0: result = tail
  elif head.endsWith("/"): result = head & tail
  else: result = head & "/" & tail

proc parentDir*(path: string): string =
  ## The directory that holds `path` ("" for a bare name). os.path.dirname
  var last = path.len - 1
  while last > 0 and path[last] == '/': dec last
  let i = path.rfind('/', last = last)
  result = if i < 0: "" elif i == 0: "/" else: path.substr(0, i - 1)

proc normalizedPath(path: string): string =
  # `.` and empty parts dropped, `x/..` collapsed. os.path.normpath
  var parts: seq[string] = @[]
  for part in path.split('/'):
    if part.len == 0 or part == ".": discard
    elif part == ".." and parts.len > 0 and parts[^1] != "..": parts.setLen(parts.len - 1)
    else: parts.add part
  result = parts.join("/")
  if path.startsWith("/"): result = "/" & result
  elif result.len == 0: result = "."

proc basePath(): string =
  # The program's directory, as SDL finds it, ending in a separator.
  let p = SDL_GetBasePath()
  result = if p != nil: fromCString(p) else: ""

proc pathType(path: string): SDL_PathType =
  # What `path` names, through SDL; 0 for nothing.
  var info = default(SDL_PathInfo)
  var p = path
  result = SDL_PathType(0)
  if SDL_GetPathInfo(p.toCString, addr info):
    result = info.`type`

proc isFile*(path: string): bool =
  ## Whether `path` names a file, through SDL (on Android, a relative path
  ## in the APK's assets). os.path.isfile
  pathType(path) == SDL_PATHTYPE_FILE

let resourcePaths = ResourcePaths(paths: @[".", basePath()], dataDir: "", fixed: false)

proc setDataDir*(path: sink string) =
  ## Sets the data directory, for a program that does not run from the
  ## directory that holds `data` and does not have it beside its executable.
  ## Call it before the first widget, label, font or resource lookup.
  assert not resourcePaths.fixed, "setDataDir: the data directory is already in use"
  resourcePaths.dataDir = path

proc fixDataDir() =
  # kivy/__init__.py: `data` beside the package. Then resources.py adds the
  # data directory's parent to the resource paths.
  # GAP: the last choice is `data` under the current directory, not beside
  # the nimkivy sources, because Nimony has no currentSourcePath
  # (instantiationInfo gives only the file name).
  if resourcePaths.fixed: return
  var dir = resourcePaths.dataDir
  if dir.len == 0:
    dir = normalizedPath(basePath() / "data")
    if pathType(dir) != SDL_PATHTYPE_DIRECTORY: dir = "data"
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
  let t = pathType(path)
  result = t == SDL_PATHTYPE_FILE or t == SDL_PATHTYPE_DIRECTORY

proc resourceFind*(filename: string): string =
  ## The path of `filename` (normalised, not made absolute: see the module
  ## doc), searched as a path and then in the resource paths, the last added
  ## first; "" if it is not found. resources.py resource_find
  fixDataDir()
  result = ""
  if filename.len == 0:
    return ""
  let direct = normalizedPath(filename)
  if exists(direct):
    return direct
  for i in countdown(resourcePaths.paths.high, 0):
    let candidate = normalizedPath(resourcePaths.paths[i] / filename)
    if exists(candidate):
      return candidate

proc resourceAddPath*(path: sink string) =
  ## Adds a directory to search, unless it is already there.
  ## resources.py resource_add_path
  if path notin resourcePaths.paths:
    resourcePaths.paths.add path
