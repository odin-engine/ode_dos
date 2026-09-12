/*
    2026 (c) Oleh, https://github.com/zm69

    Tests for Config: its Database, its capacity and chaining one Config onto another.
*/
package ode_dos__tests

// Core
    import "core:testing"

// ODE
    import dos "../src"
    import ecs "../../ode_ecs/src"

///////////////////////////////////////////////////////////////////////////////
// Types

    Cfg_Mass :: struct { value: f32 }

///////////////////////////////////////////////////////////////////////////////
// Config

    @(test)
    config__defaults__test :: proc(t: ^testing.T) {
        cfg: dos.Config
        testing.expect(t, dos.config_init(&cfg) == nil)
        defer dos.config_terminate(&cfg)

        entities, attachments := dos.config_capacity(&cfg)
        testing.expect_value(t, entities, 1)
        testing.expect_value(t, attachments, 1)

        testing.expect(t, dos.config_db(&cfg) != nil)
        testing.expect_value(t, cfg.keep_names, ODIN_DEBUG)
    }

    @(test)
    config__user_data__test :: proc(t: ^testing.T) {
        marker := 42
        cfg: dos.Config
        testing.expect(t, dos.config_init(&cfg, { keep_names = false, user_data = &marker }) == nil)
        defer dos.config_terminate(&cfg)

        testing.expect(t, dos.user_data(&cfg) == &marker)
        testing.expect(t, !cfg.keep_names)
    }

    @(test)
    config__terminate_resets__test :: proc(t: ^testing.T) {
        cfg: dos.Config
        testing.expect(t, dos.config_init(&cfg) == nil)
        dos.config_terminate(&cfg)
        testing.expect(t, cfg.state == .Not_Initialized)

        // a terminated Config can be initialized again
        testing.expect(t, dos.config_init(&cfg) == nil)
        dos.config_terminate(&cfg)
    }

    // A DLC Config inherits from its base and shares its id space.
    @(test)
    config__base_chain__test :: proc(t: ^testing.T) {
        base, dlc: dos.Config
        testing.expect(t, dos.config_init(&base, { keep_names = true }) == nil)
        defer dos.config_terminate(&base)
        testing.expect(t, dos.config_init(&dlc, { base = &base, keep_names = true }) == nil)
        defer dos.config_terminate(&dlc)

        mass: dos.Property(Cfg_Mass)
        testing.expect(t, dos.property_init(&base, &mass, "mass") == nil)

        human, _ := dos.archetype(&base, "Human")
        testing.expect(t, dos.set_property(&mass, human, Cfg_Mass{ 10 }) == nil)

        guard, gerr := dos.archetype(&dlc, "Guard", parent = "Human")
        testing.expect(t, gerr == nil)
        testing.expect(t, dos.bake(&dlc) == nil)

        // the base property resolves for the derived archetype
        m := dos.resolve(&mass, guard)
        testing.expect(t, m != nil && m.value == 10)

        // names reach up the chain, not down
        _, up := dos.find_archetype(&dlc, "Human")
        testing.expect(t, up)
        _, down := dos.find_archetype(&base, "Guard")
        testing.expect(t, !down)

        // an object of a derived archetype resolves the base property too
        obj, oerr := dos.object(&dlc, guard, "G1")
        testing.expect(t, oerr == nil)
        om := dos.resolve(&mass, obj)
        testing.expect(t, om != nil && om.value == 10)

        // one id space
        testing.expect(t, dos.config_db(&base) != dos.config_db(&dlc))
        testing.expect(t, !ecs.is_expired(dos.config_db(&base), ecs.entity_id(obj)))
    }
