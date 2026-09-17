# Values

A value is whatever a file authored under a name. ODE_DOS keeps the KDL node it came from, bakes it
through inheritance, and hands it to the game when it asks. There is nothing to declare: a name with
no argument is a flag, a name with several is a list, and a name whose node has children fills a
struct.

```kdl
archetype "Guard" parent="Human" {
    max-hit-points 100         // a number
    can-attach-rope            // a flag
    status "Alerted" "Dead"    // a list
    transform {                // a struct
        position 10.0 0.0 4.0
    }
}
```

## Reading

```odin
dos.has(&cfg, id, "can-attach-rope")   // bool: is the name set at all
dos.value(&cfg, id, "mass")            // (Load_Value, bool): the first argument
dos.args(&cfg, id, "status")           // []Load_Value: every argument
dos.node(&cfg, id, "transform")        // ^Load_Node: the raw tree
dos.names_of(&cfg, id)                 // []string: every name that resolves here

mass: Mass
dos.read(&cfg, id, "mass", &mass)      // fills any Odin type by reflection
```

`id` is an `object_id`, `archetype_id`, `meta_id` or `surface_id`. Scalars come out of a
`Load_Value` with `as_int`, `as_float`, `as_string` and `as_bool`.

`read` follows the same rules the KDL binder has always used: positional arguments fill fields in
order (a fixed array takes several), `key=value` pairs and child nodes set fields by name in either
case and with either separator, enums are read by name, and integers are range-checked. When a value
is not what the type wants, `read` returns `false` and records the problem — with the file, line and
column it was authored at — in [`errors`](loading.md).

`read_node` does the same for a node you already have, which is how link data is read.

## Precedence

For an object, a value comes from the first of:

1. what the object authored itself,
2. its archetype's metas, highest priority first (ties by name),
3. the archetype's own value,
4. the parent's metas, then the parent's own value,
5. and so on up to the root.

`bake` applies steps 2 to 5 once per archetype and surface, so reading is two lookups at most.
`load` bakes for you.

```odin
value, _ := dos.value(&cfg, guard01, "vision-range")
src := dos.source_of(&cfg, guard01, "vision-range")   // .Override, .Authored or .Meta
dos.source_name(&cfg, src)                            // "override", "core.Alert", ...
```

## What nothing reads

Because nothing is declared, a misspelled name in a file is not an error at load time — it is simply
a value nobody asks for. `unread` finds those after the game has built its world:

```odin
for e in dos.unread(&cfg) do fmt.eprintln(dos.format_error(e))
// data/core.kdl:3:5 nothing reads "masss"
```

A value counts as used once something reads it, or once something more specific shadows it, so
overridden defaults and inherited values do not show up here — only names that never reach anything.
