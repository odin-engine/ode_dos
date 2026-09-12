/*
    2026 (c) Oleh, https://github.com/zm69

    Property(T): a value authored on archetypes, metas and surfaces, flattened by bake,
    with optional per-object overrides in the runtime database.
*/
package ode_dos

// ODE
    import ecs "../../ode_ecs/src"

///////////////////////////////////////////////////////////////////////////////
// Property

    Property :: struct($T: typeid) {
        world:       ^World,
        set:         config_set_id,
        authored:    ecs.Table(T),         // authored on archetypes, metas and surfaces
        baked:       ecs.Table(Baked(T)),  // effective value per archetype and surface, with its source
        override:    ecs.Compact_Table(T), // per-object overrides, runtime; grown on first override
        can_override: bool,                // T is plain data, so it can be saved with the game
        overrides_cap: int,
    }

    @(private)
    Baked :: struct($T: typeid) {
        value: T,
        from:  ecs.entity_id, // the archetype, surface or meta the value came from
    }

    Source_Kind :: enum u8 {
        None,
        Override,
        Authored, // on the archetype or surface itself, or an ancestor
        Meta,
    }

    // Where a resolved value came from.
    Value_Source :: struct {
        kind: Source_Kind,
        id:   ecs.entity_id, // the object for Override, else the archetype, surface or meta
    }

    // Objects can override a property of plain data; its table holds one row until the first
    // override grows it to overrides_cap, which defaults to min(max_objects, 4096).
    property__init :: proc(w: ^World, self: ^Property($T), name: string, set := CORE, overrides_cap := 0, decode: Decode_Proc = nil) -> Error {
        when VALIDATIONS do assert(world__is_valid(w) && self != nil)

        if !world__set_is_loaded(w, set) do return DOS_Error.Config_Set_Not_Found
        if world__binding_exists(w, name) do return DOS_Error.Name_Already_Exists

        db := &w.sets[set].db
        ecs_err(ecs.table_init(&self.authored, db, w.config_cap)) or_return
        ecs_err(ecs.table_init(&self.baked, db, w.config_cap)) or_return

        self.can_override = type_is_pod(type_info_of(T)) // overrides are saved with the game
        if self.can_override {
            ocap := overrides_cap > 0 ? overrides_cap : 4096
            self.overrides_cap = min(ocap, w.cfg.max_objects)
            ecs_err(ecs.compact_table_init(&self.override, &w.runtime_db, 1)) or_return
        }

        self.world = w
        self.set = set

        bake :: proc(w: ^World, data: rawptr) -> Error {
            return property__bake(w, cast(^Property(T))data)
        }
        grow :: proc(data: rawptr, cap: int) -> Error {
            self := cast(^Property(T))data
            ecs_err(ecs.grow(&self.authored, cap)) or_return
            return ecs_err(ecs.grow(&self.baked, cap))
        }
        world__add_baker(w, bake, grow, self, set) or_return

        apply :: proc(data: rawptr, op: Binding_Op, a: ecs.entity_id, b: ecs.entity_id, value: rawptr) -> Error {
            self := cast(^Property(T))data
            #partial switch op {
            case .Author:   return property__author(self, a, self.world.config_kind[a.ix], (cast(^T)value)^)
            case .Unauthor: _ = ecs.remove_component(&self.authored, a)
            case .Override: return property__override(self, object_id(a), (cast(^T)value)^)
            }
            return nil
        }
        read :: proc(data: rawptr, obj: ecs.entity_id, index: int) -> (value: rawptr, other: ecs.entity_id, source: Value_Source, ok: bool) {
            v, src := property__resolve_with_source(cast(^Property(T))data, object_id(obj))
            return v, {}, src, v != nil
        }
        reserve :: proc(data: rawptr) -> Error {
            self := cast(^Property(T))data
            if !self.can_override do return nil
            return ecs_err(ecs.grow(&self.override, self.overrides_cap))
        }
        world__add_binding(w, name, .Property, set, type_info_of(T), self, apply, decode, read, reserve) or_return
        world__find_binding(w, name).can_override = self.can_override
        return nil
    }

///////////////////////////////////////////////////////////////////////////////
// Authoring

    property__set_archetype :: proc(self: ^Property($T), holder: archetype_id, value: T) -> Error {
        return property__author(self, ecs.entity_id(holder), .Archetype, value)
    }

    property__set_meta :: proc(self: ^Property($T), holder: meta_id, value: T) -> Error {
        return property__author(self, ecs.entity_id(holder), .Meta, value)
    }

    property__set_surface :: proc(self: ^Property($T), holder: surface_id, value: T) -> Error {
        return property__author(self, ecs.entity_id(holder), .Surface, value)
    }

    // The value authored on holder itself, not inherited; nil when none.
    property__get_archetype :: proc(self: ^Property($T), holder: archetype_id) -> ^T { return ecs.get_component(&self.authored, ecs.entity_id(holder)) }
    property__get_meta      :: proc(self: ^Property($T), holder: meta_id) -> ^T      { return ecs.get_component(&self.authored, ecs.entity_id(holder)) }
    property__get_surface   :: proc(self: ^Property($T), holder: surface_id) -> ^T   { return ecs.get_component(&self.authored, ecs.entity_id(holder)) }

    property__unset_archetype :: proc(self: ^Property($T), holder: archetype_id) -> Error { return ecs_err(ecs.remove_component(&self.authored, ecs.entity_id(holder))) }
    property__unset_meta      :: proc(self: ^Property($T), holder: meta_id) -> Error      { return ecs_err(ecs.remove_component(&self.authored, ecs.entity_id(holder))) }
    property__unset_surface   :: proc(self: ^Property($T), holder: surface_id) -> Error   { return ecs_err(ecs.remove_component(&self.authored, ecs.entity_id(holder))) }

