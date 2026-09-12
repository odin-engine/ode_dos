# Properties and state

Configuration and runtime state are different types, so they cannot be confused.

| | lives in | inherited | per object |
|---|---|---|---|
| `Property(T)` | the config set | yes, baked | overrides, per object |
| `Flag` | the config set | yes, baked | no |
| `State(T)` | the runtime database | no | yes |
| `State_Flags(E)` | the runtime database | no | yes |

Each is declared with a name; the name is used by KDL and diagnostics, never by gameplay.

## Property(T)

```odin
Mass :: struct { value: f32 }
masses: dos.Property(Mass)
dos.property_init(&w, &masses, "mass") or_return
```

Authoring in code (KDL normally does this):

```odin
dos.set_property(&masses, human, Mass{ 80 })  // on an archetype_id, meta_id or surface_id
dos.get_property(&masses, human)              // ^Mass authored on human itself, or nil
dos.unset_property(&masses, human)
```

Reading, after `bake`:

```odin
dos.resolve(&masses, obj)             // ^Mass: override, else the baked archetype value; nil when none
dos.resolve(&masses, human)           // the baked value of an archetype or surface
v, src := dos.resolve_with_source(&masses, obj)
dos.source_name(&w, src)              // "override", "core.Human", "core.Alert", ...
```

`resolve` on an object is at most three O(1) lookups: the override, the object's archetype and the baked value. Under the hood a `Property(T)` holds two ODE_ECS tables in its config set: what was authored, and each archetype's and surface's baked value together with where it came from. It also has one `Compact_Table(T)` of overrides in the runtime database, holding a single row until an object actually overrides it.

Any object can override any property:

```odin
dos.override(&masses, obj, Mass{ 95 })
dos.local(&masses, obj)          // ^Mass, the override only
dos.clear_override(&masses, obj)
```

The first override grows that table from one row to `overrides_cap`, so a property nobody overrides costs about a hundred bytes. `load_game` grows every one first, so a snapshot always fits.

`property_init` takes `set` (default `CORE`), `overrides_cap` (objects with an override, default 4,096) and an optional KDL `decode` proc.

## Flag

A configuration boolean, authored like a `Property` value and baked into one `ecs.Flags_Table` bit; up to 128 flags share one table.

```odin
rope: dos.Flag
dos.flag_init(&w, &rope, "can-attach-rope") or_return
dos.set_flag(&rope, wooden, true)      // archetype_id, meta_id or surface_id
dos.resolve_flag(&rope, obj)           // after bake; also for an archetype_id
dos.surface_flag(&w, planks, &rope)
```

Each flag takes the value of its first source in precedence order, so `set_flag(&flammable, human, false)` turns off a `true` inherited from `Physical`.

## State(T)

One `ecs.Table(T)` in the runtime database.

```odin
health: dos.State(Health)
dos.state_init(&w, &health, "health") or_return

dos.add(&health, obj, Health{ 100, 100 })  // overwrites an existing value
h := dos.get(&health, obj)                 // ^Health or nil
h.current -= 10
dos.has(&health, obj)
dos.remove(&health, obj)
dos.table(&health)                         // ^ecs.Table(Health)
```

## State_Flags(E)

Many runtime booleans in one `ecs.Flags_Table`, named by an enum (up to 128 values).

```odin
Status :: enum u8 { Dead, Unconscious, Alerted, Burning }
status: dos.State_Flags(Status)
dos.state_flags_init(&w, &status, "status") or_return

dos.set(&status, obj, Status.Dead)
dos.unset(&status, obj, Status.Dead)
dos.is_set(&status, obj, Status.Alerted)
dos.flags_of(&status, obj)              // bit_set[Status]
dos.table(&status)                      // ^ecs.Flags_Table
```

Write enum values in full (`Status.Dead`): Odin cannot infer the enum of `.Dead` through the polymorphic parameter.

## Plain data

The runtime database is what `save_game` writes, so everything kept there must be plain data: no strings, pointers, slices or maps. `state_init` and `link_init` return `DOS_Error.Type_Not_POD` for such types. A `Property(T)` may hold strings, but then objects cannot override it: `override` and `clear_override` return `Type_Not_POD`, and an override written in KDL is a load error.

## Gameplay

ODE_DOS does not wrap iteration. `dos.table` and `dos.link_table` hand back the ODE_ECS tables, and `dos.runtime(&w)` the database:

```odin
patrolling: ecs.View
ecs.view_init(&patrolling, dos.runtime(&w), {
    dos.table(&transforms),
    dos.link_table(&patrol),                                         // has an outgoing Patrol link
    ecs.flags_term(dos.table(&status), ecs.flags_of(Status.Alerted)),
}, excludes = {ecs.flags_term(dos.table(&status), ecs.flags_of(Status.Dead))}) or_return
```
