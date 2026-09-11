/*
    2026 (c) Oleh, https://github.com/zm69

    Registry of declared names (config values, state, flags, links, effects). Each binding
    carries its value type and a type-erased apply proc, so KDL loading can write values
    without knowing their Odin types.
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
        State,
        State_Flags,
        Flag,
        Link,
        Effect,
    }

    Binding_Op :: enum u8 {
        Author,   // a = holder; value = ^T, or ^bool for a Flag
        Unauthor, // a = holder
        Override, // a = object; value = ^T
        Add,      // a = object; value = ^T
        Set_Bit,  // a = object; value = ^int
        Link,     // a = from, b = to; value = ^T
    }

    Binding_Apply :: proc(data: rawptr, op: Binding_Op, a: ecs.entity_id, b: ecs.entity_id, value: rawptr) -> Error

    // What obj has: Property and State give the value (Property also its source), State_Flags whether
    // enum value index is set, Link its index-th outgoing link (other = target), Flag whether set.
    Binding_Read :: proc(data: rawptr, obj: ecs.entity_id, index: int) -> (value: rawptr, other: ecs.entity_id, source: Value_Source, ok: bool)

    // Reads a KDL node into out; report problems with decode_error.
    Decode_Proc :: proc(ctx: ^Decode_Context, node: ^Load_Node, out: rawptr) -> bool

    Binding :: struct {
        name:      string,
        hash:      u64,
        kind:      Binding_Kind,
        set:       config_set_id, // NO_CONFIG_SET for runtime bindings
        type_info: ^rt.Type_Info, // value type; the enum for State_Flags; nil for Flag and Effect
        data:      rawptr,        // the Property, State, State_Flags, Flag or Link
        apply:     Binding_Apply,
        decode:    Decode_Proc,
        read:      Binding_Read,
        overridable: bool,          // Property: objects can override it
    }

///////////////////////////////////////////////////////////////////////////////
// Private

    @(private)
    world__binding_exists :: proc(self: ^World, name: string) -> bool {
        return world__find_binding(self, name) != nil
    }

    @(private)
    world__find_binding :: proc(self: ^World, name: string) -> ^Binding {
        h := name_hash(name)
        for &b in self.bindings {
            if b.hash == h do return &b
        }
        return nil
    }

    @(private)
    world__add_binding :: proc(self: ^World, name: string, kind: Binding_Kind, set := NO_CONFIG_SET, type_info: ^rt.Type_Info = nil, data: rawptr = nil, apply: Binding_Apply = nil, decode: Decode_Proc = nil, read: Binding_Read = nil) -> Error {
        if name == "" do return DOS_Error.Invalid_Name
        if world__binding_exists(self, name) do return DOS_Error.Name_Already_Exists

        copy := strings.clone(name, self.allocator) or_return
        _, err := append(&self.bindings, Binding{
            name      = copy,
            hash      = name_hash(name),
            kind      = kind,
            set       = set,
            type_info = type_info,
            data      = data,
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

    // Plain data only (no strings, pointers, slices, maps or other references), so it can be saved.
    @(private)
    type_is_pod :: proc(ti: ^rt.Type_Info) -> bool {
        base := rt.type_info_base(ti)
        #partial switch v in base.variant {
        case rt.Type_Info_Integer, rt.Type_Info_Rune, rt.Type_Info_Float, rt.Type_Info_Complex, rt.Type_Info_Quaternion,
             rt.Type_Info_Boolean, rt.Type_Info_Enum, rt.Type_Info_Bit_Set, rt.Type_Info_Bit_Field, rt.Type_Info_Matrix:
            return true
        case rt.Type_Info_Array:
            return type_is_pod(v.elem)
        case rt.Type_Info_Enumerated_Array:
            return type_is_pod(v.elem)
        case rt.Type_Info_Struct:
            for i in 0..<int(v.field_count) {
                if !type_is_pod(v.types[i]) do return false
            }
            return true
        }
        return false
    }
