/*
    2026 (c) Oleh, https://github.com/zm69

    Objects: runtime instances of archetypes, with optional names and spawn hooks.
*/
package ode_dos

// ODE
    import ecs "../../ode_ecs/src"
    import oc "../../ode_ecs/src/ode_core"
    import oc_maps "../../ode_ecs/src/ode_core/maps"

///////////////////////////////////////////////////////////////////////////////
// Spawning

    // Runs after every spawn; reaches your tables through user_data.
    Spawn_Hook :: proc(w: ^World, obj: object_id)

    world__on_spawn :: proc(self: ^World, hook: Spawn_Hook) -> Error {
        when VALIDATIONS do assert(world__is_valid(self) && hook != nil)

        if self.spawn_hooks_len >= MAX_SPAWN_HOOKS do return oc.Core_Error.Container_Is_Full
        self.spawn_hooks[self.spawn_hooks_len] = hook
        self.spawn_hooks_len += 1
        return nil
    }

    world__spawn_by_id :: proc(self: ^World, archetype: archetype_id) -> (obj: object_id, err: Error) {
        obj = world__create_object(self, archetype) or_return
        world__run_spawn_hooks(self, obj)
        return obj, nil
    }

    // An object without running spawn hooks.
    @(private)
    world__create_object :: proc(self: ^World, archetype: archetype_id) -> (obj: object_id, err: Error) {
        when VALIDATIONS do assert(world__is_valid(self))

        if !world__config_is(self, ecs.entity_id(archetype), .Archetype) do return {}, DOS_Error.Wrong_Kind

        eid, cerr := ecs.create_entity(&self.runtime_db)
        if cerr != nil do return {}, ecs_err(cerr)

        a, aerr := ecs.add_component(&self.archetype_table, eid)
        if aerr != nil {
            _ = ecs.destroy_entity(&self.runtime_db, eid)
            return {}, ecs_err(aerr)
        }
        a^ = archetype

        return object_id(eid), nil
    }

    @(private)
    world__run_spawn_hooks :: proc(self: ^World, obj: object_id) {
        for hook in self.spawn_hooks[:self.spawn_hooks_len] do hook(self, obj)
    }

    world__spawn_by_name :: proc(self: ^World, archetype: string) -> (obj: object_id, err: Error) {
        a, ok := world__find_archetype(self, archetype)
        if !ok do return {}, DOS_Error.Name_Not_Found
        return world__spawn_by_id(self, a)
    }

    // Removes the object with every component, flag and link it has.
    world__destroy :: proc(self: ^World, obj: object_id) -> Error {
        when VALIDATIONS do assert(world__is_valid(self))

        eid := ecs.entity_id(obj)
        if ecs.is_expired(&self.runtime_db, eid) do return ecs.API_Error.Entity_Id_Expired

        world__unname_object(self, eid)
        return ecs_err(ecs.destroy_entity(&self.runtime_db, eid))
    }

    world__alive :: proc(self: ^World, obj: object_id) -> bool {
        return !ecs.is_expired(&self.runtime_db, ecs.entity_id(obj))
    }

    world__archetype_of :: proc(self: ^World, obj: object_id) -> archetype_id {
        a := ecs.get_component(&self.archetype_table, ecs.entity_id(obj))
        if a == nil do return {}
        return a^
    }

///////////////////////////////////////////////////////////////////////////////
// Names

    world__set_object_name :: proc(self: ^World, obj: object_id, name: string) -> Error {
        when VALIDATIONS do assert(world__is_valid(self))

        eid := ecs.entity_id(obj)
        if name == "" do return DOS_Error.Invalid_Name
        if ecs.is_expired(&self.runtime_db, eid) do return ecs.API_Error.Entity_Id_Expired

        h := name_hash(name)
        if oc_maps.rh_map64__get(&self.object_names, h) != oc_maps.RH_MAP64_NOT_FOUND do return DOS_Error.Name_Already_Exists

        world__unname_object(self, eid)
        oc_maps.rh_map64__add(&self.object_names, h, u32(eid.ix)) or_return

        slot, aerr := ecs.add_component(&self.object_name_table, eid)
        if slot == nil {
            _ = oc_maps.rh_map64__remove(&self.object_names, h)
            return ecs_err(aerr)
        }
        slot^ = h

        return world__keep_name(self, &self.object_strings, h, name)
    }

    world__find :: proc(self: ^World, name: string) -> (object_id, bool) {
        h := name_hash(name)
        ix := oc_maps.rh_map64__get(&self.object_names, h)
        if ix == oc_maps.RH_MAP64_NOT_FOUND do return {}, false

        eid := self.runtime_db.overbase.id_factory.items[ix]
        stored := ecs.get_component(&self.object_name_table, eid)
        if stored == nil || stored^ != h do return {}, false

        return object_id(eid), true
    }

    // "" when names are not kept or the object has none.
    world__object_name :: proc(self: ^World, obj: object_id) -> string {
        if !self.keep_names do return ""
        h := ecs.get_component(&self.object_name_table, ecs.entity_id(obj))
        if h == nil do return ""
        return self.object_strings[h^]
    }

    @(private)
    world__unname_object :: proc(self: ^World, eid: ecs.entity_id) {
        h := ecs.get_component(&self.object_name_table, eid)
        if h == nil do return

        hash := h^
        _ = oc_maps.rh_map64__remove(&self.object_names, hash) // the string stays, so the name comes back with a loaded game
        _ = ecs.remove_component(&self.object_name_table, eid)
    }
