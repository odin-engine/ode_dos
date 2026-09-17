# Archetypes, metas and surfaces

Three kinds of config entity, all named, all able to carry values.

```kdl
archetype "Physical" { mass 10.0 }
archetype "Creature" parent="Physical" { max-hit-points 100 }

meta "Alert" priority=50 { vision-range 45.0 }
surface "WoodPlanks" { meta "Wooden" }
```

## Archetypes

Templates objects are made from. They form one inheritance forest across a Config chain: a parent
must live in the same Config or in one it is based on.

```odin
dos.find_archetype(&cfg, "core.Creature")   // (archetype_id, bool)
dos.parent_of(&cfg, creature)               // (archetype_id, bool)
dos.chain_of(&cfg, guard)                   // []archetype_id, nearest first
dos.is_kind_of(&cfg, guard, physical)       // true for itself and any ancestor
dos.name_of(&cfg, guard)                    // "core.Guard"
```

## Metas

Metas are mixins: they carry values and are attached to archetypes or surfaces with a priority. A
higher priority wins; ties break by name, so the result never depends on attach order.

```odin
dos.attach(&cfg, guard, alert, 50)   // archetype_id or surface_id
dos.detach(&cfg, guard, alert)
dos.metas_of(&cfg, guard)            // []Attachment, highest priority first
```

Metas cannot carry metas, and an object cannot carry one either — put it on the archetype.

## Surfaces

Surfaces are Dark's texture flyweights: geometry stores a `surface_id`, and material questions cost
one lookup. Surfaces have no parents; their values come from their metas and what is authored on
them.

```odin
planks, _ := dos.find_surface(&cfg, "core.WoodPlanks")
dos.has(&cfg, planks, "can-attach-rope")
dos.value(&cfg, planks, "footstep-sound")
```

## Creating them in code

`archetype`, `meta`, `surface` and `object` exist for tools and tests. Values, though, come from
files — there is no code path that authors one. After changing parents or metas in code, call
`dos.bake(&cfg)`; a load bakes on its own.
