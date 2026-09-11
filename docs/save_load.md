# Save and load

```odin
dos.save_game(&w, "save01.bin") or_return
dos.load_game(&w, "save01.bin") or_return
```

**Only runtime state is saved:** objects, `State` values, `State_Flags`, config overrides, links and applied effects, as one ODE_ECS snapshot of the runtime database. Configuration comes back from KDL, so a patched file applies to existing saves and saves stay small.

```
KDL configuration  +  state snapshot  =  restored world
```

`load_game` replaces the runtime state. The World must be set up the same way as the one that saved: the same declarations in the same order, and the same configuration loaded, so archetype ids match. ODE_ECS rejects a snapshot whose tables do not match.

Object names are restored, so `find` and `name_of` work after loading. A World keeps every object name string it has seen, so the names of objects destroyed before the load come back too.
