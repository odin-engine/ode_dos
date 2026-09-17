# ODE_DOS documentation

* [Config](config.md) — setup, chaining Configs, errors
* [Archetypes, metas and surfaces](archetypes.md) — inheritance, mixins, precedence, bake
* [Values](values.md) — what the files author, and how a game reads it
* [Objects](objects.md) — designed objects, queries, building your runtime
* [Links](links.md) — typed relations between objects
* [KDL format](kdl_format.md) — what the files look like
* [Loading](loading.md) — validation, diagnostics, hot reload
* [Inspect and CLI](inspect_cli.md) — `dump`, `explain`, and building a tool
* [API](api.md) — every public procedure

## Samples

* [thief_demo](../samples/thief_demo/main.odin) — load, read values, build an ODE_ECS world, save it
* [dos_tool](../samples/dos_tool/main.odin) — a command-line tool built from the game's own Config