///////////////////////////////////////////////////////////////////////////////
// Resolving

    // The override, else the baked archetype value; nil before bake or when nothing is authored.
    property__resolve_object :: proc(self: ^Property($T), obj: object_id) -> ^T {
        eid := ecs.entity_id(obj)
        if self.can_override {
            if o := ecs.get_component(&self.override, eid); o != nil do return o
        }

        a := ecs.get_component(&self.world.archetype_table, eid)
        if a == nil do return nil
        return property__baked_value(self, ecs.entity_id(a^))
    }

    property__resolve_archetype :: proc(self: ^Property($T), holder: archetype_id) -> ^T {
        return property__baked_value(self, ecs.entity_id(holder))
    }

    property__resolve_surface :: proc(self: ^Property($T), holder: surface_id) -> ^T {
        return property__baked_value(self, ecs.entity_id(holder))
    }

    property__resolve_with_source :: proc(self: ^Property($T), obj: object_id) -> (^T, Value_Source) {
        eid := ecs.entity_id(obj)
        if self.can_override {
            if o := ecs.get_component(&self.override, eid); o != nil do return o, Value_Source{ kind = .Override, id = eid }
        }

        a := ecs.get_component(&self.world.archetype_table, eid)
        if a == nil do return nil, {}

        row := ecs.get_component(&self.baked, ecs.entity_id(a^))
        if row == nil do return nil, {}

        kind := self.world.config_kind[row.from.ix] == .Meta ? Source_Kind.Meta : Source_Kind.Authored
        return &row.value, Value_Source{ kind = kind, id = row.from }
    }

///////////////////////////////////////////////////////////////////////////////
// Overrides

    // The object's own override; nil when it has none, or when T is not plain data.
    property__local :: proc(self: ^Property($T), obj: object_id) -> ^T {
        if !self.can_override do return nil
        return ecs.get_component(&self.override, ecs.entity_id(obj))
    }

    // Type_Not_POD when T is not plain data, since overrides are saved with the game.
    property__override :: proc(self: ^Property($T), obj: object_id, value: T) -> Error {
        if !self.can_override do return DOS_Error.Type_Not_POD
        if self.override.cap < self.overrides_cap do ecs_err(ecs.grow(&self.override, self.overrides_cap)) or_return

        c, err := ecs.add_component(&self.override, ecs.entity_id(obj))
        if c == nil do return ecs_err(err)
        c^ = value
        return nil
    }

    property__clear_override :: proc(self: ^Property($T), obj: object_id) -> Error {
        if !self.can_override do return DOS_Error.Type_Not_POD
        return ecs_err(ecs.remove_component(&self.override, ecs.entity_id(obj)))
    }

///////////////////////////////////////////////////////////////////////////////
// Private

    // Full override capacity everywhere, so any snapshot fits.
    @(private)
    world__reserve_overrides :: proc(self: ^World) -> Error {
        for &b in self.bindings {
            if b.reserve != nil do b.reserve(b.data) or_return
        }
        return nil
    }

    @(private)
    property__author :: proc(self: ^Property($T), holder: ecs.entity_id, kind: Config_Kind, value: T) -> Error {
        if !world__config_is(self.world, holder, kind) do return DOS_Error.Wrong_Kind

        c, err := ecs.add_component(&self.authored, holder)
        if c == nil do return ecs_err(err)
        c^ = value
        return nil
    }

    @(private)
    property__baked_value :: #force_inline proc(self: ^Property($T), holder: ecs.entity_id) -> ^T {
        row := ecs.get_component(&self.baked, holder)
        return row != nil ? &row.value : nil
    }

    @(private)
    property__bake :: proc(w: ^World, self: ^Property($T)) -> Error {
        ecs.clear(&self.baked)

        for kind, ix in w.config_kind {
            if kind != .Archetype && kind != .Surface do continue

            holder := w.config_eid[ix]
            it := source_iter(w, holder, kind)
            for src in source_iter__next(&it) {
                v := ecs.get_component(&self.authored, src)
                if v == nil do continue

                row, err := ecs.add_component(&self.baked, holder)
                if row == nil do return ecs_err(err)
                row^ = Baked(T){ value = v^, from = src }
                break
            }
        }
        return nil
    }
