/*
    2026 (c) Oleh, https://github.com/zm69

    Flags: booleans authored like Property values and baked into one ecs.Flags_Table bit each, up
    to FLAGS_PER_GROUP bits per group. A single Flag takes one bit; State_Flags(E) and Effects take
    a range of them, so a game can copy a whole range into its own Flags_Table in one call.
*/
package ode_dos

// ODE
    import ecs "../../ode_ecs/src"

///////////////////////////////////////////////////////////////////////////////
// Flag

    Flag :: struct {
        config: ^Config,
        group:  ^Flag_Group,
        bit:    int,
    }

    @(private)
    Flag_Authored :: struct {
        mask:  ecs.Bits, // bits authored on this holder
        value: ecs.Bits, // their values
    }

    @(private)
    Flag_Group :: struct {
        config:   ^Config,
        authored: ecs.Table(Flag_Authored),
        baked:    ecs.Flags_Table,
        used:     int,
    }

    flag__init :: proc(cfg: ^Config, self: ^Flag, name: string) -> Error {
        when VALIDATIONS do assert(config__is_valid(cfg) && self != nil)

        if config__binding_exists(cfg, name) do return DOS_Error.Name_Already_Exists

        group, first := config__reserve_bits(cfg, 1) or_return
        self.config = cfg
        self.group = group
        self.bit = first

        apply :: proc(data: rawptr, op: Binding_Op, a: ecs.entity_id, b: ecs.entity_id, value: rawptr) -> Error {
            self := cast(^Flag)data
            #partial switch op {
            case .Author:   return flag_group__author(self.group, a, self.bit, (cast(^bool)value)^)
            case .Unauthor: flag_group__unauthor(self.group, a, self.bit)
            }
            return nil
        }
        read :: proc(data: rawptr, holder: ecs.entity_id, index: int) -> (value: rawptr, other: ecs.entity_id, source: Value_Source, ok: bool) {
            self := cast(^Flag)data
            return nil, {}, {}, self.bit in flag_group__bits_of(self.group, holder)
        }
        return config__add_binding(cfg, name, .Flag, nil, self, 0, apply, nil, read)
    }

///////////////////////////////////////////////////////////////////////////////
// Authoring

    flag__set_archetype :: proc(self: ^Flag, holder: archetype_id, value := true) -> Error { return flag__set(self, ecs.entity_id(holder), .Archetype, value) }
    flag__set_meta      :: proc(self: ^Flag, holder: meta_id, value := true) -> Error      { return flag__set(self, ecs.entity_id(holder), .Meta, value) }
    flag__set_surface   :: proc(self: ^Flag, holder: surface_id, value := true) -> Error   { return flag__set(self, ecs.entity_id(holder), .Surface, value) }
    flag__set_object    :: proc(self: ^Flag, holder: object_id, value := true) -> Error    { return flag__set(self, ecs.entity_id(holder), .Object, value) }

///////////////////////////////////////////////////////////////////////////////
// Resolving

    flag__resolve_object :: proc(self: ^Flag, obj: object_id) -> bool {
        return self.bit in flag_group__bits_of(self.group, ecs.entity_id(obj))
    }

    flag__resolve_archetype :: proc(self: ^Flag, holder: archetype_id) -> bool {
        return self.bit in flag_group__bits_of(self.group, ecs.entity_id(holder))
    }

    flag__resolve_surface :: proc(self: ^Flag, holder: surface_id) -> bool {
        return self.bit in flag_group__bits_of(self.group, ecs.entity_id(holder))
    }

///////////////////////////////////////////////////////////////////////////////
// Private

    @(private)
    flag__set :: proc(self: ^Flag, holder: ecs.entity_id, kind: Config_Kind, value: bool) -> Error {
        if !config__config_is(self.config, holder, kind) do return DOS_Error.Wrong_Kind
        return flag_group__author(self.group, holder, self.bit, value)
    }

    // A group of this Config with count free bits, created when none has room.
    @(private)
    config__reserve_bits :: proc(self: ^Config, count: int) -> (group: ^Flag_Group, first: int, err: Error) {
        if count > FLAGS_PER_GROUP do return nil, 0, DOS_Error.Out_Of_Flags

        for g in self.flag_groups {
            if g.used + count <= FLAGS_PER_GROUP {
                first = g.used
                g.used += count
                return g, first, nil
            }
        }

        g := new(Flag_Group, self.allocator) or_return
        ecs_err(ecs.table_init(&g.authored, &self.db, self.config_cap)) or_return
        ecs_err(ecs.flags_table_init(&g.baked, &self.db, self.config_cap)) or_return
        g.config = self
        g.used = count

        _, aerr := append(&self.flag_groups, g)
        if aerr != nil do return nil, 0, aerr
        return g, 0, nil
    }

    @(private)
    flag_group__author :: proc(self: ^Flag_Group, holder: ecs.entity_id, bit: int, value: bool) -> Error {
        a := ecs.get_component(&self.authored, holder)
        if a == nil {
            c, err := ecs.add_component(&self.authored, holder)
            if c == nil do return ecs_err(err)
            a = c
        }

        a.mask += {bit}
        if value {
            a.value += {bit}
        } else {
            a.value -= {bit}
        }
        return nil
    }

    @(private)
    flag_group__unauthor :: proc(self: ^Flag_Group, holder: ecs.entity_id, bit: int) {
        if row := ecs.get_component(&self.authored, holder); row != nil {
            row.mask -= {bit}
            row.value -= {bit}
        }
    }

    // What holder ends up with: an object's own bits over its archetype's baked ones.
    @(private)
    flag_group__bits_of :: proc(self: ^Flag_Group, holder: ecs.entity_id) -> ecs.Bits {
        cfg := self.config
        base := holder
        if a := ecs.get_component(&cfg.root.archetype_table, holder); a != nil {
            base = ecs.entity_id(a^)
        }

        bits := ecs.get_flags(&self.baked, base)
        if own := ecs.get_component(&self.authored, holder); own != nil && base != holder {
            bits -= own.mask
            bits += own.value & own.mask
        }
        return bits
    }

    // Each bit takes the value of its first source in precedence order.
    @(private)
    flag_group__bake :: proc(self: ^Flag_Group) -> Error {
        ecs.clear(&self.baked)

        for cfg in self.config.root.chain {
            for kind, ix in cfg.config_kind {
                if kind != .Archetype && kind != .Surface do continue

                holder := cfg.config_eid[ix]
                decided, value: ecs.Bits
                it := source_iter(cfg, holder, kind)
                for src in source_iter__next(&it) {
                    a := ecs.get_component(&self.authored, src)
                    if a == nil do continue
                    fresh := a.mask - decided
                    value += a.value & fresh
                    decided += fresh
                }

                if value != {} do ecs_err(ecs.set_flags(&self.baked, holder, value)) or_return
            }
        }
        return nil
    }
