# KDL format

ODE_DOS reads [KDL v2](https://kdl.dev). A file is a list of these top-level nodes:

```kdl
namespace "core"          // optional; names declared below become core.Name

meta "Wooden" priority=0 {
    can-attach-rope
    footstep-sound "wood"
}

archetype "Physical" { mass 10.0 }
archetype "Creature" parent="Physical" { max-hit-points 100 }
archetype "Human" parent="Creature" {
    ai { vision-range 20.0 }
}
archetype "Guard" parent="Human" {
    ai { vision-range 30.0 }
    meta "Alert" priority=60
}

surface "WoodPlanks" { meta "Wooden" }

object "Guard01" archetype="Guard" {
    transform { position 10.0 0.0 4.0 }
    max-hit-points 75
    status "Alerted"
}

link "Contains" from="Guard01" to="Sword01" { slot "RightHand" }
```

| node | `key=value` | children |
|---|---|---|
| `namespace "N"` | | |
| `archetype "Name"` | `parent="Other"` | property values, flags, `meta` |
| `meta "Name"` | `priority=N` (default when attached) | property values, flags |
| `surface "Name"` | | property values, flags, `meta` |
| `object "Name"` | `archetype="A"` (required) | config overrides, state values, state flags |
| `link "Flavor"` | `from="Object"`, `to="Object"` | the link's data |

Inside an archetype, meta or surface, `meta "M" priority=N` attaches a meta; without `priority` it uses the meta's own `priority`, else 0.

## Names

Declared names are prefixed with the file's namespace. A reference (`parent=`, `archetype=`, `meta`, `from=`, `to=`) is looked up as `namespace.Ref` first, then as written, so `parent="Physical"` finds `core.Physical` inside `namespace "core"` and `archetype="core.Guard"` works from any namespace. File order and directory layout never matter.

## Values

A child node named after a declared `Property`, `State` or `State_Flags` sets it; the name is exactly the one given to `property_init`, `state_init` or `state_flags_init`.

- **Property and State values** are read into the Odin type by reflection:
  - positional arguments fill struct fields in order; a fixed array takes as many arguments as it has elements (`position 10.0 0.0 4.0` into `position: [3]f32`);
  - `key=value` pairs and child nodes set fields by name, in kebab-case or snake_case, any letter case (`slot "RightHand"` into `slot: Slot`);
  - enums are read by name, with the same rules (`"RightHand"` matches `Right_Hand`);
  - integers are range-checked for their Odin type; floats accept integers.

  A binding can supply its own decode proc for anything else (see [Loading](loading.md#custom-decoders)).
- **Flags** (`Flag`): the name alone means `#true`, or give `#true` / `#false`.
- **State flags** (`State_Flags`): one or more enum value names, `status "Alerted" "Burning"`.

A node that is not a declared name and has only children, like `ai { ... }`, is a group: its children are read as if they were written directly inside.

On an object, a `Property` value is an override; a `Flag` cannot be set on an object.
