/*
    2026 (c) Oleh, https://github.com/zm69

    Effects: named changes a designer can put on an archetype or an object (KnockedOut, Burning).
    ODE_DOS keeps the names, their bits and what authored them; what an effect does is the game's,
    which copies the bits into its own ecs.Flags_Table with bits_of.
*/
package ode_dos

// ODE
    import ecs "../../ode_ecs/src"

///////////////////////////////////////////////////////////////////////////////
// Effects

    Effects :: struct {
        config: ^Config,
        group:  ^Flag_Group,
        first:  int, // its bits are first + effect index
        cap:    int,
        used:   int,
    }

    // Reserves cap bits; every effect registered later takes the next one.
    effects__init :: proc(cfg: ^Config, self: ^Effects, cap := DEFAULT_EFFECTS_CAP) -> Error {
        when VALIDATIONS do assert(config__is_valid(cfg) && self != nil)

        n := cap > 0 ? cap : DEFAULT_EFFECTS_CAP
        group, first := config__reserve_bits(cfg, n) or_return
        self.config = cfg
        self.group = group
        self.first = first
        self.cap = n
        return nil
    }

    // The bit the game should use for this effect in its own Flags_Table.
    effects__register :: proc(self: ^Effects, name: string) -> (bit: int, err: Error) {
        when VALIDATIONS do assert(self != nil && self.group != nil)

        if config__binding_exists(self.config, name) do return 0, DOS_Error.Name_Already_Exists
        if self.used >= self.cap do return 0, DOS_Error.Out_Of_Flags

        slot := new(Effect_Bit, self.config.allocator) or_return
        slot.effects = self
        slot.bit = self.used

        if _, aerr := append(&self.config.effect_slots, slot); aerr != nil {
            free(slot, self.config.allocator)
            return 0, aerr
        }
        config__add_binding(self.config, name, .Effect, nil, slot, slot.bit, effects__apply, nil, effects__read) or_return

        self.used += 1
        return slot.bit, nil
    }

    effects__bit :: proc(self: ^Effects, name: string) -> (int, bool) {
        b := config__find_binding(self.config, name)
        if b == nil || b.kind != .Effect do return 0, false

        slot := cast(^Effect_Bit)b.data
        if slot.effects != self do return 0, false
        return slot.bit, true
    }

    effects__name :: proc(self: ^Effects, bit: int) -> string {
        for c := self.config; c != nil; c = c.base {
            for b in c.bindings {
                if b.kind != .Effect do continue
                slot := cast(^Effect_Bit)b.data
                if slot.effects == self && slot.bit == bit do return b.name
            }
        }
        return ""
    }

    effects__count :: proc(self: ^Effects) -> int {
        return self.used
    }

///////////////////////////////////////////////////////////////////////////////
// Authoring

    effects__set_archetype :: proc(self: ^Effects, holder: archetype_id, name: string, value := true) -> Error {
        return effects__set(self, ecs.entity_id(holder), .Archetype, name, value)
    }

    effects__set_meta :: proc(self: ^Effects, holder: meta_id, name: string, value := true) -> Error {
        return effects__set(self, ecs.entity_id(holder), .Meta, name, value)
    }

    effects__set_surface :: proc(self: ^Effects, holder: surface_id, name: string, value := true) -> Error {
        return effects__set(self, ecs.entity_id(holder), .Surface, name, value)
    }

    effects__set_object :: proc(self: ^Effects, holder: object_id, name: string, value := true) -> Error {
        return effects__set(self, ecs.entity_id(holder), .Object, name, value)
    }

///////////////////////////////////////////////////////////////////////////////
// Reading

    effects__has :: proc(self: ^Effects, obj: object_id, name: string) -> bool {
        bit, ok := effects__bit(self, name)
        if !ok do return false
        return (self.first + bit) in flag_group__bits_of(self.group, ecs.entity_id(obj))
    }

    // The authored effects, indexed by registration order, for your own Flags_Table.
    effects__bits_of :: proc(self: ^Effects, obj: object_id) -> (res: ecs.Bits) {
        bits := flag_group__bits_of(self.group, ecs.entity_id(obj))
        for i in 0..<self.used {
            if (self.first + i) in bits do res += {i}
        }
        return
    }

///////////////////////////////////////////////////////////////////////////////
// Private

    @(private)
    effects__set :: proc(self: ^Effects, holder: ecs.entity_id, kind: Config_Kind, name: string, value: bool) -> Error {
        if !config__config_is(self.config, holder, kind) do return DOS_Error.Wrong_Kind

        bit, ok := effects__bit(self, name)
        if !ok do return DOS_Error.Name_Not_Found
        return flag_group__author(self.group, holder, self.first + bit, value)
    }

    // One binding per effect name, each pointing at its own bit.
    @(private)
    Effect_Bit :: struct {
        effects: ^Effects,
        bit:     int,
    }

    @(private)
    effects__apply :: proc(data: rawptr, op: Binding_Op, a: ecs.entity_id, b: ecs.entity_id, value: rawptr) -> Error {
        slot := cast(^Effect_Bit)data
        fx := slot.effects
        #partial switch op {
        case .Author:   return flag_group__author(fx.group, a, fx.first + slot.bit, (cast(^bool)value)^)
        case .Unauthor: flag_group__unauthor(fx.group, a, fx.first + slot.bit)
        }
        return nil
    }

    @(private)
    effects__read :: proc(data: rawptr, holder: ecs.entity_id, index: int) -> (value: rawptr, other: ecs.entity_id, source: Value_Source, ok: bool) {
        slot := cast(^Effect_Bit)data
        fx := slot.effects
        return nil, {}, {}, (fx.first + slot.bit) in flag_group__bits_of(fx.group, holder)
    }
