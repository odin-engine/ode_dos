# API

Everything public, by area. `cfg` is a `^Config`, and `id` is an `object_id`, `archetype_id`,
`meta_id` or `surface_id`.

## Config

```odin
config_init(self: ^Config, opts := Config_Options{}) -> Error
config_terminate(self: ^Config)
user_data(self: ^Config) -> rawptr

Config_Options :: struct {
    base:      ^Config,
    user_data: rawptr,
    allocator: rt.Allocator,
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
name_of(cfg, id) -> string                       // proc group: all four id types

parent_of(cfg, id: archetype_id) -> (archetype_id, bool)
chain_of(cfg, id: archetype_id, allocator := context.temp_allocator) -> []archetype_id
is_kind_of(cfg, id: archetype_id, kind: archetype_id) -> bool

attach(cfg, holder, meta: meta_id, priority := 0) -> Error   // archetype or surface
detach(cfg, holder, meta: meta_id) -> Error
metas_of(cfg, holder) -> []Attachment
bake(cfg) -> Error                               // load bakes; needed after code changes
```

## Objects

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

## Values

```odin
has(cfg, id, name: string) -> bool
value(cfg, id, name: string) -> (Load_Value, bool)
args(cfg, id, name: string) -> []Load_Value
node(cfg, id, name: string) -> ^Load_Node
read(cfg, id, name: string, out: ^$T) -> bool
read_node(cfg, node: ^Load_Node, out: ^$T) -> bool
names_of(cfg, id, allocator := context.temp_allocator) -> []string

source_of(cfg, id, name: string) -> Value_Source
source_name(cfg, src: Value_Source) -> string
unread(cfg, allocator := context.temp_allocator) -> []Load_Error

as_int(v: Load_Value) -> (i64, bool)
as_float(v: Load_Value) -> (f64, bool)
as_string(v: Load_Value) -> (string, bool)
as_bool(v: Load_Value) -> (bool, bool)
```

## Links

```odin
links_of(cfg, obj: object_id, allocator := context.temp_allocator) -> []Link
links_to(cfg, obj: object_id, allocator := context.temp_allocator) -> []Link
link_data(cfg, from, to: object_id, flavor: string) -> (^Load_Node, bool)

Link :: struct { flavor: string, from, to: object_id, data: ^Load_Node }
```

## Loading and tooling

```odin
load(cfg, path: string) -> Error
errors(cfg) -> []Load_Error
format_error(e: Load_Error, allocator := context.allocator) -> string
bind_node(ctx: ^Decode_Context, node: ^Load_Node, ti: ^rt.Type_Info, out: rawptr) -> bool
bind_value(ctx: ^Decode_Context, v: Load_Value, ti: ^rt.Type_Info, out: rawptr) -> bool

dump(cfg, obj: object_id, out: io.Writer)
explain(cfg, obj: object_id, name: string, out: io.Writer) -> bool
cli_run(cfg, args: []string, out: io.Writer) -> int
```

## Types and constants

```odin
object_id, archetype_id, meta_id, surface_id   // distinct u32
Config, Config_Options, Config_Kind
Attachment   :: struct { meta: meta_id, priority: i32 }
Source_Kind  :: enum { None, Override, Authored, Meta }
Value_Source :: struct { kind: Source_Kind, id: u32 }
Resolved     :: struct { name: string, node: ^Load_Node, source: Value_Source }
Link, Load_Node, Load_Value, Load_Property, Load_Error, Decode_Context
DOS_Error, Error
NO_ID         // an id that names nothing
VALIDATIONS   // -define:DOS_VALIDATIONS=false to compile the checks out
```
