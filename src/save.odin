/*
    2026 (c) Oleh, https://github.com/zm69

    Save and load: only runtime state is saved (objects, state, flags, overrides, links and
    effects); configuration comes back from KDL.
*/
package ode_dos

// ODE
    import ecs "../../ode_ecs/src"
    import oc_maps "../../ode_ecs/src/ode_core/maps"

///////////////////////////////////////////////////////////////////////////////
// Save and load

    world__save_game :: proc(self: ^World, path: string) -> Error {
        when VALIDATIONS do assert(world__is_valid(self))
        return ecs_err(ecs.save_to_file(&self.runtime_db, path, self.allocator))
    }

    // Replaces runtime state with a snapshot from a World set up the same way: same
    // declarations in the same order and the same configuration.
    world__load_game :: proc(self: ^World, path: string) -> Error {
        when VALIDATIONS do assert(world__is_valid(self))
        ecs_err(ecs.load_from_file(&self.runtime_db, path, self.allocator)) or_return
        return world__rebuild_object_names(self)
    }

///////////////////////////////////////////////////////////////////////////////
// Private

    @(private)
    world__rebuild_object_names :: proc(self: ^World) -> Error {
        oc_maps.rh_map64__clear(&self.object_names)

        hashes := ecs.slice(&self.object_name_table)
        for eid, i in ecs.entities_slice(&self.object_name_table) {
            if ecs.is_not_set(eid) do continue
            oc_maps.rh_map64__add(&self.object_names, hashes[i], u32(eid.ix)) or_return
        }
        return nil
    }
