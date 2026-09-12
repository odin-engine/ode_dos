# Inspect and CLI

## dump

Everything about a designed object, with the source of every value:

```odin
dos.dump(&cfg, guard01, os.to_stream(os.stdout))
```

```
Object: bafford.Guard01            archetype: core.Guard
Chain:  core.Guard → core.Human → core.Creature → core.Physical
Metas:  core.Alert (priority 50)

Properties
  mass               10         [core.Physical]
  max-hit-points     75         [override]
  vision-range       45         [core.Alert]
  transform          [10, 0, 4] [override]

State flags
  status             Unconscious

Effects
  KnockedOut

Links
  Contains → bafford.Sword01  (Right_Hand)
```

## explain

One property and where it comes from:

```odin
dos.explain(&g.cfg, &g.vision, guard01, out)   // vision-range = 45  [from core.Alert]
```

## A tool of your own

A generic tool cannot know your Odin types, so your game builds its own: declare everything as usual,
load the data and hand the arguments to `cli_run`. See [samples/dos_tool](../samples/dos_tool/main.odin).

```odin
return dos.cli_run(&g.cfg, args[2:], os.to_stream(os.stdout))
```

```
commands:
  validate <path>            load path and report problems
  inspect  <object>          what an object is and where its values come from
  resolve  <object> <name>   one property value and where it comes from
  chain    <archetype>       the inheritance chain
  links    <object>          outgoing links
```

Object and archetype names may be given in full or by their last part when that is unique, so
`Guard01` finds `bafford.Guard01`.
