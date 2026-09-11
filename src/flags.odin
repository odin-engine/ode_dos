/*
    2026 (c) Oleh, https://github.com/zm69

    Config flags: booleans authored like Property values and baked into one ecs.Flags_Table bit
    per flag, up to 128 flags per group.
*/
package ode_dos

// ODE
    import ecs "../../ode_ecs/src"

///////////////////////////////////////////////////////////////////////////////
// Flag

    Flag :: struct {
        world: ^World,
        group: ^Flag_Group,
        bit:   int,
    }

    @(private)
    FLAGS_PER_GROUP :: 128

    @(private)
    Flag_Authored :: struct {
        mask:  ecs.Bits, // flags authored on this holder
        value: ecs.Bits, // their values
    }

    @(private)
    Flag_Group :: struct {
        set:      config_set_id,
        authored: ecs.Table(Flag_Authored),
        baked:    ecs.Flags_Table,
        used:     int,
    }

    flag__init :: proc(w: ^World, self: ^Flag, name: string, set := CORE) -> Error {
        when VALIDATIONS do assert(world__is_valid(w) && self != nil)

        if !world__set_is_loaded(w, set) do return DOS_Error.Config_Set_Not_Found
        if world__binding_exists(w, name) do return DOS_Error.Name_Already_Exists

        group := world__flag_group(w, set) or_return
        self.world = w
        self.group = group
        self.bit = group.used
        group.used += 1

        apply :: proc(data: rawptr, op: Binding_Op, a: ecs.entity_id, b: ecs.entity_id, value: rawptr) -> Error {
            self := cast(^Flag)data
            #partial switch op {
            case .Author:
                return flag__author(self, a, self.world.config_kind[a.ix], (cast(^bool)value)^)
            case .Unauthor:
                if row := ecs.get_component(&self.group.authored, a); row != nil {
                    row.mask -= {self.bit}
                    row.value -= {self.bit}
                }
            }
            return nil
        }
        read :: proc(data: rawptr, obj: ecs.entity_id, index: int) -> (value: rawptr, other: ecs.entity_id, source: Value_Source, ok: bool) {
            return nil, {}, {}, flag__resolve_object(cast(^Flag)data, object_id(obj))
        }
        return world__add_binding(w, name, .Flag, set, nil, self, apply, nil, read)
    }

///////////////////////////////////////////////////////////////////////////////
// Authoring

    flag__set_archetype :: proc(self: ^Flag, holder: archetype_id, value: bool) -> Error { return flag__author(self, ecs.entity_id(holder), .Archetype, value) }
    flag__set_meta      :: proc(self: ^Flag, holder: meta_id, value: bool) -> Error      { return flag__author(self, ecs.entity_id(holder), .Meta, value) }
    flag__set_surface   :: proc(self: ^Flag, holder: surface_id, value: bool) -> Error   { return flag__author(self, ecs.entity_id(holder), .Surface, value) }

///////////////////////////////////////////////////////////////////////////////
// Resolving

    flag__resolve_object :: proc(self: ^Flag, obj: object_id) -> bool {
        a := ecs.get_component(&self.world.archetype_table, ecs.entity_id(obj))
        if a == nil do return false
        return ecs.has_flag(&self.group.baked, ecs.entity_id(a^), self.bit)
    }

    flag__resolve_archetype :: proc(self: ^Flag, holder: archetype_id) -> bool {
        return ecs.has_flag(&self.group.baked, ecs.entity_id(holder), self.bit)
    }

    flag__surface_flag :: proc(w: ^World, holder: surface_id, flag: ^Flag) -> bool {
        return ecs.has_flag(&flag.group.baked, ecs.entity_id(holder), flag.bit)
    }

///////////////////////////////////////////////////////////////////////////////
// Private

    @(private)
    flag__author :: proc(self: ^Flag, holder: ecs.entity_id, kind: Config_Kind, value: bool) -> Error {
        if !world__config_is(self.world, holder, kind) do return DOS_Error.Wrong_Kind

        a := ecs.get_component(&self.group.authored, holder)
        if a == nil {
            c, err := ecs.add_component(&self.group.authored, holder)
            if c == nil do return ecs_err(err)
            a = c
        }

        a.mask += {self.bit}
        if value {
            a.value += {self.bit}
        } else {
            a.value -= {self.bit}
        }
        return nil
    }

    // A group of the set with a free bit, created when all are full.
    @(private)
    world__flag_group :: proc(self: ^World, set: config_set_id) -> (group: ^Flag_Group, err: Error) {
        for g in self.flag_groups {
            if g.set == set && g.used < FLAGS_PER_GROUP do return g, nil
        }

        g := new(Flag_Group, self.allocator) or_return
        db := &self.sets[set].db
        ecs_err(ecs.table_init(&g.authored, db, self.cfg.max_archetypes)) or_return
        ecs_err(ecs.flags_table_init(&g.baked, db, self.cfg.max_archetypes)) or_return
        g.set = set

        _, aerr := append(&self.flag_groups, g)
        if aerr != nil do return nil, aerr
        return g, nil
    }

    // Each bit takes the value of its first source in precedence order.
    @(private)
    flag_group__bake :: proc(w: ^World, g: ^Flag_Group) -> Error {
        ecs.clear(&g.baked)

        for kind, ix in w.config_kind {
            if kind != .Archetype && kind != .Surface do continue

            holder := w.config_eid[ix]
            decided, value: ecs.Bits
            it := source_iter(w, holder, kind)
            for src in source_iter__next(&it) {
                a := ecs.get_component(&g.authored, src)
                if a == nil do continue
                fresh := a.mask - decided
                value += a.value & fresh
                decided += fresh
            }

            if value != {} do ecs_err(ecs.set_flags(&g.baked, holder, value)) or_return
        }
        return nil
    }
