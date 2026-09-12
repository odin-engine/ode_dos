# Archetypes, metas and surfaces

Three kinds of config entity, all named, all able to carry property values and flags.

```odin
physical, _ := dos.archetype(&cfg, "Physical")
creature, _ := dos.archetype(&cfg, "Creature", parent = "Physical")
wooden, _   := dos.meta(&cfg, "Wooden")
planks, _   := dos.surface(&cfg, "WoodPlanks")
```

## Archetypes

Templates objects are made from. They form one inheritance forest across a Config chain: a parent
must live in the same Config or in one it is based on.

```odin
dos.find_archetype(&cfg, "Creature")   // (archetype_id, bool)
dos.parent_of(&cfg, creature)          // (archetype_id, bool)
dos.chain_of(&cfg, guard)              // []archetype_id, nearest first
dos.is_kind_of(&cfg, guard, physical)  // true for itself and any ancestor
dos.name_of(&cfg, guard)               // "core.Guard"
```

## Metas

Metas are mixins: they carry property values and are attached to archetypes or surfaces with a
priority. A higher priority wins; ties break by name, so the result never depends on attach order.

```odin
dos.attach(&cfg, guard, alert, 50)   // archetype_id or surface_id
dos.detach(&cfg, guard, alert)
dos.metas_of(&cfg, guard)            // []Attachment, highest priority first
```

Metas cannot carry metas: `attach` only accepts an `archetype_id` or a `surface_id` holder.

## Surfaces

Surfaces are Dark's texture flyweights: geometry stores a `surface_id`, and material questions cost
one lookup. Surfaces have no parents; their values come from their metas and what is authored on them.

```odin
planks, _ := dos.surface(&cfg, "WoodPlanks")
dos.attach(&cfg, planks, wooden)
dos.resolve(&footsteps, planks)   // ^Sound, after bake
dos.resolve_flag(&rope, planks)
```

## Precedence

For an object, a value comes from the first of:

1. what the object authored itself,
2. its archetype's metas, highest priority first (ties by name),
3. the archetype's own authored value,
4. the parent's metas, then the parent's authored value,
5. and so on up to the root.

## Bake

`bake` applies that precedence once for every archetype and surface in the chain, for every
`Property`, `Flag`, `State_Flags` and `Effects`, and stores the result. After it, `resolve` never
walks a chain. `load` bakes for you; call `dos.bake(&cfg)` yourself after authoring in code.
