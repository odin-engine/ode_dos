![ODE_DOS banner](img/banner.png)
# 🗡️ ODE_DOS (BETA)

A Thief-style **Dark Object System** for Odin: prototype inheritance, mixins (metas), a typed link graph and data-driven authoring in [KDL](https://kdl.dev), built on [ODE_ECS](https://github.com/odin-engine/ode_ecs) and [ODE_KDL](https://github.com/odin-engine/ode_kdl).

ODE_DOS is based on Marc "MAHK" LeBlanc's GDC talk ["Game Entities in Thief: The Dark Project"](https://www.youtube.com/watch?v=5di7jmHKAQs).

ODE_DOS supports all "primitives" mentioned in the talk:

In configuration space:
- Properties (config space components)
- Metas/MetaProperties (a set of config space components, for mixing into archetypes and surfaces)
- Archetypes and "inheritance" (config space entities)
- Surfaces (texture flyweights, so material questions cost one lookup)
- Flags (config space booleans)

In runtime state space:
- Entities + components in ODE_ECS: objects, state and state flags
- Links (a typed object-to-object graph, authored in KDL)
- Per-object property overrides (opt-in per property)

Improvements over the original Thief-style **Dark Object System**:

1. Instead of building everything in an editor and saving the game's configuration in binary files, as Thief's designers did with DromEd, you do it in KDL (https://kdl.dev) text files, a human-friendly document language that is cleaner than JSON. Because the files are plain text, designers can keep them in Git and diff, review and merge each other's changes.

2. ODE_DOS has a clear distinction between configuration (what designers define) and runtime state (what is happening in the game during playtime). ODE_DOS answers *"what is this thing?"*; ODE_ECS answers *"what do all these things do this frame?"*. Inheritance is flattened once by `bake`, so gameplay reads configuration with O(1) lookups and iterates runtime state with plain ODE_ECS views or groups.

> NOTE: The project is in beta. Everything has been tested and is working, but it will be polished over the coming months.

## Features
- The game world has two spaces: config (archetypes, properties, metas, surfaces) and runtime (objects, state, links).
- Load your game configs from [KDL](https://kdl.dev) files, with
  `file:line:column` diagnostics and hot reload.
- Config space sizes itself: each load grows it to exactly what the KDL files declare.
- `bake` flattens inheritance into one value per archetype; `spawn` creates objects (entities), which you run with ODE_ECS as usual.
- Typed ids, typed links that snap automatically, effects, and save/load of runtime state.
- Check your KDL files with a tool built on `cli_run` (see `samples/dos_tool`).

## Install

Clone the three repositories side by side in a `vendor/` folder inside your project, and import `vendor/ode_dos/src`:

```
git clone https://github.com/odin-engine/ode_ecs.git
git clone https://github.com/odin-engine/ode_kdl.git
git clone https://github.com/odin-engine/ode_dos.git
```

ODE_DOS imports its siblings as `../../ode_ecs/src` and `../../ode_kdl/src`.

## Example

```kdl
archetype "Physical" { mass 10.0 }
archetype "Creature" parent="Physical" { max-hit-points 100 }
archetype "Guard"    parent="Creature"

object "Guard01" archetype="Guard" { max-hit-points 75 }   // this one is wounded
```

```odin
import "core:fmt"
import dos "vendor/ode_dos/src"

Mass   :: struct { value: f32 }
Max_HP :: struct { value: int }
Health :: struct { current, max: int }

Game :: struct {
    world:  dos.World,
    mass:   dos.Property(Mass),
    max_hp: dos.Property(Max_HP),
    health: dos.State(Health),
}

main :: proc() {
    g: Game
    w := &g.world
    dos.world_init(w, { user_data = &g })
    defer dos.world_terminate(w)

    dos.property_init(w, &g.mass, "mass")
    dos.property_init(w, &g.max_hp, "max-hit-points")
    dos.state_init(w, &g.health, "health")

    // properties become state at spawn
    dos.on_spawn(w, proc(w: ^dos.World, obj: dos.object_id) {
        g := cast(^Game) dos.user_data(w)
        if hp := dos.resolve(&g.max_hp, obj); hp != nil {
            dos.add(&g.health, obj, Health{ current = hp.value, max = hp.value })
        }
    })

    if dos.load(w, "data/") != nil {
        for e in dos.errors(w) do fmt.println(dos.format_error(e))
        return
    }

    guard, _ := dos.find(w, "Guard01")
    fmt.println(dos.resolve(&g.mass, guard).value)   // 10, from Physical
    fmt.println(dos.get(&g.health, guard).current)   // 75, overridden on Guard01
}
```

[samples/thief_demo](samples/thief_demo/main.odin) is a complete example; [samples/dos_tool](samples/dos_tool/main.odin) is a command-line tool built from the game itself.

## Documentation

See [docs/_index.md](docs/_index.md).

## Tests

```
cd tests && odin test . -define:ODIN_TEST_THREADS=1
```
