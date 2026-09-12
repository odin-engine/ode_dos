# Loading

```odin
dos.load(&w, "data/") or_return                   // every .kdl file below data/, into CORE
dos.load(&w, "data/dlc_weapons/", set = dlc)       // into another config set
dos.load(&w, "data/core.kdl")                      // one file
```

`load` reads the files in sorted path order with ODE_KDL's streaming parser, then:

1. collects every declaration;
2. resolves every name (parents, metas, archetypes, link flavors and endpoints);
3. checks everything: duplicate names, unknown names, inheritance cycles, the parent-set rule, unknown or mistyped values, bad enum names, out-of-range numbers;
4. **only if nothing failed**, writes to the World: creates archetypes, metas and surfaces, sets parents, metas and values, bakes, creates objects (overrides, then spawn hooks, then state values from the file), and adds links.

A failed load leaves the World as it was and returns `DOS_Error.Load_Failed`.

## Diagnostics

```odin
if dos.load(&w, "data/") != nil {
    for e in dos.errors(&w) do fmt.println(dos.format_error(e))
}
```

```
data/archetypes/guards.kdl:2:24
  archetype "EliteGuard" parent="Humn"
                         ^^^^^^
  unknown archetype "Humn" — did you mean "Human"?
```

`Load_Error` has `file`, `line`, `column`, `span`, `message` and `suggestion`. Errors are valid until the next `load`. Suggestions need the name strings, so they cover names from the current load, plus everything else when `keep_names` is on.

## Hot reload

Loading names that already exist in the same config set updates them: their authored values, metas and parent are replaced by what the file now says, objects that already exist are kept (their values from the file are applied again), and links are linked again. Nothing is deleted: an archetype removed from a file stays until its set is unloaded.

```odin
dos.load(&w, "data/") or_return   // after editing a file
```

A name that exists in another set, or as another kind, is an error.

A load grows config space by exactly what it adds; see [Config capacity](world.md#config-capacity).

## Custom decoders

Reflection covers structs, fixed arrays, integers, floats, booleans, strings and enums. For anything else, pass a decode proc to `property_init`, `state_init` or `link_init`:

```odin
decode_color :: proc(ctx: ^dos.Decode_Context, node: ^dos.Load_Node, out: rawptr) -> bool {
    c := cast(^Color)out
    if len(node.args) != 1 {
        dos.decode_error(ctx, node.location, "color takes one \"#rrggbb\" value")
        return false
    }
    // ... parse node.args[0].value into c
    return true
}

dos.property_init(&w, &tint, "tint", decode = decode_color) or_return
```

`dos.bind_node(ctx, node, type_info_of(T), out)` and `dos.bind_value(ctx, value, type_info_of(T), out)` run the default reflection for parts of a node.
