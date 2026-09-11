# API

`import dos "ode_dos/src"`. Proc groups are marked with `|` between accepted argument types.

## World

```odin
world_init(w: ^World, cfg := World_Config{}) -> Error
world_terminate(w: ^World)
runtime(w: ^World) -> ^ecs.Database
user_data(w: ^World) -> rawptr
```

## Config sets

```odin
create_config_set(w: ^World, name: string) -> (config_set_id, Error)
find_config_set(w: ^World, name: string) -> (config_set_id, bool)
config_db(w: ^World, set := CORE) -> ^ecs.Database
unload_config_set(w: ^World, set: config_set_id) -> Error
```

## Archetypes, metas, surfaces

```odin
archetype(w: ^World, name: string, parent := "", set := CORE) -> (archetype_id, Error)
meta(w: ^World, name: string, set := CORE) -> (meta_id, Error)
surface(w: ^World, name: string, set := CORE) -> (surface_id, Error)
find_archetype(w: ^World, name: string) -> (archetype_id, bool)
find_meta(w: ^World, name: string) -> (meta_id, bool)
find_surface(w: ^World, name: string) -> (surface_id, bool)

parent_of(w: ^World, a: archetype_id) -> (archetype_id, bool)
chain_of(w: ^World, a: archetype_id) -> []archetype_id          // valid until the next chain query
is_kind_of(w: ^World, a: archetype_id, kind: archetype_id) -> bool

attach(w: ^World, holder: archetype_id | surface_id, meta: meta_id, priority := 0) -> Error
detach(w: ^World, holder: archetype_id | surface_id, meta: meta_id) -> Error
metas_of(w: ^World, holder: archetype_id | surface_id, allocator := context.temp_allocator) -> []Attachment

name_of(w: ^World, id: archetype_id | meta_id | surface_id | object_id) -> string
bake(w: ^World) -> Error
```

## Objects

```odin
spawn(w: ^World, archetype: string | archetype_id) -> (object_id, Error)
destroy(w: ^World, obj: object_id) -> Error
alive(w: ^World, obj: object_id) -> bool
archetype_of(w: ^World, obj: object_id) -> archetype_id
find(w: ^World, name: string) -> (object_id, bool)
set_name(w: ^World, obj: object_id, name: string) -> Error
on_spawn(w: ^World, hook: Spawn_Hook) -> Error          // Spawn_Hook :: proc(w: ^World, obj: object_id)
```

## Properties

```odin
property_init(w: ^World, c: ^Property($T), name: string, set := CORE, overrides_cap := 0, decode: Decode_Proc = nil) -> Error
set_property(c: ^Property($T), holder: archetype_id | meta_id | surface_id, value: T) -> Error
get_property(c: ^Property($T), holder: archetype_id | meta_id | surface_id) -> ^T
unset_property(c: ^Property($T), holder: archetype_id | meta_id | surface_id) -> Error
resolve(c: ^Property($T), x: object_id | archetype_id | surface_id) -> ^T
resolve_with_source(c: ^Property($T), obj: object_id) -> (^T, Value_Source)
local(c: ^Property($T), obj: object_id) -> ^T
override(c: ^Property($T), obj: object_id, value: T) -> Error
clear_override(c: ^Property($T), obj: object_id) -> Error

flag_init(w: ^World, f: ^Flag, name: string, set := CORE) -> Error
set_flag(f: ^Flag, holder: archetype_id | meta_id | surface_id, value: bool) -> Error
resolve_flag(f: ^Flag, x: object_id | archetype_id) -> bool
surface_flag(w: ^World, s: surface_id, f: ^Flag) -> bool
```

## State

