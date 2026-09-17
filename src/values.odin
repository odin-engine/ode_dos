/*
    2026 (c) Oleh, https://github.com/zm69

    Values: whatever the files authored under a name, kept as the KDL node it came from and baked
    through inheritance. Nothing is declared in code - a game reads a value when it builds its
    runtime, decoding the node into its own type by reflection.

    A name with no argument is a flag, a name with several is a list, and a name whose node has
    children fills a struct: they are all the same thing here.
*/
package ode_dos

// Base
    import rt "base:runtime"

// Core
    import "core:fmt"
    import "core:strings"

// ODE
    import kdl "../../ode_kdl/src"

///////////////////////////////////////////////////////////////////////////////
// Sources

    Source_Kind :: enum u8 {
        None,
        Override, // authored on the object itself
        Authored, // on the archetype or surface itself, or an ancestor
        Meta,
    }

    // Where a resolved value came from.
    Value_Source :: struct {
        kind: Source_Kind,
        id:   u32, // the entity that authored it
    }

    // A name that resolves on an entity, with the node and where it came from.
    Resolved :: struct {
        name:   string,
        node:   ^Load_Node,
        source: Value_Source,
    }

///////////////////////////////////////////////////////////////////////////////
// Reading

    values__has_object    :: proc(cfg: ^Config, id: object_id, name: string) -> bool    { return values__has(cfg, u32(id), name) }
    values__has_archetype :: proc(cfg: ^Config, id: archetype_id, name: string) -> bool { return values__has(cfg, u32(id), name) }
    values__has_meta      :: proc(cfg: ^Config, id: meta_id, name: string) -> bool      { return values__has(cfg, u32(id), name) }
    values__has_surface   :: proc(cfg: ^Config, id: surface_id, name: string) -> bool   { return values__has(cfg, u32(id), name) }

    values__node_object    :: proc(cfg: ^Config, id: object_id, name: string) -> ^Load_Node    { return values__node(cfg, u32(id), name) }
    values__node_archetype :: proc(cfg: ^Config, id: archetype_id, name: string) -> ^Load_Node { return values__node(cfg, u32(id), name) }
    values__node_meta      :: proc(cfg: ^Config, id: meta_id, name: string) -> ^Load_Node      { return values__node(cfg, u32(id), name) }
    values__node_surface   :: proc(cfg: ^Config, id: surface_id, name: string) -> ^Load_Node   { return values__node(cfg, u32(id), name) }

    values__read_object    :: proc(cfg: ^Config, id: object_id, name: string, out: ^$T) -> bool    { return values__read(cfg, u32(id), name, type_info_of(T), out) }
    values__read_archetype :: proc(cfg: ^Config, id: archetype_id, name: string, out: ^$T) -> bool { return values__read(cfg, u32(id), name, type_info_of(T), out) }
    values__read_meta      :: proc(cfg: ^Config, id: meta_id, name: string, out: ^$T) -> bool      { return values__read(cfg, u32(id), name, type_info_of(T), out) }
    values__read_surface   :: proc(cfg: ^Config, id: surface_id, name: string, out: ^$T) -> bool   { return values__read(cfg, u32(id), name, type_info_of(T), out) }

    values__value_object    :: proc(cfg: ^Config, id: object_id, name: string) -> (Load_Value, bool)    { return values__value(cfg, u32(id), name) }
    values__value_archetype :: proc(cfg: ^Config, id: archetype_id, name: string) -> (Load_Value, bool) { return values__value(cfg, u32(id), name) }
    values__value_meta      :: proc(cfg: ^Config, id: meta_id, name: string) -> (Load_Value, bool)      { return values__value(cfg, u32(id), name) }
    values__value_surface   :: proc(cfg: ^Config, id: surface_id, name: string) -> (Load_Value, bool)   { return values__value(cfg, u32(id), name) }

    values__args_object    :: proc(cfg: ^Config, id: object_id, name: string) -> []Load_Value    { return values__args(cfg, u32(id), name) }
    values__args_archetype :: proc(cfg: ^Config, id: archetype_id, name: string) -> []Load_Value { return values__args(cfg, u32(id), name) }
    values__args_meta      :: proc(cfg: ^Config, id: meta_id, name: string) -> []Load_Value      { return values__args(cfg, u32(id), name) }
    values__args_surface   :: proc(cfg: ^Config, id: surface_id, name: string) -> []Load_Value   { return values__args(cfg, u32(id), name) }

    values__source_object    :: proc(cfg: ^Config, id: object_id, name: string) -> Value_Source    { return values__source(cfg, u32(id), name) }
    values__source_archetype :: proc(cfg: ^Config, id: archetype_id, name: string) -> Value_Source { return values__source(cfg, u32(id), name) }
    values__source_meta      :: proc(cfg: ^Config, id: meta_id, name: string) -> Value_Source      { return values__source(cfg, u32(id), name) }
    values__source_surface   :: proc(cfg: ^Config, id: surface_id, name: string) -> Value_Source   { return values__source(cfg, u32(id), name) }

    values__names_object    :: proc(cfg: ^Config, id: object_id, allocator := context.temp_allocator) -> []string    { return values__names(cfg, u32(id), allocator) }
    values__names_archetype :: proc(cfg: ^Config, id: archetype_id, allocator := context.temp_allocator) -> []string { return values__names(cfg, u32(id), allocator) }
    values__names_meta      :: proc(cfg: ^Config, id: meta_id, allocator := context.temp_allocator) -> []string      { return values__names(cfg, u32(id), allocator) }
    values__names_surface   :: proc(cfg: ^Config, id: surface_id, allocator := context.temp_allocator) -> []string   { return values__names(cfg, u32(id), allocator) }

    // Fills out from a node, by the same reflection the loader uses; problems land in errors().
    values__read_node :: proc(cfg: ^Config, node: ^Load_Node, out: ^$T) -> bool {
        if node == nil do return false

        ctx := Decode_Context{ config = cfg, file = node.file }
        return binder__bind_node(&ctx, node, type_info_of(T), out)
    }

    // Names authored anywhere that nothing has read; typos show up here.
    values__unread :: proc(self: ^Config, allocator := context.temp_allocator) -> []Load_Error {
        res := make([dynamic]Load_Error, 0, 8, allocator)

        for ix in self.mine {
            e := config__entity(self, ix)
            if e == nil do continue

            for _, a in e.authored {
                if a.read do continue
                append(&res, Load_Error{
                    file    = self.files[a.node.file],
                    line    = a.node.location.line,
                    column  = a.node.location.column,
                    span    = len(a.node.name),
                    message = fmt.aprintf("nothing reads %q", a.node.name, allocator = allocator),
                })
            }
        }
        return res[:]
    }

