# ODE_DOS documentation

#### KDL
* [KDL format](kdl_format.md) — what the files look like
* [Loading](loading.md) — validation, diagnostics, hot reload, custom decoders

#### Configuration Space
* [Config](config.md) — setup, chaining Configs, capacity, errors
* [Properties](properties.md) — `Property(T)`, authoring, overrides
* [Archetypes, metas and surfaces](archetypes.md) — inheritance, mixins, precedence, bake
* [Flags and effects](flags.md) — `Flag`, `State_Flags(E)`, `Effects`
* [Links](links.md) — typed relations between objects
* [Reflection](reflection.md) — designed objects, queries, building your runtime

#### Runtime Space
* Your own [ODE_ECS](https://github.com/odin-engine/ode_ecs) Database or even something else.

#### Command-line interface
* [Inspect and CLI](inspect_cli.md) — `dump`, `explain`, and building a tool

#### Full API refernce

* [API](api.md) — every public procedure

## Samples

* [thief_demo](../samples/thief_demo/main.odin) — load, resolve, links, build an ODE_ECS world, save it
* [dos_tool](../samples/dos_tool/main.odin) — a command-line tool built from the game's declarations
