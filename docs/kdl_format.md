# KDL format

Everything a designer authors is [KDL](https://kdl.dev). Top-level nodes:

| node | `key=value` | children |
|---|---|---|
| `namespace "core"` | — | — (applies to the rest of the file) |
| `archetype "Name"` | `parent="Other"` | property values, flags, state flags, effects, `meta` |
| `meta "Name"` | `priority=50` | property values, flags, state flags, effects |
| `surface "Name"` | — | the same, plus `meta` |
| `object "Name"` | `archetype="A"` (required) | the same as an archetype, minus `meta` |
| `link "Flavor"` | `from="A"` `to="B"` | the link's data |

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
    can-attach-rope #false
    meta "Alert"
}

surface "WoodPlanks" {
    meta "Wooden"
}

object "Guard01" archetype="core.Guard" {
    max-hit-points 75          // this one is wounded
    transform { position 10.0 0.0 4.0 }
    status "Alerted"
    KnockedOut
}

link "Contains" from="Guard01" to="Sword01" {
    slot "RightHand"
}
```

## Values

A child node names a declared `Property`, `Flag`, `State_Flags` or effect:

- a **property** takes whatever its type needs — one argument for a single field, several for a fixed
  array, `key=value` pairs or child nodes for a struct;
- a **flag** or an **effect** is the name alone, or the name with `#true` / `#false`;
- **state flags** take one or more enum-value names: `status "Alerted" "Dead"`.

On an object these are the object's own values, which beat everything its archetype says. A node with
only children and no value of its own is a group, so files can be organized freely:

```kdl
archetype "Guard" parent="Human" {
    ai {
        vision-range 30.0
    }
}
```

## Names

Names are dotted. `namespace "core"` prefixes every name declared in the rest of the file, and a
reference is tried first inside the current namespace, then as written. Archetypes, metas and surfaces
share one namespace; objects have their own.

Enum values match by name, ignoring case, `_` and `-`, so `"RightHand"`, `"right_hand"` and
`"Right-Hand"` all mean `Right_Hand`.
