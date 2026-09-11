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
        override:    ecs.Compact_Table(T), // per-object overrides, runtime; only when overridable
        overridable: bool,
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

    // overridable allows per-object overrides (T must be plain data); overrides_cap defaults to min(max_objects, 4096).
    property__init :: proc(w: ^World, self: ^Property($T), name: string, set := CORE, overridable := false, overrides_cap := 0, decode: Decode_Proc = nil) -> Error {
        when VALIDATIONS do assert(world__is_valid(w) && self != nil)

        if !world__set_is_loaded(w, set) do return DOS_Error.Config_Set_Not_Found
        if world__binding_exists(w, name) do return DOS_Error.Name_Already_Exists
        if overridable && !type_is_pod(type_info_of(T)) do return DOS_Error.Type_Not_POD // overrides are saved with the game

        db := &w.sets[set].db
        ecs_err(ecs.table_init(&self.authored, db, w.cfg.max_archetypes)) or_return
        ecs_err(ecs.table_init(&self.baked, db, w.cfg.max_archetypes)) or_return

        self.overridable = overridable
        if overridable {
            ocap := overrides_cap > 0 ? overrides_cap : 4096
            ecs_err(ecs.compact_table_init(&self.override, &w.runtime_db, min(ocap, w.cfg.max_objects))) or_return
        }

        self.world = w
        self.set = set

        bake :: proc(w: ^World, data: rawptr) -> Error {
            return property__bake(w, cast(^Property(T))data)
        }
        world__add_baker(w, bake, self, set) or_return

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
        world__add_binding(w, name, .Property, set, type_info_of(T), self, apply, decode, read) or_return
        world__find_binding(w, name).overridable = overridable
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
        if self.overridable {
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
        if self.overridable {
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

    // The object's own override; nil when none or when the property is not overridable.
    property__local :: proc(self: ^Property($T), obj: object_id) -> ^T {
        if !self.overridable do return nil
        return ecs.get_component(&self.override, ecs.entity_id(obj))
    }

    // Not_Overridable unless the property was declared with overridable = true.
    property__override :: proc(self: ^Property($T), obj: object_id, value: T) -> Error {
        if !self.overridable do return DOS_Error.Not_Overridable
        c, err := ecs.add_component(&self.override, ecs.entity_id(obj))
        if c == nil do return ecs_err(err)
        c^ = value
        return nil
    }

    property__clear_override :: proc(self: ^Property($T), obj: object_id) -> Error {
        if !self.overridable do return DOS_Error.Not_Overridable
        return ecs_err(ecs.remove_component(&self.override, ecs.entity_id(obj)))
    }

///////////////////////////////////////////////////////////////////////////////
// Private

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
