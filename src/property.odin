/*
    2026 (c) Oleh, https://github.com/zm69

    Property(T): a value authored on archetypes, metas, surfaces and objects, flattened by bake.
    A value authored on an object is an override: it wins over everything its archetype says.
*/
package ode_dos

// ODE
    import ecs "../../ode_ecs/src"

///////////////////////////////////////////////////////////////////////////////
// Property

    Property :: struct($T: typeid) {
        config:   ^Config,
        authored: ecs.Table(T),        // on archetypes, metas, surfaces and objects
        baked:    ecs.Table(Baked(T)), // effective value per archetype and surface, with its source
    }

    @(private)
    Baked :: struct($T: typeid) {
        value: T,
        from:  ecs.entity_id, // the archetype, surface or meta the value came from
    }

    Source_Kind :: enum u8 {
        None,
        Override, // authored on the object itself
        Authored, // on the archetype or surface itself, or an ancestor
        Meta,
    }

    // Where a resolved value came from.
    Value_Source :: struct {
        kind: Source_Kind,
        id:   ecs.entity_id, // the object for Override, else the archetype, surface or meta
    }

    property__init :: proc(cfg: ^Config, self: ^Property($T), name: string, decode: Decode_Proc = nil) -> Error {
        when VALIDATIONS do assert(config__is_valid(cfg) && self != nil)

        if config__binding_exists(cfg, name) do return DOS_Error.Name_Already_Exists

        ecs_err(ecs.table_init(&self.authored, &cfg.db, cfg.config_cap)) or_return
        ecs_err(ecs.table_init(&self.baked, &cfg.db, cfg.config_cap)) or_return
        self.config = cfg

        bake :: proc(cfg: ^Config, data: rawptr) -> Error {
            return property__bake(cast(^Property(T))data)
        }
        grow :: proc(data: rawptr, cap: int) -> Error {
            self := cast(^Property(T))data
            ecs_err(ecs.grow(&self.authored, cap)) or_return
            return ecs_err(ecs.grow(&self.baked, cap))
        }
        config__add_storage(cfg, bake, grow, self) or_return

        apply :: proc(data: rawptr, op: Binding_Op, a: ecs.entity_id, b: ecs.entity_id, value: rawptr) -> Error {
            self := cast(^Property(T))data
            #partial switch op {
            case .Author:   return property__author(self, a, (cast(^T)value)^)
            case .Unauthor: _ = ecs.remove_component(&self.authored, a)
            }
            return nil
        }
        read :: proc(data: rawptr, holder: ecs.entity_id, index: int) -> (value: rawptr, other: ecs.entity_id, source: Value_Source, ok: bool) {
            v, src := property__resolve_any(cast(^Property(T))data, holder)
            return v, {}, src, v != nil
        }
        return config__add_binding(cfg, name, .Property, type_info_of(T), self, 0, apply, decode, read)
    }

///////////////////////////////////////////////////////////////////////////////
// Authoring

    property__set_archetype :: proc(self: ^Property($T), holder: archetype_id, value: T) -> Error {
        return property__author_kind(self, ecs.entity_id(holder), .Archetype, value)
    }

    property__set_meta :: proc(self: ^Property($T), holder: meta_id, value: T) -> Error {
        return property__author_kind(self, ecs.entity_id(holder), .Meta, value)
    }

    property__set_surface :: proc(self: ^Property($T), holder: surface_id, value: T) -> Error {
        return property__author_kind(self, ecs.entity_id(holder), .Surface, value)
    }

    // An object's own value; it wins over everything its archetype says.
    property__set_object :: proc(self: ^Property($T), holder: object_id, value: T) -> Error {
        return property__author_kind(self, ecs.entity_id(holder), .Object, value)
    }

    // The value authored on holder itself, not inherited; nil when none.
    property__get_archetype :: proc(self: ^Property($T), holder: archetype_id) -> ^T { return ecs.get_component(&self.authored, ecs.entity_id(holder)) }
    property__get_meta      :: proc(self: ^Property($T), holder: meta_id) -> ^T      { return ecs.get_component(&self.authored, ecs.entity_id(holder)) }
    property__get_surface   :: proc(self: ^Property($T), holder: surface_id) -> ^T   { return ecs.get_component(&self.authored, ecs.entity_id(holder)) }
    property__get_object    :: proc(self: ^Property($T), holder: object_id) -> ^T    { return ecs.get_component(&self.authored, ecs.entity_id(holder)) }

    property__unset_archetype :: proc(self: ^Property($T), holder: archetype_id) -> Error { return ecs_err(ecs.remove_component(&self.authored, ecs.entity_id(holder))) }
    property__unset_meta      :: proc(self: ^Property($T), holder: meta_id) -> Error      { return ecs_err(ecs.remove_component(&self.authored, ecs.entity_id(holder))) }
    property__unset_surface   :: proc(self: ^Property($T), holder: surface_id) -> Error   { return ecs_err(ecs.remove_component(&self.authored, ecs.entity_id(holder))) }
    property__unset_object    :: proc(self: ^Property($T), holder: object_id) -> Error    { return ecs_err(ecs.remove_component(&self.authored, ecs.entity_id(holder))) }

///////////////////////////////////////////////////////////////////////////////
// Resolving

    // What the object authored, else its archetype's baked value; nil when nothing does.
    property__resolve_object :: proc(self: ^Property($T), obj: object_id) -> ^T {
        eid := ecs.entity_id(obj)
        if o := ecs.get_component(&self.authored, eid); o != nil do return o

        a := ecs.get_component(&self.config.root.archetype_table, eid)
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
        return property__resolve_any(self, ecs.entity_id(obj))
    }

///////////////////////////////////////////////////////////////////////////////
// Private

    // Works for an object (override, then its archetype) and for an archetype or surface.
    @(private)
    property__resolve_any :: proc(self: ^Property($T), holder: ecs.entity_id) -> (^T, Value_Source) {
        if o := ecs.get_component(&self.authored, holder); o != nil {
            if config__kind_of(self.config, holder) == .Object do return o, Value_Source{ kind = .Override, id = holder }
        }

        eid := holder
        if a := ecs.get_component(&self.config.root.archetype_table, holder); a != nil {
            eid = ecs.entity_id(a^)
        }

        row := ecs.get_component(&self.baked, eid)
        if row == nil do return nil, {}

        kind := config__kind_of(self.config, row.from) == .Meta ? Source_Kind.Meta : Source_Kind.Authored
        return &row.value, Value_Source{ kind = kind, id = row.from }
    }

    @(private)
    property__author_kind :: proc(self: ^Property($T), holder: ecs.entity_id, kind: Config_Kind, value: T) -> Error {
        if !config__config_is(self.config, holder, kind) do return DOS_Error.Wrong_Kind
        return property__author(self, holder, value)
    }

    @(private)
    property__author :: proc(self: ^Property($T), holder: ecs.entity_id, value: T) -> Error {
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
    property__bake :: proc(self: ^Property($T)) -> Error {
        ecs.clear(&self.baked)

        for cfg in self.config.root.chain {
            for kind, ix in cfg.config_kind {
                if kind != .Archetype && kind != .Surface do continue

                holder := cfg.config_eid[ix]
                it := source_iter(cfg, holder, kind)
                for src in source_iter__next(&it) {
                    v := ecs.get_component(&self.authored, src)
                    if v == nil do continue

                    row, err := ecs.add_component(&self.baked, holder)
                    if row == nil do return ecs_err(err)
                    row^ = Baked(T){ value = v^, from = src }
                    break
                }
            }
        }
        return nil
    }
