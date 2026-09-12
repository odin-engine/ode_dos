# API

Everything public, by area. `cfg` is a `^Config`.

## Config

```odin
config_init(self: ^Config, opts := Config_Options{}) -> Error
config_terminate(self: ^Config)
config_db(self: ^Config) -> ^ecs.Database
config_capacity(self: ^Config) -> (entities: int, attachments: int)
user_data(self: ^Config) -> rawptr

Config_Options :: struct {
    base:        ^Config,
    max_derived: int,
    keep_names:  Maybe(bool),
    user_data:   rawptr,
    allocator:   rt.Allocator,
}
```

## Archetypes, metas, surfaces

```odin
archetype(cfg, name: string, parent := "") -> (archetype_id, Error)
meta(cfg, name: string) -> (meta_id, Error)
surface(cfg, name: string) -> (surface_id, Error)

find_archetype(cfg, name: string) -> (archetype_id, bool)
find_meta(cfg, name: string) -> (meta_id, bool)
find_surface(cfg, name: string) -> (surface_id, bool)
name_of(cfg, id) -> string                        // proc group: archetype, meta, surface, object

parent_of(cfg, id: archetype_id) -> (archetype_id, bool)
chain_of(cfg, id: archetype_id) -> []archetype_id
is_kind_of(cfg, id: archetype_id, kind: archetype_id) -> bool

attach(cfg, holder, meta: meta_id, priority := 0) -> Error   // proc group: archetype or surface
detach(cfg, holder, meta: meta_id) -> Error
metas_of(cfg, holder, allocator := context.temp_allocator) -> []Attachment
bake(cfg) -> Error
```

## Properties

```odin
property_init(cfg, self: ^Property($T), name: string, decode: Decode_Proc = nil) -> Error

set_property(self: ^Property($T), holder, value: T) -> Error   // archetype, meta, surface or object
get_property(self: ^Property($T), holder) -> ^T                // authored here only
unset_property(self: ^Property($T), holder) -> Error

resolve(self: ^Property($T), id) -> ^T                         // object, archetype or surface
resolve_with_source(self: ^Property($T), obj: object_id) -> (^T, Value_Source)
source_name(cfg, src: Value_Source) -> string
```

## Flags, state flags and effects

```odin
flag_init(cfg, self: ^Flag, name: string) -> Error
set_flag(self: ^Flag, holder, value := true) -> Error
resolve_flag(self: ^Flag, id) -> bool                          // object, archetype or surface

state_flags_init(cfg, self: ^State_Flags($E), name: string) -> Error
set_state_flag(self: ^State_Flags($E), holder, flag: E, value := true) -> Error
is_state_flag(self: ^State_Flags($E), obj: object_id, flag: E) -> bool
state_flags_of(self: ^State_Flags($E), obj: object_id) -> bit_set[E]

effects_init(cfg, self: ^Effects, cap := 32) -> Error
effect_register(self: ^Effects, name: string) -> (bit: int, err: Error)
effect_bit(self: ^Effects, name: string) -> (int, bool)
effect_name(self: ^Effects, bit: int) -> string
effect_count(self: ^Effects) -> int
set_effect(self: ^Effects, holder, name: string, value := true) -> Error
has_effect(self: ^Effects, obj: object_id, name: string) -> bool

bits_of(self, obj: object_id) -> ecs.Bits    // proc group: State_Flags(E) and Effects
```

## Objects and queries

```odin
object(cfg, archetype: archetype_id, name := "") -> (object_id, Error)
find(cfg, name: string) -> (object_id, bool)
set_name(cfg, obj: object_id, name: string) -> Error
archetype_of(cfg, obj: object_id) -> archetype_id

objects(cfg, allocator := context.temp_allocator) -> []object_id
objects_of(cfg, archetype: archetype_id, allocator := context.temp_allocator) -> []object_id
changed_objects(cfg, allocator := context.temp_allocator) -> []object_id
changed_archetypes(cfg, allocator := context.temp_allocator) -> []archetype_id
```

## Links

```odin
link_init(cfg, self: ^Link($T), name: string, cap := 0, decode: Decode_Proc = nil) -> Error
link(self: ^Link($T), from, to: object_id, data: T) -> Error
unlink(self: ^Link($T), from, to: object_id) -> Error
linked(self: ^Link($T), from, to: object_id) -> bool
link_data(self: ^Link($T), from, to: object_id) -> (^T, bool)
first_target(self: ^Link($T), from: object_id) -> (object_id, ^T, bool)
count_out(self: ^Link($T), from: object_id) -> int
count_in(self: ^Link($T), to: object_id) -> int
links_of(self: ^Link($T), from: object_id) -> Link_Iterator(T)
links_to(self: ^Link($T), to: object_id) -> Link_Iterator(T)
next(it: ^Link_Iterator($T)) -> (other: object_id, data: ^T, ok: bool)
link_table(self: ^Link($T)) -> ^ecs.Pair_Table(T)
```

## Loading and tooling

```odin
load(cfg, path: string) -> Error
errors(cfg) -> []Load_Error
format_error(e: Load_Error, allocator := context.allocator) -> string
decode_error(ctx: ^Decode_Context, loc: kdl.Location, format: string, args: ..any)
bind_node(ctx: ^Decode_Context, node: ^Load_Node, ti: ^rt.Type_Info, out: rawptr) -> bool
bind_value(ctx: ^Decode_Context, v: Load_Value, ti: ^rt.Type_Info, out: rawptr) -> bool

dump(cfg, obj: object_id, out: io.Writer)
explain(cfg, property: ^Property($T), obj: object_id, out: io.Writer)
cli_run(cfg, args: []string, out: io.Writer) -> int
```

## Types and constants

```odin
object_id, archetype_id, meta_id, surface_id   // distinct ecs.entity_id
Config, Config_Options, Config_Kind
Property($T), Flag, State_Flags($E), Effects, Link($T), Link_Iterator($T), Link_Row
Attachment :: struct { meta: meta_id, priority: i32 }
Source_Kind :: enum { None, Override, Authored, Meta }
Value_Source :: struct { kind: Source_Kind, id: ecs.entity_id }
Load_Error, Decode_Context, Decode_Proc, Load_Node, Load_Value
DOS_Error, Error
FLAGS_PER_GROUP, DEFAULT_EFFECTS_CAP, DEFAULT_MAX_DERIVED, DEFAULT_MAX_LINKS
VALIDATIONS   // -define:DOS_VALIDATIONS=false to compile the checks out
```
