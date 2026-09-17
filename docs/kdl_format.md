# KDL format

Everything a designer authors is [KDL](https://kdl.dev). Top-level nodes:

| node | `key=value` | children |
|---|---|---|
| `namespace "core"` | — | — (applies to the rest of the file) |
| `archetype "Name"` | `parent="Other"` | values, and `meta` |
| `meta "Name"` | `priority=50` | values |
| `surface "Name"` | — | values, and `meta` |
| `object "Name"` | `archetype="A"` (required) | values |
| `link "Flavor"` | `from="A"` `to="B"` | the link's own values |

```kdl
namespace "core"

meta "Alert" priority=50 {
    vision-range 45.0
}

archetype "Physical" {
    mass 10.0
}

archetype "Guard" parent="Physical" {
    max-hit-points 100
    can-attach-rope
    meta "Alert"
}

surface "WoodPlanks" {
    meta "Wooden"
}

object "Guard01" archetype="core.Guard" {
    max-hit-points 75          // this one is wounded
    transform { position 10.0 0.0 4.0 }
    status "Alerted" "Dead"
}

link "Contains" from="Guard01" to="Sword01" {
    slot "RightHand"
}
```

## Values

Every child node that is not `meta` is a value, stored under its own name. What it means is up to the
game that reads it:

- no arguments — a flag, `dos.has` answers it;
- one argument — a number, string or boolean, `dos.value` returns it;
- several — a list, `dos.args` returns them;
- children — a struct or anything nested, `dos.read` fills your type or `dos.node` hands you the tree.

On an object these are the object's own values, and they beat everything its archetype says. Names
are matched loosely when a value is read into a struct field or an enum: letter case, `-` and `_` are
ignored, so `RightHand`, `right_hand` and `Right-Hand` all mean `Right_Hand`.

Nothing checks a name against a list, so a file may carry values no game reads yet — and a typo is
found by [`unread`](values.md#what-nothing-reads) rather than by the loader.

## Names

Names are dotted. `namespace "core"` prefixes every name declared in the rest of the file, and a
reference is tried first inside the current namespace, then as written. Archetypes, metas and
surfaces share one namespace; objects have their own.
