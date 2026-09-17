# Config

A **`Config`** holds everything designers author: archetypes, metas, surfaces, the objects declared
in KDL, and the values they carry. Nothing about that data is declared in code — the files decide
what exists.

```odin
cfg: dos.Config
dos.config_init(&cfg, {}) or_return
defer dos.config_terminate(&cfg)

dos.load(&cfg, "data") or_return
```

A `Config` must not be moved after `config_init`; its records point into it. Everything it parses
lives in one arena, so terminating it frees the lot.

## Options

| field | default | meaning |
|---|---|---|
| `base` | nil | inherit from another Config |
| `user_data` | nil | how build code and tools reach your data |
| `allocator` | `context.allocator` | used for everything the Config allocates |

## Chaining Configs

A Config created with `base` can inherit that Config's archetypes and read what it authored. Nothing
flows the other way: the base cannot see the derived Config. Terminate derived Configs first.

```odin
base, dlc: dos.Config
dos.config_init(&base, {}) or_return
defer dos.config_terminate(&base)                 // declared first, so it runs last
dos.config_init(&dlc, { base = &base }) or_return
defer dos.config_terminate(&dlc)

dos.load(&base, "data/core") or_return
dos.load(&dlc, "data/dlc") or_return              // may say parent="core.Human"
```

That is how a base game and a DLC pack, or a shared library of archetypes and one mission, live side
by side. Ids are unique across a chain, so an id from the base means the same thing in the DLC.

## Ids

```odin
object_id    :: distinct u32 // a designed object
archetype_id :: distinct u32 // a template
meta_id      :: distinct u32 // a mixin
surface_id   :: distinct u32 // a material flyweight
```

They are indexes into the Config chain, stable across reloads and cheap to keep in a component of
your own, which is the usual way a runtime entity remembers what it was built from:

```odin
Of_Config :: struct { obj: dos.object_id }
```

## Memory

A load parses into the Config's arena and keeps the nodes, because a value is read later, when the
game builds its world. Reloading the same files leaves the previous nodes behind in the arena, so a
long editing session grows it; terminating the Config releases everything at once.

## Errors

`DOS_Error` is `Invalid_Name`, `Name_Already_Exists`, `Name_Not_Found`, `Wrong_Kind`, `Load_Failed`
or `Has_Derived`. Problems inside a load, and inside a `read` afterwards, are collected in
[`errors`](loading.md) rather than returned.
