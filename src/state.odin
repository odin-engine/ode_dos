/*
    2026 (c) Oleh, https://github.com/zm69

    Runtime state: State(T) is one ecs.Table(T) and State_Flags(E) one ecs.Flags_Table in the
    runtime database. Gameplay iterates both through ODE_ECS directly.
*/
package ode_dos

// Base
    import "base:intrinsics"

// ODE
    import ecs "../../ode_ecs/src"

///////////////////////////////////////////////////////////////////////////////
// State

    State :: struct($T: typeid) {
        world: ^World,
        table: ecs.Table(T),
    }

    // cap defaults to max_objects.
    state__init :: proc(w: ^World, self: ^State($T), name: string, cap := 0, decode: Decode_Proc = nil) -> Error {
        when VALIDATIONS do assert(world__is_valid(w) && self != nil)

        if world__binding_exists(w, name) do return DOS_Error.Name_Already_Exists
        if !type_is_pod(type_info_of(T)) do return DOS_Error.Type_Not_POD
        ecs_err(ecs.table_init(&self.table, &w.runtime_db, cap > 0 ? cap : w.cfg.max_objects)) or_return
        self.world = w

        apply :: proc(data: rawptr, op: Binding_Op, a: ecs.entity_id, b: ecs.entity_id, value: rawptr) -> Error {
            if op != .Add do return nil
            return state__add(cast(^State(T))data, object_id(a), (cast(^T)value)^)
        }
        read :: proc(data: rawptr, obj: ecs.entity_id, index: int) -> (value: rawptr, other: ecs.entity_id, source: Value_Source, ok: bool) {
            v := state__get(cast(^State(T))data, object_id(obj))
            return v, {}, {}, v != nil
        }
        return world__add_binding(w, name, .State, NO_CONFIG_SET, type_info_of(T), self, apply, decode, read)
    }

    // nil when the object has no value.
    state__get :: proc(self: ^State($T), obj: object_id) -> ^T {
        return ecs.get_component(&self.table, ecs.entity_id(obj))
    }

    // Overwrites an existing value.
    state__add :: proc(self: ^State($T), obj: object_id, value: T) -> Error {
        c, err := ecs.add_component(&self.table, ecs.entity_id(obj))
        if c == nil do return ecs_err(err)
        c^ = value
        return nil
    }

    state__remove :: proc(self: ^State($T), obj: object_id) -> Error {
        return ecs_err(ecs.remove_component(&self.table, ecs.entity_id(obj)))
    }

    state__has :: proc(self: ^State($T), obj: object_id) -> bool {
        return ecs.has_component(&self.table, ecs.entity_id(obj))
    }

    state__table :: proc(self: ^State($T)) -> ^ecs.Table(T) {
        return &self.table
    }

///////////////////////////////////////////////////////////////////////////////
// State_Flags

    State_Flags :: struct($E: typeid) where intrinsics.type_is_enum(E) {
        world: ^World,
        table: ecs.Flags_Table,
    }

    // cap (objects with at least one flag) defaults to max_objects.
    state_flags__init :: proc(w: ^World, self: ^State_Flags($E), name: string, cap := 0) -> Error {
        when VALIDATIONS do assert(world__is_valid(w) && self != nil)

        if world__binding_exists(w, name) do return DOS_Error.Name_Already_Exists
        ecs_err(ecs.flags_table_init(&self.table, &w.runtime_db, cap > 0 ? cap : w.cfg.max_objects)) or_return
        self.world = w

        apply :: proc(data: rawptr, op: Binding_Op, a: ecs.entity_id, b: ecs.entity_id, value: rawptr) -> Error {
            if op != .Set_Bit do return nil
            self := cast(^State_Flags(E))data
            return ecs_err(ecs.flag(&self.table, a, (cast(^int)value)^))
        }
        read :: proc(data: rawptr, obj: ecs.entity_id, index: int) -> (value: rawptr, other: ecs.entity_id, source: Value_Source, ok: bool) {
            self := cast(^State_Flags(E))data
            return nil, {}, {}, ecs.has_flag(&self.table, obj, index)
        }
        return world__add_binding(w, name, .State_Flags, NO_CONFIG_SET, type_info_of(E), self, apply, nil, read)
    }

    state_flags__set :: proc(self: ^State_Flags($E), obj: object_id, flag: E) -> Error {
        return ecs_err(ecs.flag(&self.table, ecs.entity_id(obj), flag))
    }

    state_flags__unset :: proc(self: ^State_Flags($E), obj: object_id, flag: E) -> Error {
        return ecs_err(ecs.unflag(&self.table, ecs.entity_id(obj), flag))
    }

    state_flags__is_set :: proc(self: ^State_Flags($E), obj: object_id, flag: E) -> bool {
        return ecs.has_flag(&self.table, ecs.entity_id(obj), flag)
    }

    state_flags__flags_of :: proc(self: ^State_Flags($E), obj: object_id) -> (res: bit_set[E]) {
        bits := ecs.get_flags(&self.table, ecs.entity_id(obj))
        for v in E {
            if int(v) in bits do res += {v}
        }
        return
    }

    state_flags__table :: proc(self: ^State_Flags($E)) -> ^ecs.Flags_Table {
        return &self.table
    }
