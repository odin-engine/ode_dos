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
| `max_config_sets` | 4 | CORE plus your own |
| `max_objects` | 100,000 | live objects |
| `max_links` | 32,768 | links per flavor, unless `link_init` sets `cap` |
| `max_named_objects` | 4,096 | objects that can have a name (at most `max_objects`) |
| `keep_names` | debug builds | keep name strings for `name_of`, suggestions and inspect |
| `user_data` | nil | how spawn hooks and effects reach your tables |
| `allocator` | `context.allocator` | used for everything the World allocates |

These capacities are allocated at `world_init`. Config space has no capacity to set: it sizes itself (see below). Nothing grows during a frame.

## Config capacity

A new World holds one config entity. Every `load` grows config space to exactly what the loaded files declare, before it writes anything: the first load sizes it, and a hot reload or a new set adds only what it declares. Ids never change, so objects, cached `archetype_id`s and save games are unaffected.

```odin
dos.config_capacity(&w)   // (archetypes, attachments): what config space holds now
```

- Capacity only grows. Unloading a set keeps it, and later loads reuse the freed ids.
- `archetype`, `meta`, `surface` and `attach` called from code cannot know the total, so at capacity they double it (at least 16). A later load still grows exactly.
- Growing allocates, so load and build config at load boundaries, never mid-frame.
- ODE_ECS tables you add to a `config_db` yourself stay valid as config space grows, but keep the row capacity you gave them.

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

`DOS_Error` is `Invalid_Name`, `Name_Already_Exists`, `Name_Not_Found`, `Wrong_Kind`, `Parent_Not_Allowed`, `Config_Set_Not_Found`, `Cannot_Unload_Core`, `Load_Failed`, `Type_Not_POD` or `Not_Overridable`. ODE_ECS errors pass through unchanged.

The runtime database is ODE_ECS's own: `dos.runtime(&w)` returns it for views, groups and command buffers.
