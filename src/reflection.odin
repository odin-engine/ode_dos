/*
    2026 (c) Oleh, https://github.com/zm69

    Reflection: what a game reads back about the objects a designer authored - their names, their
    archetype, the values, flags and effects they carry, and the links between them. It describes
    designed things; the game builds its own runtime from what it finds here.
*/
package ode_dos

// ODE
    import ecs "../../ode_ecs/src"
    import oc_maps "../../ode_ecs/src/ode_core/maps"

///////////////////////////////////////////////////////////////////////////////
// Objects

    // A designed object of an archetype; an empty name leaves it unnamed.
    config__object :: proc(self: ^Config, archetype: archetype_id, name := "") -> (obj: object_id, err: Error) {
        when VALIDATIONS do assert(config__is_valid(self))

        if !config__config_is(self, ecs.entity_id(archetype), .Archetype) do return {}, DOS_Error.Wrong_Kind

        eid: ecs.entity_id
        if name == "" {
            eid = config__create_unnamed(self, .Object) or_return
        } else {
            eid = config__create(self, name, .Object) or_return
        }

        a, aerr := ecs.add_component(&self.root.archetype_table, eid)
        if a == nil {
            config__destroy(self, eid)
            return {}, ecs_err(aerr)
        }
        a^ = archetype

        return object_id(eid), nil
    }

    config__archetype_of :: proc(self: ^Config, obj: object_id) -> archetype_id {
        a := ecs.get_component(&self.root.archetype_table, ecs.entity_id(obj))
        return a == nil ? archetype_id{} : a^
    }

    config__find_object :: proc(self: ^Config, name: string) -> (object_id, bool) {
        eid, kind, ok := config__find_named(self, name, true)
        if !ok || kind != .Object do return {}, false
        return object_id(eid), true
    }

    // "" when names are not kept or the object has none.
    config__object_name :: proc(self: ^Config, obj: object_id) -> string {
        return config__name_of(self, ecs.entity_id(obj))
    }

    config__set_object_name :: proc(self: ^Config, obj: object_id, name: string) -> Error {
        eid := ecs.entity_id(obj)

        if name == "" do return DOS_Error.Invalid_Name
        owner := config__owner(self, eid)
        if owner == nil || owner.config_kind[eid.ix] != .Object do return DOS_Error.Wrong_Kind
        if _, _, exists := config__find_named(owner, name, true); exists do return DOS_Error.Name_Already_Exists

        if old := owner.config_hash[eid.ix]; old != 0 {
            _ = oc_maps.rh_map64__remove(&owner.object_names, old)
            config__drop_name(owner, &owner.object_strings, old)
        }

        h := name_hash(name)
        oc_maps.rh_map64__add(&owner.object_names, h, u32(eid.ix)) or_return
        owner.config_hash[eid.ix] = h
        return config__keep_name(owner, &owner.object_strings, h, name)
    }

///////////////////////////////////////////////////////////////////////////////
// Queries

    // Every object this Config declares.
    config__objects :: proc(self: ^Config, allocator := context.temp_allocator) -> []object_id {
        res := make([dynamic]object_id, 0, 64, allocator)
        for kind, ix in self.config_kind {
            if kind == .Object do append(&res, object_id(self.config_eid[ix]))
        }
        return res[:]
    }

    // Objects of this archetype or anything derived from it.
    config__objects_of :: proc(self: ^Config, archetype: archetype_id, allocator := context.temp_allocator) -> []object_id {
        res := make([dynamic]object_id, 0, 64, allocator)
        for kind, ix in self.config_kind {
            if kind != .Object do continue

            obj := object_id(self.config_eid[ix])
            if config__is_kind_of(self, config__archetype_of(self, obj), archetype) do append(&res, obj)
        }
        return res[:]
    }

    // What the last load touched; valid until the next one.
    config__changed_objects :: proc(self: ^Config, allocator := context.temp_allocator) -> []object_id {
        res := make([dynamic]object_id, 0, 32, allocator)
        for eid in self.changed {
            if config__kind_of(self, eid) == .Object do append(&res, object_id(eid))
        }
        return res[:]
    }

    config__changed_archetypes :: proc(self: ^Config, allocator := context.temp_allocator) -> []archetype_id {
        res := make([dynamic]archetype_id, 0, 32, allocator)
        for eid in self.changed {
            if config__kind_of(self, eid) == .Archetype do append(&res, archetype_id(eid))
        }
        return res[:]
    }
