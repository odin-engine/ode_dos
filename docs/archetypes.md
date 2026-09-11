# Archetypes, metas and surfaces

## Archetypes

```odin
physical, _ := dos.archetype(&w, "Physical")
creature, _ := dos.archetype(&w, "Creature", parent = "Physical")
guard, _    := dos.archetype(&w, "Guard", parent = "Creature")

dos.parent_of(&w, guard)            // (archetype_id, bool)
dos.chain_of(&w, guard)             // []archetype_id, nearest first: Creature, Physical
dos.is_kind_of(&w, guard, physical) // true; also true for guard itself
dos.find_archetype(&w, "Guard")     // (archetype_id, bool)
```

All archetypes, from every config set, form one inheritance forest (an ODE_ECS `Relations_Table` on CORE), so cycles are rejected and a parent can be in another set. The rule is that a parent must be in the child's set or in CORE, so unloading a set never orphans another set's archetypes.

`chain_of` returns ODE_ECS's own buffer; it is valid until the next chain query.

## Metas

Metas are mixins: they carry property values and are attached to archetypes or surfaces with a priority.

```odin
alert, _ := dos.meta(&w, "Alert")
dos.attach(&w, guard, alert, priority = 50)   // attaching again changes the priority
dos.detach(&w, guard, alert)
dos.metas_of(&w, guard)                       // []Attachment, highest priority first, ties by name
```

Metas cannot carry metas: `attach` only accepts an `archetype_id` or a `surface_id` holder.

## Surfaces

Surfaces are Dark's texture flyweights: geometry stores a `surface_id`, and material questions cost one lookup.

```odin
planks, _ := dos.surface(&w, "WoodPlanks")
dos.attach(&w, planks, wooden)
dos.surface_flag(&w, planks, &can_attach_rope)  // after bake
dos.resolve(&footsteps, planks)                 // ^Sound, after bake
```

Surfaces have no parents; their values come from their metas and what is authored on them.

## Precedence

For an object, a value comes from the first of:

1. the object's own override,
2. its archetype's metas, highest priority first (ties by name),
3. the archetype's own authored value,
4. the parent's metas, then the parent's authored value,
5. and so on up to the root.

Precedence is total: attachment order never matters.

## Bake

`bake` applies that precedence once for every archetype and surface and every `Property` and `Flag`, and stores the result. After it, `resolve` never walks a chain.

```odin
dos.bake(&w) or_return
```

`bake` is idempotent: run it again after any change to archetypes, metas or authored values. `load` bakes on its own before spawning the objects it declares.
