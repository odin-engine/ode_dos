/*
    2026 (c) Oleh, https://github.com/zm69

    State_Flags(E): the flags an object starts with, authored per enum value on archetypes, metas,
    surfaces and objects. They are metadata, not runtime state: bits_of hands you the whole set
    with the enum's own bit indices, so it drops straight into your own ecs.Flags_Table.
*/
package ode_dos

// Base
    import "base:intrinsics"

// ODE
    import ecs "../../ode_ecs/src"

///////////////////////////////////////////////////////////////////////////////
// State_Flags

    State_Flags :: struct($E: typeid) where intrinsics.type_is_enum(E) {
        config: ^Config,
        group:  ^Flag_Group,
        first:  int, // its bits are first + int(value)
    }

    state_flags__init :: proc(cfg: ^Config, self: ^State_Flags($E), name: string) -> Error {
        when VALIDATIONS do assert(config__is_valid(cfg) && self != nil)

        if config__binding_exists(cfg, name) do return DOS_Error.Name_Already_Exists

        group, first := config__reserve_bits(cfg, enum_bit_count(E)) or_return
        self.config = cfg
        self.group = group
        self.first = first

        apply :: proc(data: rawptr, op: Binding_Op, a: ecs.entity_id, b: ecs.entity_id, value: rawptr) -> Error {
            self := cast(^State_Flags(E))data
            #partial switch op {
            case .Author:   return flag_group__author(self.group, a, self.first + (cast(^int)value)^, true)
            case .Unauthor: state_flags__unauthor(self, a)
            }
            return nil
        }
        read :: proc(data: rawptr, holder: ecs.entity_id, index: int) -> (value: rawptr, other: ecs.entity_id, source: Value_Source, ok: bool) {
            self := cast(^State_Flags(E))data
            return nil, {}, {}, (self.first + index) in flag_group__bits_of(self.group, holder)
        }
        return config__add_binding(cfg, name, .State_Flags, type_info_of(E), self, 0, apply, nil, read)
    }

///////////////////////////////////////////////////////////////////////////////
// Authoring

    state_flags__set_archetype :: proc(self: ^State_Flags($E), holder: archetype_id, flag: E, value := true) -> Error {
        return state_flags__set(self, ecs.entity_id(holder), .Archetype, flag, value)
    }

    state_flags__set_meta :: proc(self: ^State_Flags($E), holder: meta_id, flag: E, value := true) -> Error {
        return state_flags__set(self, ecs.entity_id(holder), .Meta, flag, value)
    }

    state_flags__set_surface :: proc(self: ^State_Flags($E), holder: surface_id, flag: E, value := true) -> Error {
        return state_flags__set(self, ecs.entity_id(holder), .Surface, flag, value)
    }

    state_flags__set_object :: proc(self: ^State_Flags($E), holder: object_id, flag: E, value := true) -> Error {
        return state_flags__set(self, ecs.entity_id(holder), .Object, flag, value)
    }

///////////////////////////////////////////////////////////////////////////////
// Reading

    state_flags__is_set :: proc(self: ^State_Flags($E), obj: object_id, flag: E) -> bool {
        return (self.first + int(flag)) in flag_group__bits_of(self.group, ecs.entity_id(obj))
    }

    state_flags__flags_of :: proc(self: ^State_Flags($E), obj: object_id) -> (res: bit_set[E]) {
        bits := flag_group__bits_of(self.group, ecs.entity_id(obj))
        for v in E {
            if (self.first + int(v)) in bits do res += {v}
        }
        return
    }

    // The same bits, indexed by the enum, ready for ecs.set_flags on your own Flags_Table.
    state_flags__bits_of :: proc(self: ^State_Flags($E), obj: object_id) -> (res: ecs.Bits) {
        bits := flag_group__bits_of(self.group, ecs.entity_id(obj))
        for v in E {
            if (self.first + int(v)) in bits do res += {int(v)}
        }
        return
    }

///////////////////////////////////////////////////////////////////////////////
// Private

    @(private)
    state_flags__set :: proc(self: ^State_Flags($E), holder: ecs.entity_id, kind: Config_Kind, flag: E, value: bool) -> Error {
        if !config__config_is(self.config, holder, kind) do return DOS_Error.Wrong_Kind
        return flag_group__author(self.group, holder, self.first + int(flag), value)
    }

    @(private)
    state_flags__unauthor :: proc(self: ^State_Flags($E), holder: ecs.entity_id) {
        for v in E do flag_group__unauthor(self.group, holder, self.first + int(v))
    }

    // Bits are indexed by enum value, so the count is the highest value plus one.
    @(private)
    enum_bit_count :: proc($E: typeid) -> int where intrinsics.type_is_enum(E) {
        n := 0
        for v in E do n = max(n, int(v) + 1)
        return n
    }
