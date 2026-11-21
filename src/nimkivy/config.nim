## The configuration: Kivy's `kivy/config.py`, in memory only.
##
## `Config` holds the keys nimkivy reads, with Kivy's defaults. Values are
## strings, as in Kivy's ConfigParser; `getint`, `getfloat` and `getboolean`
## convert them. There is no `config.ini` file (SCOPE.md).

import std/[tables, strutils, parseutils, syncio]

type
  ConfigParser* = ref object
    ## Sections of string options.
    values: Table[string, string]   # keyed by "section\0option"

proc keyOf(section, option: string): string =
  result = section & "\0" & option

proc hasOption*(c: ConfigParser; section, option: string): bool =
  ## Whether `option` is set in `section`.
  c.values.hasKey(keyOf(section, option))

proc set*(c: ConfigParser; section, option, value: string) =
  ## Sets an option.
  c.values[keyOf(section, option)] = value

proc set*(c: ConfigParser; section, option: string; value: int) =
  ## Sets an option to a number (stored as its text, as Kivy does).
  c.set(section, option, $value)

proc setdefault*(c: ConfigParser; section, option, value: string) =
  ## Sets an option unless it is already set.
  if not c.hasOption(section, option): c.set(section, option, value)

proc get*(c: ConfigParser; section, option: string): string =
  ## The text of an option. A missing option stops the program, as Kivy's
  ## NoOptionError does.
  let k = keyOf(section, option)
  if not c.values.hasKey(k):
    quit "NoOptionError: No option '" & option & "' in section: '" & section & "'"
  result = c.values.getOrDefault(k, "")

proc getdefault*(c: ConfigParser; section, option, default: string): string =
  ## The text of an option, or `default` when it is not set.
  result = c.values.getOrDefault(keyOf(section, option), default)

proc getint*(c: ConfigParser; section, option: string): int =
  ## An option as an integer. A value that is not one stops the program.
  let s = c.get(section, option).strip()
  try:
    result = parseInt(s)
  except:
    quit "ValueError: invalid literal for int() with base 10: '" & s & "'"

proc getfloat*(c: ConfigParser; section, option: string): float =
  ## An option as a float. A value that is not one stops the program.
  let s = c.get(section, option).strip()
  var x = 0.0
  if s.len == 0 or parseFloat(s, x) != s.len:
    quit "ValueError: could not convert string to float: '" & s & "'"
  result = x

proc getboolean*(c: ConfigParser; section, option: string): bool =
  ## An option as a boolean: 1, yes, true, on or 0, no, false, off.
  let s = c.get(section, option).toLowerAscii
  case s
  of "1", "yes", "true", "on": result = true
  of "0", "no", "false", "off": result = false
  else: quit "ValueError: Not a boolean: " & s

proc newConfigParser*(): ConfigParser =
  ## An empty configuration.
  ConfigParser(values: initTable[string, string]())

proc setKivyDefaults*(c: ConfigParser) =
  ## Kivy's defaults for the keys in SCOPE.md (config.py, the upgrade steps).
  c.setdefault("kivy", "exit_on_escape", "1")
  c.setdefault("graphics", "width", "800")
  c.setdefault("graphics", "height", "600")
  c.setdefault("graphics", "resizable", "1")
  c.setdefault("graphics", "maxfps", "60")
  c.setdefault("graphics", "multisamples", "2")
  c.setdefault("graphics", "min_state_time", ".035")
  c.setdefault("input", "mouse", "mouse")

proc newKivyConfig(): ConfigParser =
  result = newConfigParser()
  result.setKivyDefaults()

let Config* = newKivyConfig()
  ## The application's configuration. Set options before the window opens.
