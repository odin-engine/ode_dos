# Inspect and CLI

## dump

Everything about a designed object, with the source of every value. ODE_DOS does not know your Odin
types, so values print as they were authored:

```odin
dos.dump(&cfg, guard01, os.to_stream(os.stdout))
```

```
Object: bafford.Guard01            archetype: core.Guard
Chain:  core.Guard → core.Human → core.Creature → core.Physical
Metas:  core.Alert (priority 50)

Values
  mass               10               [core.Physical]
  max-hit-points     75               [override]
  status             Unconscious      [override]
  transform          { position 10 0 4 } [override]
  vision-range       45               [core.Alert]

Links
  Contains → bafford.Sword01  ({ slot RightHand })
```

## explain

One value and where it comes from:

```odin
dos.explain(&cfg, guard01, "vision-range", out)   // vision-range = 45  [from core.Alert]
```

## A tool of your own

`cli_run` takes a Config, so a tool is a few lines around your own loading code. See
[samples/dos_tool](../samples/dos_tool/main.odin).

```odin
return dos.cli_run(&g.cfg, args[2:], os.to_stream(os.stdout))
```

```
commands:
  validate <path>            load path and report problems
  inspect  <object>          what an object is and where its values come from
  resolve  <object> <name>   one value and where it comes from
  chain    <archetype>       the inheritance chain
  links    <object>          outgoing links
```

Object and archetype names may be given in full or by their last part when that is unique, so
`Guard01` finds `bafford.Guard01`.
