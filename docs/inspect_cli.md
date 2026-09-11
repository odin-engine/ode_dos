# Inspect and CLI

Without an editor, the source of every value is what makes a text workflow work.

## dump and explain

```odin
out := os.to_stream(os.stdout)
dos.dump(&w, guard01, out)
dos.explain(&w, &vision, guard01, out)   // vision-range = 45  [from core.Alert]
```

```
Object: bafford.Guard01            archetype: core.Guard
Chain:  core.Guard → core.Human → core.Creature → core.Physical
Metas:  core.Alert (priority 50)

Properties
  mass               10         [core.Physical]
  max-hit-points     75         [override]
  vision-range       45         [core.Alert]

State
  transform          [10, 0, 4]
  health             Health{current = 75, max = 75}

Links
  Contains → bafford.Sword01  (Right_Hand)
```

A struct with one field prints as that field. `dos.source_name(&w, src)` turns a `Value_Source` into `"override"` or a name.

## Building a tool

A generic `dos` binary cannot know your Odin types, so your game builds its own tool: it declares everything as usual, loads its data, and passes the arguments to `cli_run`, which returns the exit code.

```odin
code := dos.cli_run(&w, os.args[2:], os.to_stream(os.stdout))
```

```
validate <path>            load path and report problems
inspect  <object>          what an object is and where its values come from
resolve  <object> <name>   one property value and where it comes from
chain    <archetype>       the inheritance chain
links    <object>          outgoing links
```

Objects and archetypes can be given by their short name (`Guard01` for `bafford.Guard01`) when it is unique and names are kept.

[samples/dos_tool](../samples/dos_tool/main.odin) does this with the demo's declarations:

```
dos_tool ../thief_game/data inspect Guard01
dos_tool ../thief_game/data resolve Guard01 vision-range
dos_tool ../thief_game/data validate ../thief_game/data
```
