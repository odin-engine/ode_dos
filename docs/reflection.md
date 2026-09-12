# Reflection

Reflection is what your game reads back from a `Config`: the objects a designer authored, their
names, their archetype, the values and flags they carry, and the links between them. It describes
designed things — it does not run them. There is no separate handle; these are procedures on the
Config itself.

## Designed objects

An object is a config entity of an archetype. `load` creates them from KDL; you can also make them in
code.

```odin
guard01, _ := dos.object(&cfg, guard, "Guard01")   // an empty name leaves it unnamed
dos.archetype_of(&cfg, guard01)                    // archetype_id
dos.name_of(&cfg, guard01)                         // "bafford.Guard01"
dos.set_name(&cfg, guard01, "Captain")             // renaming releases the old name
dos.find(&cfg, "bafford.Guard01")                  // (object_id, bool)
```

## Queries

```odin
dos.objects(&cfg)                    // []object_id, everything this Config declares
dos.objects_of(&cfg, creature)       // []object_id, of that archetype or anything derived from it
dos.changed_objects(&cfg)            // []object_id, what the last load touched
dos.changed_archetypes(&cfg)         // []archetype_id
```

Each returns a fresh slice from `context.temp_allocator` unless you pass an allocator.

## Building your runtime

ODE_DOS never writes to your world. You read what a designer authored and build whatever you like —
an ODE_ECS Database, a flat array, a scene graph.

```odin
for obj in dos.objects(&cfg) {
    e, _ := ecs.create_entity(&g.db)                 // your entity, your Database

    if hp := dos.resolve(&g.max_hp, obj); hp != nil {
        c, _ := ecs.add_component(&g.healths, e)
        c^ = Health{ hp.value, hp.value }
    }
    if p := dos.resolve(&g.transform, obj); p != nil {
        c, _ := ecs.add_component(&g.positions, e)
        c^ = Position{ p.position }
    }
    ecs.set_flags(&g.statuses, e, dos.bits_of(&g.status, obj))

    for target, data in dos.links_of(&g.contains, obj) { /* your graph */ }
}
```

Keep your own `map[dos.object_id]ecs.entity_id` if you need to go back and forth; the demo does.

## Saving

There is nothing of yours in ODE_DOS to save. Configuration comes back from KDL, and your world is
saved by ODE_ECS:

```odin
ecs.save_to_file(&g.db, "save01.bin") or_return
ecs.load_from_file(&g.db, "save01.bin") or_return
```
