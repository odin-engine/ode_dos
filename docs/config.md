# Config

A **`Config`** holds everything designers author: archetypes, metas, surfaces, the properties and
flags they carry, and the objects declared in KDL. It owns one ODE_ECS `Database` and sizes it from
the files it loads.

```odin
cfg: dos.Config
dos.config_init(&cfg, { keep_names = true }) or_return
defer dos.config_terminate(&cfg)
```

A `Config` must not be moved after `config_init`; its tables keep pointers into it.

## Options

| field | default | meaning |
|---|---|---|
| `base` | nil | inherit from another Config |
| `max_derived` | 4 | Configs that may chain onto this one (roots only) |
| `keep_names` | debug builds | keep name strings for `name_of`, suggestions and inspect |
| `user_data` | nil | how decoders and tools reach your data |
| `allocator` | `context.allocator` | used for everything the Config allocates |

## Chaining Configs

A Config created with `base` shares its base's entity id space, so its archetypes can inherit from
the base's and its files can name them. Nothing flows the other way: the base cannot see the derived
Config. Terminate derived Configs first.

```odin
base, dlc: dos.Config
dos.config_init(&base, {}) or_return
defer dos.config_terminate(&base)                 // declared first, so it runs last
dos.config_init(&dlc, { base = &base }) or_return
defer dos.config_terminate(&dlc)

dos.load(&base, "data/core") or_return
dos.load(&dlc, "data/dlc") or_return              // may say parent="core.Human"
```

This is how a base game and a DLC pack, or a shared library of archetypes and one mission, live side
by side. Each Config has its own `Database`, and the root of a chain holds the archetype hierarchy,
the meta attachments and the object-to-archetype table for all of them.

## Ids

```odin
object_id    :: distinct ecs.entity_id // a designed object
archetype_id :: distinct ecs.entity_id // a template
meta_id      :: distinct ecs.entity_id // a mixin
surface_id   :: distinct ecs.entity_id // a material flyweight
```

All four name entities in a Config's Database. Your runtime entities are plain `ecs.entity_id`s in
your own Database and never mix with them. Procedures that legitimately accept more than one kind are
proc groups (`attach`, `set_property`, `resolve`, `name_of`).

## Capacity

Config space sizes itself; there is nothing to set. A new Config holds one entity, and every `load`
grows it to exactly what the files declare before writing anything.

```odin
dos.config_capacity(&cfg)   // (entities, attachments)
```

- Capacity only grows, and a whole chain grows together.
- `archetype`, `meta`, `surface`, `object` and `attach` called from code cannot know the total, so at
  capacity they double it (at least 16).
- Growing allocates, so build and load config at load boundaries, never mid-frame.

## Errors

`DOS_Error` is `Invalid_Name`, `Name_Already_Exists`, `Name_Not_Found`, `Wrong_Kind`,
`Parent_Not_Allowed`, `Load_Failed`, `Out_Of_Flags` or `Has_Derived`. ODE_ECS errors pass through
unchanged.
