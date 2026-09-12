# Loading

```odin
dos.load(&cfg, "data/") or_return       // one .kdl file, or every one below a directory
```

A load is one transaction: parse, declare, resolve names, validate, and only then write. If anything
fails nothing changes, `load` returns `DOS_Error.Load_Failed`, and every problem is in `errors`.

```odin
if dos.load(&cfg, "data/") != nil {
    for e in dos.errors(&cfg) do fmt.eprintln(dos.format_error(e, context.temp_allocator))
}
```

Loading bakes at the end, so values resolve as soon as it returns.

## Diagnostics

`Load_Error` carries `file`, `line`, `column`, `span`, `message` and an optional `suggestion`.
`format_error` renders it with the source line, an underline and the suggestion:

```
data/bad/unknown_parent.kdl:2:24
  archetype "EliteGuard" parent="Humn"
                         ^^^^^^
  unknown archetype "Humn" — did you mean "Human"?
```

Suggestions come from an edit-distance search over what is declared, so typos in archetype, meta,
property, flag and enum names all point at the right thing.

## Hot reload

Loading names that already exist in the same Config updates them: their authored values, metas and
parent are replaced by what the file now says, and objects keep their ids. Nothing is deleted: an
archetype removed from a file stays until its Config is terminated.

```odin
dos.load(&cfg, "data/") or_return       // after a designer saves

for obj in dos.changed_objects(&cfg) { /* re-read this one and update your entity */ }
for a in dos.changed_archetypes(&cfg) { /* anything you built from it may differ */ }
```

Both lists are valid until the next load. A name that exists in another Config, or as another kind,
is an error.

## Custom decoders

By default a value is read by reflection: one argument fills a single field (a fixed array takes
several), `key=value` pairs and child nodes set fields by name. When a type wants a different shape,
pass a `decode` proc:

```odin
dos.property_init(&cfg, &colors, "color", proc(ctx: ^dos.Decode_Context, node: ^dos.Load_Node, out: rawptr) -> bool {
    c := cast(^Color) out
    if len(node.args) != 3 {
        dos.decode_error(ctx, node.location, "color takes r g b")
        return false
    }
    ...
    return true
})
```

`dos.bind_node` and `dos.bind_value` are the reflection binder, so a decoder can fall back to it for
parts it does not want to handle itself.
