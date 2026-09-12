/*
    2026 (c) Oleh, https://github.com/zm69

    Registry of declared names (properties, flags, state flags, effects, links). Each binding
    carries its value type and a type-erased apply proc, so KDL loading can write values without
    knowing their Odin types. A derived Config sees the bindings of the Configs it is based on.
*/
package ode_dos

// Base
    import rt "base:runtime"

// Core
    import "core:strings"

// ODE
    import ecs "../../ode_ecs/src"

///////////////////////////////////////////////////////////////////////////////
// Binding

    Binding_Kind :: enum u8 {
        Property,
        Flag,
        State_Flags,
        Effect,
        Link,
    }

    Binding_Op :: enum u8 {
        Author,   // a = holder; value = ^T, ^bool for a Flag or an Effect, ^int for State_Flags
        Unauthor, // a = holder
        Link,     // a = from, b = to; value = ^T
    }

    Binding_Apply :: proc(data: rawptr, op: Binding_Op, a: ecs.entity_id, b: ecs.entity_id, value: rawptr) -> Error

    // What holder has: Property gives the value and its source, State_Flags whether enum value
    // index is set, Link its index-th outgoing link (other = target), Flag and Effect whether set.
    Binding_Read :: proc(data: rawptr, holder: ecs.entity_id, index: int) -> (value: rawptr, other: ecs.entity_id, source: Value_Source, ok: bool)

    // Reads a KDL node into out; report problems with decode_error.
    Decode_Proc :: proc(ctx: ^Decode_Context, node: ^Load_Node, out: rawptr) -> bool

    Binding :: struct {
        name:      string,
        hash:      u64,
        kind:      Binding_Kind,
        config:    ^Config,       // where it was declared
        type_info: ^rt.Type_Info, // value type; the enum for State_Flags; nil for Flag and Effect
        data:      rawptr,        // the Property, Flag, State_Flags, Effects or Link
        bit:       int,           // Effect: which bit of its Effects
        apply:     Binding_Apply,
        decode:    Decode_Proc,
        read:      Binding_Read,
    }

///////////////////////////////////////////////////////////////////////////////
// Private

    @(private)
    config__binding_exists :: proc(self: ^Config, name: string) -> bool {
        return config__find_binding(self, name) != nil
    }

    // This Config first, then the ones it is based on.
    @(private)
    config__find_binding :: proc(self: ^Config, name: string) -> ^Binding {
        h := name_hash(name)
        for c := self; c != nil; c = c.base {
            for &b in c.bindings {
                if b.hash == h do return &b
            }
        }
        return nil
    }

    @(private)
    config__add_binding :: proc(self: ^Config, name: string, kind: Binding_Kind, type_info: ^rt.Type_Info = nil, data: rawptr = nil, bit := 0, apply: Binding_Apply = nil, decode: Decode_Proc = nil, read: Binding_Read = nil) -> Error {
        if name == "" do return DOS_Error.Invalid_Name
        if config__binding_exists(self, name) do return DOS_Error.Name_Already_Exists

        copy := strings.clone(name, self.allocator) or_return
        _, err := append(&self.bindings, Binding{
            name      = copy,
            hash      = name_hash(name),
            kind      = kind,
            config    = self,
            type_info = type_info,
            data      = data,
            bit       = bit,
            apply     = apply,
            decode    = decode,
            read      = read,
        })
        if err != nil {
            delete(copy, self.allocator)
            return err
        }
        return nil
    }