///////////////////////////////////////////////////////////////////////////////
// Values

    values__as_int :: proc(v: Load_Value) -> (i64, bool) {
        n, is_number := v.value.variant.(kdl.Number)
        if !is_number do return 0, false

        switch x in n {
        case i64:    return x, true
        case f64:    return i64(x), true
        case string: return 0, false
        }
        return 0, false
    }

    values__as_float :: proc(v: Load_Value) -> (f64, bool) {
        n, is_number := v.value.variant.(kdl.Number)
        if !is_number do return 0, false

        switch x in n {
        case i64:    return f64(x), true
        case f64:    return x, true
        case string: return 0, false
        }
        return 0, false
    }

    values__as_string :: proc(v: Load_Value) -> (string, bool) {
        s, is_string := v.value.variant.(string)
        return s, is_string
    }

    values__as_bool :: proc(v: Load_Value) -> (bool, bool) {
        b, is_bool := v.value.variant.(bool)
        return b, is_bool
    }

///////////////////////////////////////////////////////////////////////////////
// Private

    @(private)
    values__has :: proc(cfg: ^Config, ix: u32, name: string) -> bool {
        return values__node(cfg, ix, name) != nil
    }

    @(private)
    values__node :: proc(cfg: ^Config, ix: u32, name: string) -> ^Load_Node {
        node, _ := values__resolve(cfg, ix, name_hash(name), mark = true)
        return node
    }

    @(private)
    values__read :: proc(cfg: ^Config, ix: u32, name: string, ti: ^rt.Type_Info, out: rawptr) -> bool {
        node := values__node(cfg, ix, name)
        if node == nil do return false

        ctx := Decode_Context{ config = cfg, file = node.file }
        return binder__bind_node(&ctx, node, ti, out)
    }

    @(private)
    values__value :: proc(cfg: ^Config, ix: u32, name: string) -> (Load_Value, bool) {
        node := values__node(cfg, ix, name)
        if node == nil || len(node.args) == 0 do return {}, false
        return node.args[0], true
    }

    @(private)
    values__args :: proc(cfg: ^Config, ix: u32, name: string) -> []Load_Value {
        node := values__node(cfg, ix, name)
        return node == nil ? nil : node.args
    }

    @(private)
    values__source :: proc(cfg: ^Config, ix: u32, name: string) -> Value_Source {
        _, src := values__resolve(cfg, ix, name_hash(name), mark = false)
        return src
    }

    @(private)
    values__names :: proc(cfg: ^Config, ix: u32, allocator := context.temp_allocator) -> []string {
        res := make([dynamic]string, 0, 16, allocator)
        for r in values__resolved(cfg, ix, allocator) do append(&res, r.name)
        return res[:]
    }

    // What the entity authored, else what its archetype baked; nil when nothing does.
    @(private)
    values__resolve :: proc(cfg: ^Config, ix: u32, hash: u64, mark: bool) -> (^Load_Node, Value_Source) {
        e := config__entity(cfg, ix)
        if e == nil do return nil, {}

        // an object's own value wins; for anything else bake already decided
        if e.kind == .Object {
            if a, own := e.authored[hash]; own {
                if mark {
                    values__mark(cfg, ix, hash)
                    values__mark_shadowed(cfg, e.archetype, hash) // the default it stands in for
                }
                return a.node, Value_Source{ kind = .Override, id = ix }
            }
        }

        holder := ix
        if e.kind == .Object {
            if e.archetype == NO_ID do return nil, {}
            holder = e.archetype
        }

        h := config__entity(cfg, holder)
        if h == nil do return nil, {}

        if b, baked := h.baked[hash]; baked {
            if mark do values__mark(cfg, b.from, hash)
            kind := config__kind_of(cfg, b.from) == .Meta ? Source_Kind.Meta : Source_Kind.Authored
            return b.node, Value_Source{ kind = kind, id = b.from }
        }
        return nil, {}
    }

    @(private)
    values__mark :: proc(cfg: ^Config, ix: u32, hash: u64) {
        e := config__entity(cfg, ix)
        if e == nil do return
        if a, has := e.authored[hash]; has {
            a.read = true
            e.authored[hash] = a
        }
    }

    // What an object's own value stands in for counts as used too.
    @(private)
    values__mark_shadowed :: proc(cfg: ^Config, holder: u32, hash: u64) {
        h := config__entity(cfg, holder)
        if h == nil do return
        if b, baked := h.baked[hash]; baked do values__mark(cfg, b.from, hash)
    }

    // Every name that resolves on an entity, in no particular order.
    @(private)
    values__resolved :: proc(cfg: ^Config, ix: u32, allocator := context.temp_allocator) -> []Resolved {
        res := make([dynamic]Resolved, 0, 16, allocator)
        seen := make(map[u64]bool, allocator = allocator)

        e := config__entity(cfg, ix)
        if e == nil do return res[:]

        if e.kind == .Object {
            for hash, a in e.authored {
                seen[hash] = true
                append(&res, Resolved{ name = a.node.name, node = a.node, source = Value_Source{ kind = .Override, id = ix } })
            }
        }

        holder := ix
        if e.kind == .Object do holder = e.archetype

        if h := config__entity(cfg, holder); h != nil && holder != ix {
            for hash, b in h.baked {
                if hash in seen do continue
                kind := config__kind_of(cfg, b.from) == .Meta ? Source_Kind.Meta : Source_Kind.Authored
                append(&res, Resolved{ name = b.node.name, node = b.node, source = Value_Source{ kind = kind, id = b.from } })
            }
        } else if e.kind != .Object {
            for hash, b in e.baked {
                if hash in seen do continue
                kind := config__kind_of(cfg, b.from) == .Meta ? Source_Kind.Meta : Source_Kind.Authored
                append(&res, Resolved{ name = b.node.name, node = b.node, source = Value_Source{ kind = kind, id = b.from } })
            }
        }

        slice_sort_by_name(res[:])
        return res[:]
    }

    // Stable output for dumps and tools.
    @(private)
    slice_sort_by_name :: proc(res: []Resolved) {
        for i in 1..<len(res) {
            for j := i; j > 0 && strings.compare(res[j].name, res[j - 1].name) < 0; j -= 1 {
                res[j], res[j - 1] = res[j - 1], res[j]
            }
        }
    }
