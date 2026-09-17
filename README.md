![ODE_DOS banner](img/banner.png)
# 🗡️ ODE_DOS (BETA)

A Thief-style **Dark Object System** for Odin: prototype inheritance, mixins (metas), a typed link graph and data-driven authoring in [KDL](https://kdl.dev), built on [ODE_KDL](https://github.com/odin-engine/ode_kdl).

ODE_DOS is based on Marc "MAHK" LeBlanc's GDC talk ["Game Entities in Thief: The Dark Project"](https://www.youtube.com/watch?v=5di7jmHKAQs).

ODE_DOS describes what designers author; your runtime stays yours:

- **Config** is everything the files declare — archetypes, metas, surfaces, objects and the values they carry — with inheritance flattened once by `bake`.
- **Values** are read by name when your game builds its world, straight into your own Odin types. Nothing is declared in code: the files decide what exists.
- **Runtime** is yours — an [ODE_ECS](https://github.com/odin-engine/ode_ecs) Database, or whatever you build from what you read. ODE_DOS never writes to it.

ODE_DOS supports all "primitives" mentioned in the talk:

- Properties (named values, authored anywhere and inherited)
- Metas/MetaProperties (mixins, attached with a priority)
- Archetypes and "inheritance"
- Surfaces (texture flyweights, so material questions cost one lookup)
- Objects (the instances a designer authors) and their per-object overrides
- Links (a typed object-to-object graph)

Improvements over the original Thief-style **Dark Object System**:

1. Instead of building everything in an editor and saving the game's configuration in binary files, as Thief's designers did with DromEd, you describe it in KDL (https://kdl.dev) text files, a human-friendly document language that is cleaner than JSON. Because the files are plain text, designers can keep them in Git and diff, review and merge each other's changes.

2. ODE_DOS has a clear distinction between configuration (what designers define) and runtime state (what is happening in the game during playtime). ODE_DOS answers *"what is this thing?"*; your runtime answers *"what do all these things do this frame?"*. Inheritance is flattened once by `bake`, so a game reads configuration with O(1) lookups.

> NOTE: The project is in beta. Everything has been tested and is working, but it will be polished over the coming months.

## Features
- No declarations: load a folder of KDL and read whatever the designers wrote, by name.
- `file:line:column` diagnostics, and hot reload that tells you which objects changed.
- `unread` reports authored names nothing ever read, which is how typos are caught.
- Values read straight into your Odin types by reflection: structs, fixed arrays, enums, nested nodes.
- Several Configs can chain, so a DLC pack extends a base game.
- Inspect any object from the command line with a tool built on `cli_run` (see `samples/dos_tool`).

## Install

Clone the two repositories side by side in a `vendor/` folder inside your project, and import `vendor/ode_dos/src`:

```
git clone https://github.com/odin-engine/ode_kdl.git
git clone https://github.com/odin-engine/ode_dos.git
```

ODE_DOS imports ODE_KDL as `../../ode_kdl/src`.

## Example

```kdl
archetype "Physical" { mass 10.0 }
archetype "Creature" parent="Physical" { max-hit-points 100 }
archetype "Guard"    parent="Creature"

object "Guard01" archetype="Guard" {
    max-hit-points 75                     // this one is wounded
    transform { position 10.0 0.0 4.0 }
}
```

```odin
import "core:fmt"
import "core:os"

import dos "vendor/ode_dos/src"
import ecs "vendor/ode_ecs/src"

Transform :: struct { position: [3]f32 }
Health    :: struct { current, max: int }
Of_Config :: struct { obj: dos.object_id }   // what this entity was built from

Game :: struct {
    cfg:       dos.Config,       // what designers author

    db:        ecs.Database,     // the running game: yours, plain ODE_ECS
    positions: ecs.Table(Transform),
    healths:   ecs.Table(Health),
    sources:   ecs.Table(Of_Config),
}

main :: proc() {
    g: Game
    defer dos.config_terminate(&g.cfg)
    defer ecs.terminate(&g.db)

    if err := dos.config_init(&g.cfg); err != nil {
        fmt.eprintln("cannot start:", err)
        return
    }

    if dos.load(&g.cfg, "data") != nil {          // archetypes, metas, surfaces, objects; bakes
        for e in dos.errors(&g.cfg) do fmt.eprintln(dos.format_error(e, context.temp_allocator))
        return
    }

    if err := build(&g); err != nil {
        fmt.eprintln("cannot build the world:", err)
        return
    }

    // what the build produced, straight out of your own tables
    entities := ecs.entities_slice(&g.sources)
    for src, i in ecs.slice(&g.sources) {
        hp := ecs.get_component(&g.healths, entities[i])
        fmt.printfln("%s: %d hp", dos.name_of(&g.cfg, src.obj), hp.current)
    }

    guard01, _ := dos.find(&g.cfg, "Guard01")
    dos.explain(&g.cfg, guard01, "mass", os.to_stream(os.stdout))   // mass = 10  [from Physical]

    // once everything has been read, whatever is left is probably a typo
    for e in dos.unread(&g.cfg) do fmt.eprintln(dos.format_error(e, context.temp_allocator))
}

// your runtime, built from what the files say
build :: proc(g: ^Game) -> ecs.Error {
    ecs.init(&g.db, 4096) or_return
    ecs.table_init(&g.positions, &g.db, 4096) or_return
    ecs.table_init(&g.healths, &g.db, 4096) or_return
    ecs.table_init(&g.sources, &g.db, 4096) or_return

    for obj in dos.objects(&g.cfg) {
        e := ecs.create_entity(&g.db) or_return

        src := ecs.add_component(&g.sources, e) or_return
        src^ = Of_Config{ obj }

        transform: Transform
        if dos.read(&g.cfg, obj, "transform", &transform) {
            c := ecs.add_component(&g.positions, e) or_return
            c^ = transform
        }

        if v, has := dos.value(&g.cfg, obj, "max-hit-points"); has {
            hp, _ := dos.as_int(v)                        // 75 for Guard01, 100 for the rest
            c := ecs.add_component(&g.healths, e) or_return
            c^ = Health{ current = int(hp), max = int(hp) }
        }
    }
    return nil
}
```

Run it as [samples/sample01](samples/sample01/main.odin):

```
cd samples/sample01 && odin run .
```

[samples/thief_demo](samples/thief_demo/main.odin) is a fuller example; [samples/dos_tool](samples/dos_tool/main.odin) is a command-line tool built from the game itself.

## Documentation

See [docs/_index.md](docs/_index.md).

## Tests

```
cd tests && odin test . -define:ODIN_TEST_THREADS=1
```
