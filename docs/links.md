# Links

A **`Link(T)`** is a typed relation between designed objects: `(from, flavor, to, data)`. Each flavor
is one `ecs.Pair_Table(T)` in the Config's Database.

```odin
Contains :: struct { slot: Slot }

contains: dos.Link(Contains)
dos.link_init(&cfg, &contains, "Contains", cap = 8192) or_return
```

`cap` bounds the links of this flavor and defaults to 32,768.

## Linking

```odin
dos.link(&contains, guard01, sword01, Contains{ .Right_Hand })  // updates the data if it exists
dos.unlink(&contains, guard01, sword01)
dos.linked(&contains, guard01, sword01)                         // bool
dos.link_data(&contains, guard01, sword01)                      // (^Contains, bool)
dos.count_out(&contains, guard01)
dos.count_in(&contains, sword01)
```

## Iterating

Both directions, with the other end and the data:

```odin
it := dos.links_of(&contains, guard01)     // outgoing
for target, data in dos.next(&it) {
    fmt.println(dos.name_of(&cfg, target), data.slot)
}

back := dos.links_to(&contains, sword01)   // incoming
for holder, data in dos.next(&back) { ... }
```

`dos.link_table(&contains)` hands out the `ecs.Pair_Table(T)` if you want ODE_ECS directly.

## They are metadata

Links describe what a designer wired up. A game usually reads them once, when it builds its world,
and turns them into whatever it actually needs — an inventory array, a constraint list, a graph of
its own. Nothing says your runtime has to have links at all.