```odin
state_init(w: ^World, s: ^State($T), name: string, cap := 0, decode: Decode_Proc = nil) -> Error
get(s: ^State($T), obj: object_id) -> ^T
add(s: ^State($T), obj: object_id, value: T) -> Error
remove(s: ^State($T), obj: object_id) -> Error
has(s: ^State($T), obj: object_id) -> bool

state_flags_init(w: ^World, s: ^State_Flags($E), name: string, cap := 0) -> Error
set(s: ^State_Flags($E), obj: object_id, flag: E) -> Error
unset(s: ^State_Flags($E), obj: object_id, flag: E) -> Error
is_set(s: ^State_Flags($E), obj: object_id, flag: E) -> bool
flags_of(s: ^State_Flags($E), obj: object_id) -> bit_set[E]

table(s: ^State($T) | ^State_Flags($E)) -> ^ecs.Table(T) | ^ecs.Flags_Table
```

## Links

```odin
link_init(w: ^World, l: ^Link($T), name: string, cap := 0, decode: Decode_Proc = nil) -> Error
link(l: ^Link($T), from, to: object_id, data: T) -> Error
unlink(l: ^Link($T), from, to: object_id) -> Error
linked(l: ^Link($T), from, to: object_id) -> bool
link_data(l: ^Link($T), from, to: object_id) -> (^T, bool)
first_target(l: ^Link($T), from: object_id) -> (object_id, ^T, bool)
count_out(l: ^Link($T), from: object_id) -> int
count_in(l: ^Link($T), to: object_id) -> int
unlink_all_from(l: ^Link($T), from: object_id) -> Error
unlink_all_to(l: ^Link($T), to: object_id) -> Error
outgoing(l: ^Link($T), from: object_id) -> Link_Iterator(T)
incoming(l: ^Link($T), to: object_id) -> Link_Iterator(T)
next(it: ^Link_Iterator($T)) -> (other: object_id, data: ^T, ok: bool)
link_table(l: ^Link($T)) -> ^ecs.Pair_Table(T)
```

## Effects

```odin
effect_register(w: ^World, name: string, effect: Effect) -> Error   // Effect{on_attach, on_detach}
apply(w: ^World, obj: object_id, name: string) -> Error
unapply(w: ^World, obj: object_id, name: string) -> Error
affected(w: ^World, obj: object_id, name: string) -> bool
effect_term(w: ^World, name: string) -> (ecs.Flags, bool)
```

## Loading

```odin
load(w: ^World, path: string, set := CORE) -> Error
errors(w: ^World) -> []Load_Error
format_error(e: Load_Error, allocator := context.allocator) -> string

// for decode procs: Decode_Proc :: proc(ctx: ^Decode_Context, node: ^Load_Node, out: rawptr) -> bool
bind_node(ctx: ^Decode_Context, node: ^Load_Node, ti: ^runtime.Type_Info, out: rawptr) -> bool
bind_value(ctx: ^Decode_Context, v: Load_Value, ti: ^runtime.Type_Info, out: rawptr) -> bool
decode_error(ctx: ^Decode_Context, loc: kdl.Location, format: string, args: ..any)
```

## Save and load

```odin
save_game(w: ^World, path: string) -> Error
load_game(w: ^World, path: string) -> Error
```

## Inspect and tooling

```odin
dump(w: ^World, obj: object_id, out: io.Writer)
explain(w: ^World, c: ^Property($T), obj: object_id, out: io.Writer)
source_name(w: ^World, src: Value_Source) -> string
cli_run(w: ^World, args: []string, out: io.Writer) -> int
```

## Types and constants

```odin
object_id, archetype_id, meta_id, surface_id :: distinct ecs.entity_id
config_set_id :: distinct int
CORE          :: config_set_id(0)
NO_CONFIG_SET :: config_set_id(-1)

Value_Source :: struct { kind: Source_Kind, id: ecs.entity_id }   // Source_Kind: None, Override, Authored, Meta
Attachment   :: struct { meta: meta_id, priority: i32 }
Load_Error   :: struct { file: string, line, column, span: int, message, suggestion: string }

DOS_VALIDATIONS (#config, default true)
DEFAULT_MAX_ARCHETYPES, DEFAULT_MAX_CONFIG_SETS, DEFAULT_MAX_OBJECTS, DEFAULT_MAX_LINKS, DEFAULT_MAX_NAMED_OBJECTS
MAX_SPAWN_HOOKS
CLI_USAGE
```
