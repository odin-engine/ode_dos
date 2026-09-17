# Objects

An object is an instance a designer authored: a name, an archetype and whatever values they put on
it. `load` creates them from KDL; you can also make one in code.

```odin
guard01, _ := dos.object(&cfg, guard, "Guard01")   // an empty name leaves it unnamed
dos.archetype_of(&cfg, guard01)                    // archetype_id
dos.name_of(&cfg, guard01)                         // "bafford.Guard01"
dos.set_name(&cfg, guard01, "Captain")             // renaming releases the old name
dos.find(&cfg, "bafford.Guard01")                  // (object_id, bool)
```

## Queries

```odin
dos.objects(&cfg)                  // []object_id, everything this Config declares
dos.objects_of(&cfg, creature)     // []object_id, of that archetype or anything derived from it
dos.changed_objects(&cfg)          // []object_id, what the last load touched
dos.changed_archetypes(&cfg)       // []archetype_id
```

Each returns a fresh slice from `context.temp_allocator` unless you pass an allocator.

## Building your runtime

ODE_DOS never writes to your world. You read what a designer authored and build whatever you like —
an ODE_ECS Database, a flat array, a scene graph.

```odin
for obj in dos.objects(&cfg) {
    e, _ := ecs.create_entity(&g.db)          // your entity, your Database

    src, _ := ecs.add_component(&g.sources, e)
    src^ = Of_Config{ obj }                   // so the entity remembers where it came from

    if v, has := dos.value(&cfg, obj, "max-hit-points"); has {
        hp, _ := dos.as_int(v)
        c, _ := ecs.add_component(&g.healths, e)
        c^ = Health{ int(hp), int(hp) }
    }

    transform: Transform
    if dos.read(&cfg, obj, "transform", &transform) {
        c, _ := ecs.add_component(&g.positions, e)
        c^ = transform
    }

    for a in dos.args(&cfg, obj, "status") {
        name, _ := dos.as_string(a)
        ecs.flag(&g.statuses, e, status_bit(name))
    }

    for l in dos.links_of(&cfg, obj) { /* your graph */ }
}
```

Keeping the two spaces connected is your business: a component holding the `object_id`, as above, or
a `map[dos.object_id]ecs.entity_id`, or nothing at all if the game never needs to look back.

## Saving

There is nothing of ODE_DOS's in your world to save. Configuration comes back from KDL, and your
world is saved by whatever owns it:

```odin
ecs.save_to_file(&g.db, "save01.bin") or_return
```
