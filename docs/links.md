# Links

Dark's link is `(source, flavor, destination, data)`. In ODE_DOS the flavor is the Odin type, so the data is statically typed. Each flavor is one `ecs.Pair_Table(T)` in the runtime database.

```odin
Contains :: struct { slot: Slot }
contains: dos.Link(Contains)
dos.link_init(&w, &contains, "Contains") or_return            // cap defaults to max_links

dos.link(&contains, guard01, sword01, Contains{ slot = .Right_Hand })  // linking again updates the data
dos.unlink(&contains, guard01, sword01)
dos.linked(&contains, guard01, sword01)
dos.link_data(&contains, guard01, sword01)    // (^Contains, bool)
dos.first_target(&contains, guard01)          // (object_id, ^Contains, bool): the most recent link
dos.count_out(&contains, guard01)
dos.count_in(&contains, sword01)
dos.unlink_all_from(&contains, guard01)
dos.unlink_all_to(&contains, sword01)
```

## Iteration

Both directions cost O(links of that object), never a table scan:

```odin
it := dos.outgoing(&contains, guard01)
for target, data in dos.next(&it) {
    fmt.println(dos.name_of(&w, target), data.slot)
}

it2 := dos.incoming(&contains, sword01)
for source, data in dos.next(&it2) { }
```

Unlinking the current link while iterating is safe.

## Autosnapping

Destroying an object removes every link to or from it, in every flavor, at a cost proportional to its own links. There are no dangling links.

## Views

`dos.link_table(&contains)` returns the `^ecs.Pair_Table(Contains)`; as an ODE_ECS view term it means "has at least one outgoing link".
