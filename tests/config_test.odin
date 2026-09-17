/*
    2026 (c) Oleh, https://github.com/zm69

    Tests for Config: its lifetime, and chaining one Config onto another.
*/
package ode_dos__tests

// Core
    import "core:testing"

// ODE
    import dos "../src"

///////////////////////////////////////////////////////////////////////////////
// Config

    @(test)
    config__lifetime__test :: proc(t: ^testing.T) {
        marker := 42
        cfg: dos.Config
        testing.expect(t, dos.config_init(&cfg, { user_data = &marker }) == nil)

        testing.expect(t, dos.user_data(&cfg) == &marker)
        testing.expect_value(t, len(dos.objects(&cfg)), 0)

        dos.config_terminate(&cfg)
        testing.expect(t, !cfg.initialized)

        // a terminated Config can be initialized again
        testing.expect(t, dos.config_init(&cfg) == nil)
        dos.config_terminate(&cfg)
    }

    // A DLC Config inherits from its base and can read what the base authored.
    @(test)
    config__base_chain__test :: proc(t: ^testing.T) {
        base, dlc: dos.Config
        testing.expect(t, dos.config_init(&base) == nil)
        defer dos.config_terminate(&base)
        testing.expect(t, dos.config_init(&dlc, { base = &base }) == nil)
        defer dos.config_terminate(&dlc)

        testing.expect(t, dos.load(&base, "data/base") == nil)
        testing.expect(t, dos.load(&dlc, "data/dlc") == nil)

        elite, ok := dos.find_archetype(&dlc, "dlc.EliteGuard")
        testing.expect(t, ok)

        // a base value, inherited across Configs
        mass, has_mass := dos.value(&dlc, elite, "mass")
        testing.expect(t, has_mass)
        m, _ := dos.as_float(mass)
        testing.expect_value(t, m, 80)

        // and the derived archetype's own value wins
        vision, _ := dos.value(&dlc, elite, "vision-range")
        v, _ := dos.as_float(vision)
        testing.expect_value(t, v, 60)

        // names reach up the chain, not down
        _, up := dos.find_archetype(&dlc, "core.Human")
        testing.expect(t, up)
        _, down := dos.find_archetype(&base, "dlc.EliteGuard")
        testing.expect(t, !down)

        obj, found := dos.find(&dlc, "dlc.Elite01")
        testing.expect(t, found)
        om, _ := dos.value(&dlc, obj, "mass")
        mo, _ := dos.as_float(om)
        testing.expect_value(t, mo, 80)
    }
