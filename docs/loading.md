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

## What is checked, and when

Because nothing is declared in code, a load can only check what the files say about each other:
unknown or non-archetype parents, an object without an `archetype=`, names declared twice, metas on
metas, inheritance cycles, link endpoints, unknown top-level nodes, and KDL syntax.

Whether a value is the right *shape* is decided when the game reads it: `read` returns `false` and
records the problem, with the location it was authored at, in the same `errors` list. Names nothing
reads are found with [`unread`](values.md#what-nothing-reads).

## Diagnostics

`Load_Error` carries `file`, `line`, `column`, `span`, `message` and an optional `suggestion`.
`format_error` renders it with the source line, an underline and the suggestion:

```
data/bad/unknown_parent.kdl:2:24
  archetype "EliteGuard" parent="Humn"
                         ^^^^^^
  unknown archetype "Humn" — did you mean "Human"?
```

Suggestions come from an edit-distance search over what is declared, so typos in archetype, meta and
enum names point at the right thing.

## Hot reload

Loading names that already exist in the same Config updates them: their values, metas, parent and
links are replaced by what the files now say, and their ids stay the same. Nothing is deleted: an
archetype removed from a file stays until the Config is terminated.

```odin
dos.load(&cfg, "data/") or_return       // after a designer saves

for obj in dos.changed_objects(&cfg) { /* re-read this one and update your entity */ }
for a in dos.changed_archetypes(&cfg) { /* anything you built from it may differ */ }
```

Both lists are valid until the next load. A name that exists as another kind is an error.
