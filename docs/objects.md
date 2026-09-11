# Objects

Objects are runtime instances of archetypes.

```odin
guard01 := dos.spawn(&w, "Guard") or_return   // by archetype name
sword01 := dos.spawn(&w, sword) or_return     // or by a cached archetype_id

dos.archetype_of(&w, guard01)  // archetype_id
dos.alive(&w, guard01)
dos.destroy(&w, guard01)       // removes every component, flag and link of the object
```

## Spawn hooks

`spawn` creates the object, records its archetype, then runs every spawn hook. Hooks turn effective configuration into runtime state, which keeps inheritance out of the frame loop:

```odin
dos.on_spawn(&w, proc(w: ^dos.World, obj: dos.object_id) {
    g := cast(^Game) dos.user_data(w)
    if hp := dos.resolve(&g.max_hp, obj); hp != nil {
        dos.add(&g.health, obj, Health{ current = hp.value, max = hp.value })
    }
})
```

Odin has no closures, so hooks reach your tables through `World_Config.user_data`. Up to `MAX_SPAWN_HOOKS` (32) hooks can be registered.

For objects declared in KDL, `load` bakes first, applies the object's property overrides, runs the hooks, and then applies the state values from the file, so a hook sees the override and the file has the last word.

## Names

```odin
dos.set_name(&w, guard01, "Guard01")  // renaming releases the old name
dos.find(&w, "Guard01")               // (object_id, bool)
dos.name_of(&w, guard01)              // "" when names are not kept or it has none
```

Object names are separate from archetype names. `destroy` releases the name. Objects destroyed directly through ODE_ECS are not found by name any more, but their names are only released by `dos.destroy`.
