# World and config sets

A `World` holds everything: one **runtime database** for objects and one **config Overbase** with one or more **config sets** for archetypes, metas and surfaces.

```odin
w: dos.World
dos.world_init(&w) or_return           // every field defaulted
defer dos.world_terminate(&w)
```

A `World` must not be moved after `world_init`; ODE_ECS tables keep pointers into it. Put it in a struct you keep at a fixed address, as the samples do.

## World_Config

| field | default | meaning |
|---|---|---|
| `max_archetypes` | 2,048 | archetypes + metas + surfaces across all sets |
| `max_config_sets` | 4 | CORE plus your own |
| `max_objects` | 100,000 | live objects |
| `max_links` | 32,768 | links per flavor, unless `link_init` sets `cap` |
| `max_attachments` | 4 × `max_archetypes` | meta attachments across all archetypes and surfaces |
| `max_named_objects` | 4,096 | objects that can have a name (at most `max_objects`) |
| `keep_names` | debug builds | keep name strings for `name_of`, suggestions and inspect |
| `user_data` | nil | how spawn hooks and effects reach your tables |
| `allocator` | `context.allocator` | used for everything the World allocates |

Every capacity is allocated at `world_init`; nothing grows during a frame.

## Two id spaces, four id types

Archetypes are few and hierarchical; objects are many and short-lived. They live in separate ODE_ECS id spaces, so the same number means different things in each, and the types keep them apart:

```odin
object_id    :: distinct ecs.entity_id // runtime: instances
archetype_id :: distinct ecs.entity_id // config: templates
meta_id      :: distinct ecs.entity_id // config: mixins
surface_id   :: distinct ecs.entity_id // config: material flyweights
```

Procedures that legitimately accept more than one kind are proc groups (`attach`, `set_property`, `resolve`, `name_of`).

## Config sets

Every config set is a separate ODE_ECS `Database` on the one config Overbase, so archetype ids stay comparable across sets. `CORE` always exists.

```odin
items := dos.create_config_set(&w, "items") or_return
dos.property_init(&w, &durability, "durability", set = items) or_return
dos.archetype(&w, "items.Sword", parent = "Physical", set = items) or_return

dos.find_config_set(&w, "items")       // (config_set_id, bool)
dos.config_db(&w, items)               // ^ecs.Database
dos.unload_config_set(&w, items)       // destroys its archetypes, metas and surfaces
```

Split sets by lifetime (a DLC pack, a streamed region), not by category. Unloading a set also drops the property values, flags and names declared in it; `create_config_set` can then reuse its slot. `CORE` cannot be unloaded.

## Names

Names are dotted (`core.Guard`, `bafford.Guard01`); the namespace is purely lexical. Archetypes, metas and surfaces share one namespace; objects have their own. Names are hashed to 64 bits; the strings are kept only when `keep_names` is on.

## Errors

```odin
Error :: union #shared_nil { DOS_Error, ecs.API_Error, oc.Core_Error, oc.Error, runtime.Allocator_Error }
```

`DOS_Error` is `Invalid_Name`, `Name_Already_Exists`, `Name_Not_Found`, `Wrong_Kind`, `Parent_Not_Allowed`, `Config_Set_Not_Found`, `Cannot_Unload_Core`, `Load_Failed` or `Type_Not_POD`. ODE_ECS errors pass through unchanged.

The runtime database is ODE_ECS's own: `dos.runtime(&w)` returns it for views, groups and command buffers.
