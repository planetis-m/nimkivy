# The type-plugin route for typed properties: `addhello` adds a proc to the
# module that declares `Thing`, as a property type plugin would add the
# accessors. Fails today: planetis-m/nimony-bugs-llms#336 (bug-reports/09).
# Run: nimony c -r --nimcache:nc app.nim
import std/syncio
import thing

echo hello(newThing())
