# Properties

A **`Property(T)`** is a component in config space: one Odin type, authored on archetypes, metas,
surfaces and objects, and flattened by `bake`.

```odin
Mass :: struct { value: f32 }

masses: dos.Property(Mass)
dos.property_init(&cfg, &masses, "mass") or_return   // "mass" is the name KDL uses
```

## Authoring

```odin
dos.set_property(&masses, physical, Mass{ 10 })   // archetype_id, meta_id, surface_id or object_id
dos.get_property(&masses, physical)               // ^Mass authored right here, not inherited
dos.unset_property(&masses, physical)
```

## Resolving

```odin
dos.resolve(&masses, guard)     // ^Mass for an archetype or surface: the baked value
dos.resolve(&masses, guard01)   // ^Mass for an object: what it authored, else its archetype's

value, src := dos.resolve_with_source(&masses, guard01)
dos.source_name(&cfg, src)      // "override", "core.Human", "core.Alert", ...
```

`resolve` on an object is at most two O(1) lookups. A `Property(T)` holds two ODE_ECS tables in the
Config's Database: what was authored, and each archetype's and surface's baked value with where it
came from.

## Overrides

A value authored on an object is an override: it beats everything its archetype says, and it is the
same call.

```odin
dos.set_property(&masses, guard01, Mass{ 95 })
dos.get_property(&masses, guard01)      // ^Mass, the object's own value only
dos.unset_property(&masses, guard01)    // back to the archetype's
```

Since nothing ODE_DOS stores is ever serialized, a property may hold strings, slices or maps, and an
object can override those too. What your game copies into its own runtime tables is your business —
ODE_ECS requires plain data only for what *it* saves.

## Types

Any Odin type works. `property_init` takes an optional `decode` proc for KDL shapes reflection cannot
guess; see [Loading](loading.md#custom-decoders).
