# ODE_DOS documentation

* [World and config sets](world.md) — setup, id spaces, config sets, errors
* [Archetypes, metas and surfaces](archetypes.md) — inheritance, mixins, precedence, bake
* [Properties and state](properties_and_state.md) — `Property(T)`, `Flag`, `State(T)`, `State_Flags(E)`
* [Objects](objects.md) — spawning, spawn hooks, names
* [Links](links.md) — typed relations and autosnapping
* [Effects](effects.md) — runtime status effects
* [KDL format](kdl_format.md) — what the files look like
* [Loading](loading.md) — validation, diagnostics, hot reload, custom decoders
* [Save and load](save_load.md) — saving runtime state
* [Inspect and CLI](inspect_cli.md) — `dump`, `explain`, and building a tool
* [API](api.md) — every public procedure

## Samples

* [thief_demo](../samples/thief_demo/main.odin) — load, resolve, links, effects, a frame loop, save and load
* [dos_tool](../samples/dos_tool/main.odin) — a command-line tool built from the game's declarations
