# Effects

Effects (`KnockedOut`, `Burning`) apply to objects, change often, and change what the object does. The data stays in KDL; the behavior is Odin:

```odin
dos.effect_register(&w, "KnockedOut", dos.Effect{
    on_attach = proc(w: ^dos.World, obj: dos.object_id) {
        g := cast(^Game) dos.user_data(w)
        dos.set(&g.status, obj, Status.Unconscious)
    },
    on_detach = proc(w: ^dos.World, obj: dos.object_id) {
        g := cast(^Game) dos.user_data(w)
        dos.unset(&g.status, obj, Status.Unconscious)
    },
}) or_return

dos.apply(&w, guard01, "KnockedOut")    // runs on_attach; applying again does nothing
dos.unapply(&w, guard01, "KnockedOut")  // runs on_detach; unapplying an absent effect does nothing
dos.affected(&w, guard01, "KnockedOut")
```

Both hooks are optional. An applied effect is one bit in a runtime `ecs.Flags_Table` (128 effects per table), so it is saved with the game and usable in views:

```odin
term, _ := dos.effect_term(&w, "Burning")
ecs.view_init(&burning, dos.runtime(&w), {dos.table(&transforms), term})
```

Effects are not metas: metas live in the config id space and feed inheritance, effects live on objects and never enter it.
