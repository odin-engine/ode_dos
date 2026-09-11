/*
    2026 (c) Oleh, https://github.com/zm69

    Tests for World setup and config sets.
*/
package ode_dos__tests

// Core
    import "core:testing"

// ODE
    import dos "../src"
    import ecs "../../ode_ecs/src"
    import oc "../../ode_ecs/src/ode_core"

///////////////////////////////////////////////////////////////////////////////
// World

    @(test)
    world__defaults__test :: proc(t: ^testing.T) {
        w: dos.World
        testing.expect(t, dos.world_init(&w) == nil)
        defer dos.world_terminate(&w)

        testing.expect_value(t, w.cfg.max_archetypes, dos.DEFAULT_MAX_ARCHETYPES)
        testing.expect_value(t, w.cfg.max_config_sets, dos.DEFAULT_MAX_CONFIG_SETS)
        testing.expect_value(t, w.cfg.max_objects, dos.DEFAULT_MAX_OBJECTS)
        testing.expect_value(t, w.cfg.max_links, dos.DEFAULT_MAX_LINKS)
        testing.expect_value(t, w.keep_names, ODIN_DEBUG)

        testing.expect(t, dos.runtime(&w) != nil)
        testing.expect(t, dos.config_db(&w) != nil)

        set, found := dos.find_config_set(&w, "core")
        testing.expect(t, found && set == dos.CORE)
    }

    @(test)
    world__custom_config__test :: proc(t: ^testing.T) {
        marker := 42
        w: dos.World
        testing.expect(t, dos.world_init(&w, {max_archetypes = 64, max_config_sets = 2, max_objects = 16, keep_names = false, user_data = &marker}) == nil)
        defer dos.world_terminate(&w)

        testing.expect(t, dos.user_data(&w) == &marker)
        testing.expect(t, !w.keep_names)

        // the runtime database holds exactly max_objects entities
        for _ in 0..<16 {
            _, err := ecs.create_entity(dos.runtime(&w))
            testing.expect(t, err == nil)
        }
        _, err := ecs.create_entity(dos.runtime(&w))
        testing.expect(t, err != nil)
    }

    @(test)
    world__terminate_resets__test :: proc(t: ^testing.T) {
        w: dos.World
        testing.expect(t, dos.world_init(&w, {max_archetypes = 8, max_objects = 8}) == nil)
        dos.world_terminate(&w)
        testing.expect(t, w.state == .Not_Initialized)

        // a terminated World can be initialized again
        testing.expect(t, dos.world_init(&w, {max_archetypes = 8, max_objects = 8}) == nil)
        dos.world_terminate(&w)
    }

///////////////////////////////////////////////////////////////////////////////
// Config sets

    @(test)
    world__config_sets__test :: proc(t: ^testing.T) {
        w: dos.World
        testing.expect(t, dos.world_init(&w, {max_archetypes = 64, max_config_sets = 3, max_objects = 16}) == nil)
        defer dos.world_terminate(&w)

        items, err := dos.create_config_set(&w, "items")
        testing.expect(t, err == nil && items != dos.CORE)
        dlc, err2 := dos.create_config_set(&w, "dlc")
        testing.expect(t, err2 == nil && dlc != items)

        _, full := dos.create_config_set(&w, "extra")
        testing.expect(t, full == oc.Core_Error.Container_Is_Full)
        _, dup := dos.create_config_set(&w, "items")
        testing.expect(t, dup == dos.DOS_Error.Name_Already_Exists)

        found, ok := dos.find_config_set(&w, "dlc")
        testing.expect(t, ok && found == dlc)
        _, ok = dos.find_config_set(&w, "missing")
        testing.expect(t, !ok)

        // sets are separate databases sharing one config id space
        testing.expect(t, dos.config_db(&w, items) != dos.config_db(&w, dlc))
        eid, cerr := ecs.create_entity(dos.config_db(&w, items))
        testing.expect(t, cerr == nil)
        testing.expect(t, !ecs.is_expired(dos.config_db(&w, dos.CORE), eid))

        testing.expect(t, dos.unload_config_set(&w, dos.CORE) == dos.DOS_Error.Cannot_Unload_Core)
        testing.expect(t, dos.unload_config_set(&w, dlc) == nil)
        _, ok = dos.find_config_set(&w, "dlc")
        testing.expect(t, !ok)
        testing.expect(t, dos.unload_config_set(&w, dlc) == dos.DOS_Error.Config_Set_Not_Found)

        // the freed slot is reused
        again, err3 := dos.create_config_set(&w, "dlc2")
        testing.expect(t, err3 == nil && again == dlc)
    }
