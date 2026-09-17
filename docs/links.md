# Links

A link is a typed relation a designer wires between two objects: `(from, flavor, to, data)`.

```kdl
link "Contains" from="Guard01" to="Sword01" {
    slot "RightHand"
}
```

## Reading them

```odin
for l in dos.links_of(&cfg, guard01) {      // outgoing
    fmt.println(l.flavor, dos.name_of(&cfg, l.to))

    data: Contains
    dos.read_node(&cfg, l.data, &data)      // the link's own values
}

for l in dos.links_to(&cfg, sword01) { … }  // incoming

node, ok := dos.link_data(&cfg, guard01, sword01, "Contains")
```

`Link` is `{ flavor: string, from, to: object_id, data: ^Load_Node }`, and both listing procedures
return a fresh slice from `context.temp_allocator` unless you pass an allocator.

## They are metadata

Links describe what a designer wired up. A game usually reads them once, when it builds its world,
and turns them into whatever it actually needs — an inventory array, a constraint list, a graph of
its own. Nothing says your runtime has to have links at all.
