# Flags and effects

Three ways to author bits. All three are baked with the same inheritance rules as properties, and all
three hand the game a bit set it can drop into its own `ecs.Flags_Table`.

## Flag

A single named boolean.

```odin
rope: dos.Flag
dos.flag_init(&cfg, &rope, "can-attach-rope") or_return

dos.set_flag(&rope, wooden)          // archetype_id, meta_id, surface_id or object_id
dos.set_flag(&rope, crate01, false)  // an object can turn an inherited flag off
dos.resolve_flag(&rope, crate01)     // bool
```

## State_Flags(E)

The flags an object starts with, one bit per enum value.

```odin
Status :: enum u8 { Dead, Unconscious, Alerted }

status: dos.State_Flags(Status)
dos.state_flags_init(&cfg, &status, "status") or_return

dos.set_state_flag(&status, guard, Status.Alerted)
dos.is_state_flag(&status, guard01, Status.Alerted)   // bool
dos.state_flags_of(&status, guard01)                  // bit_set[Status]
dos.bits_of(&status, guard01)                         // ecs.Bits, indexed by the enum
```

`bits_of` is the one a game wants: the bits are numbered by the enum, so they go straight into a
`Flags_Table` of your own.

```odin
ecs.set_flags(&g.statuses, e, dos.bits_of(&status, obj))
```

## Effects

Named changes a designer can put on an archetype or an object — KnockedOut, Burning. ODE_DOS keeps
the names, their bits and what authored them; what an effect *does* is your game's business.

```odin
fx: dos.Effects
dos.effects_init(&cfg, &fx, 32) or_return          // reserves 32 bits
knocked := dos.effect_register(&fx, "KnockedOut") or_return

dos.set_effect(&fx, guard, "KnockedOut")           // also on an object
dos.has_effect(&fx, guard01, "KnockedOut")
dos.effect_bit(&fx, "KnockedOut")                  // (int, bool)
dos.effect_name(&fx, knocked)                      // "KnockedOut"
dos.effect_count(&fx)
ecs.set_flags(&g.effects, e, dos.bits_of(&fx, obj))
```

Every registered name becomes a KDL keyword, so `KnockedOut` on an object or archetype sets it.

## Capacity

Bits live in groups of 128 per Config. A `Flag` takes one, a `State_Flags(E)` takes one per enum
value, and `Effects` takes the capacity you ask for. Running out returns `DOS_Error.Out_Of_Flags`.
