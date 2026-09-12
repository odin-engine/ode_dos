/*
    2026 (c) Oleh, https://github.com/zm69

    Tests for config capacity: a load sizes config space to exactly what it declares, a hot
    reload or a new set grows it by what it adds, and code-path creation doubles it.
*/
package ode_dos__tests

// Core
    import "core:fmt"
    import "core:os"
    import "core:testing"

// ODE
    import dos "../src"

///////////////////////////////////////////////////////////////////////////////
// Sizing

    @(test)
    sizing__load_is_exact__test :: proc(t: ^testing.T) {
        g: Ld_Game
        ld_setup(t, &g)
        defer dos.world_terminate(&g.w)

        testing.expect(t, dos.load(&g.w, "data/ok") == nil)

        // 5 archetypes, 2 metas and 1 surface; Guard -> Alert and WoodPlanks -> Wooden
        archetypes, attachments := dos.config_capacity(&g.w)
        testing.expect_value(t, archetypes, 8)
        testing.expect_value(t, attachments, 2)

        g01, found := dos.find(&g.w, "bafford.Guard01")
        testing.expect(t, found)
        v := dos.resolve(&g.vision, g01)
        testing.expect(t, v != nil && v.range == 45)
        m := dos.resolve(&g.mass, g01)
        testing.expect(t, m != nil && m.value == 10)
    }

    @(test)
    sizing__reload_grows_by_what_it_adds__test :: proc(t: ^testing.T) {
        g: Ld_Game
        ld_setup(t, &g)
        defer dos.world_terminate(&g.w)

        testing.expect(t, dos.load(&g.w, "data/ok") == nil)
        guard, _ := dos.find_archetype(&g.w, "core.Guard")
        g01, _ := dos.find(&g.w, "bafford.Guard01")
        db := dos.config_db(&g.w)

        // one archetype and one attachment more
        testing.expect(t, dos.load(&g.w, "data/grow") == nil)
        archetypes, attachments := dos.config_capacity(&g.w)
        testing.expect_value(t, archetypes, 9)
        testing.expect_value(t, attachments, 3)

        again, _ := dos.find_archetype(&g.w, "core.Guard")
        testing.expect_value(t, again, guard)
        testing.expect(t, dos.alive(&g.w, g01))
        testing.expect_value(t, dos.archetype_of(&g.w, g01), guard)
        testing.expect(t, dos.config_db(&g.w) == db)
        hp := dos.resolve(&g.max_hp, g01)
        testing.expect(t, hp != nil && hp.value == 75)

        archer, err := dos.spawn(&g.w, "core.Archer")
        testing.expect(t, err == nil)
        v := dos.resolve(&g.vision, archer)
        testing.expect(t, v != nil && v.range == 45)
        m := dos.resolve(&g.mass, archer)
        testing.expect(t, m != nil && m.value == 10)

        // a second set grows by what it adds
        dlc, cerr := dos.create_config_set(&g.w, "dlc")
        testing.expect(t, cerr == nil)
        testing.expect(t, dos.load(&g.w, "data/grow_dlc", dlc) == nil)
        archetypes, attachments = dos.config_capacity(&g.w)
        testing.expect_value(t, archetypes, 10)
        testing.expect_value(t, attachments, 3)

        shield, found := dos.find_archetype(&g.w, "dlc.Shield")
        testing.expect(t, found)
        sm := dos.resolve(&g.mass, shield)
        testing.expect(t, sm != nil && sm.value == 10)
    }

    @(test)
    sizing__same_shape_reload_does_not_grow__test :: proc(t: ^testing.T) {
        g: Ld_Game
        ld_setup(t, &g)
        defer dos.world_terminate(&g.w)

        testing.expect(t, dos.load(&g.w, "data/reload_a") == nil)
        before, before_att := dos.config_capacity(&g.w)
        testing.expect_value(t, before, 1)

        testing.expect(t, dos.load(&g.w, "data/reload_b") == nil)
        after, after_att := dos.config_capacity(&g.w)
        testing.expect_value(t, after, before)
        testing.expect_value(t, after_att, before_att)

        crate, _ := dos.find(&g.w, "Crate01")
        m := dos.resolve(&g.mass, crate)
        testing.expect(t, m != nil && m.value == 7)
    }

    @(test)
    sizing__code_doubles__test :: proc(t: ^testing.T) {
        w: dos.World
        testing.expect(t, dos.world_init(&w, {max_objects = 8}) == nil)
        defer dos.world_terminate(&w)

        mass: dos.Property(Ld_Mass)
        testing.expect(t, dos.property_init(&w, &mass, "mass") == nil)

        root, err := dos.archetype(&w, "Root")
        testing.expect(t, err == nil)
        testing.expect(t, dos.set_property(&mass, root, Ld_Mass{ 3 }) == nil)
        archetypes, _ := dos.config_capacity(&w)
        testing.expect_value(t, archetypes, 1)

        child, cerr := dos.archetype(&w, "Child", parent = "Root")
        testing.expect(t, cerr == nil)
        archetypes, _ = dos.config_capacity(&w)
        testing.expect_value(t, archetypes, 16)

        for i in 0..<14 {
            _, berr := dos.archetype(&w, fmt.tprintf("B%d", i))
            testing.expect(t, berr == nil)
        }
        archetypes, _ = dos.config_capacity(&w)
        testing.expect_value(t, archetypes, 16)

        _, derr := dos.archetype(&w, "Last")
        testing.expect(t, derr == nil)
        archetypes, _ = dos.config_capacity(&w)
        testing.expect_value(t, archetypes, 32)

        m1, _ := dos.meta(&w, "M1")
        m2, _ := dos.meta(&w, "M2")
        testing.expect(t, dos.attach(&w, child, m1) == nil)
        testing.expect(t, dos.attach(&w, child, m2) == nil)
        _, attachments := dos.config_capacity(&w)
        testing.expect_value(t, attachments, 16)

        testing.expect(t, dos.bake(&w) == nil)
        m := dos.resolve(&mass, child)
        testing.expect(t, m != nil && m.value == 3)
        testing.expect_value(t, len(dos.metas_of(&w, child)), 2)

        // a load that fits needs no growth, and capacity never shrinks
        testing.expect(t, dos.load(&w, "data/reload_a") == nil)
        archetypes, _ = dos.config_capacity(&w)
        testing.expect_value(t, archetypes, 32)
    }

    @(test)
    sizing__save_survives_grow__test :: proc(t: ^testing.T) {
        g: Ld_Game
        ld_setup(t, &g)
        defer dos.world_terminate(&g.w)

        testing.expect(t, dos.load(&g.w, "data/ok") == nil)
        guard, _ := dos.find_archetype(&g.w, "core.Guard")

        path := "sizing_test.sav"
        defer os.remove(path)
        testing.expect(t, dos.save_game(&g.w, path) == nil)

        testing.expect(t, dos.load(&g.w, "data/grow") == nil)
        testing.expect(t, dos.load_game(&g.w, path) == nil)

        g01, found := dos.find(&g.w, "bafford.Guard01")
        testing.expect(t, found)
        testing.expect_value(t, dos.archetype_of(&g.w, g01), guard)
        hp := dos.resolve(&g.max_hp, g01)
        testing.expect(t, hp != nil && hp.value == 75)
    }
