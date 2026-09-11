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
        world:      ^World,
        set:        config_set_id,
        authored:   ecs.Table(T),             // authored on archetypes, metas and surfaces
        baked:      ecs.Table(T),             // effective value per archetype and surface
        baked_from: ecs.Table(ecs.entity_id), // where each baked value came from
        override:   ecs.Compact_Table(T),     // per-object overrides, runtime
        can_override: bool,                   // T is plain data, so overrides can be saved
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

    // overrides_cap (objects with an override) defaults to min(max_objects, 4096).
    property__init :: proc(w: ^World, self: ^Property($T), name: string, set := CORE, overrides_cap := 0, decode: Decode_Proc = nil) -> Error {
        when VALIDATIONS do assert(world__is_valid(w) && self != nil)

        if !world__set_is_loaded(w, set) do return DOS_Error.Config_Set_Not_Found
        if world__binding_exists(w, name) do return DOS_Error.Name_Already_Exists

        db := &w.sets[set].db
        cap := w.cfg.max_archetypes
        ecs_err(ecs.table_init(&self.authored, db, cap)) or_return
        ecs_err(ecs.table_init(&self.baked, db, cap)) or_return
        ecs_err(ecs.table_init(&self.baked_from, db, cap)) or_return

        // overrides live in the saved runtime database, so only plain data can have them
        self.can_override = type_is_pod(type_info_of(T))
        if self.can_override {
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
        world__find_binding(w, name).overridable = self.can_override
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
        return ecs.get_component(&self.baked, ecs.entity_id(a^))
    }

    property__resolve_archetype :: proc(self: ^Property($T), holder: archetype_id) -> ^T {
        return ecs.get_component(&self.baked, ecs.entity_id(holder))
    }

    property__resolve_surface :: proc(self: ^Property($T), holder: surface_id) -> ^T {
        return ecs.get_component(&self.baked, ecs.entity_id(holder))
    }

    property__resolve_with_source :: proc(self: ^Property($T), obj: object_id) -> (^T, Value_Source) {
        eid := ecs.entity_id(obj)
        if self.can_override {
            if o := ecs.get_component(&self.override, eid); o != nil do return o, Value_Source{ kind = .Override, id = eid }
        }

        a := ecs.get_component(&self.world.archetype_table, eid)
        if a == nil do return nil, {}

        holder := ecs.entity_id(a^)
        v := ecs.get_component(&self.baked, holder)
        if v == nil do return nil, {}

        from := ecs.get_component(&self.baked_from, holder)^
        kind := self.world.config_kind[from.ix] == .Meta ? Source_Kind.Meta : Source_Kind.Authored
        return v, Value_Source{ kind = kind, id = from }
    }

///////////////////////////////////////////////////////////////////////////////
// Overrides

    // The object's own override; nil when none.
    property__local :: proc(self: ^Property($T), obj: object_id) -> ^T {
        if !self.can_override do return nil
        return ecs.get_component(&self.override, ecs.entity_id(obj))
    }

    // Type_Not_POD when T holds strings or pointers.
    property__override :: proc(self: ^Property($T), obj: object_id, value: T) -> Error {
        if !self.can_override do return DOS_Error.Type_Not_POD
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

    @(private)
    property__author :: proc(self: ^Property($T), holder: ecs.entity_id, kind: Config_Kind, value: T) -> Error {
        if !world__config_is(self.world, holder, kind) do return DOS_Error.Wrong_Kind

        c, err := ecs.add_component(&self.authored, holder)
        if c == nil do return ecs_err(err)
        c^ = value
        return nil
    }

    @(private)
    property__bake :: proc(w: ^World, self: ^Property($T)) -> Error {
        ecs.clear(&self.baked)
        ecs.clear(&self.baked_from)

        for kind, ix in w.config_kind {
            if kind != .Archetype && kind != .Surface do continue

            holder := w.config_eid[ix]
            it := source_iter(w, holder, kind)
            for src in source_iter__next(&it) {
                v := ecs.get_component(&self.authored, src)
                if v == nil do continue

                b, berr := ecs.add_component(&self.baked, holder)
                if b == nil do return ecs_err(berr)
                b^ = v^

                f, ferr := ecs.add_component(&self.baked_from, holder)
                if f == nil do return ecs_err(ferr)
                f^ = src
                break
            }
        }
        return nil
    }
