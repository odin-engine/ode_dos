/*
    2026 (c) Oleh, https://github.com/zm69

    Tests for config capacity: a load sizes it to exactly what it declares, a reload grows it by
    what it adds, and code-path creation doubles it.
*/
package ode_dos__tests

// Core
    import "core:fmt"
    import "core:testing"

// ODE
    import dos "../src"

///////////////////////////////////////////////////////////////////////////////
// Sizing

    @(test)
    sizing__load_is_exact__test :: proc(t: ^testing.T) {
        g: Ld_Game
        ld_setup(t, &g)
        defer dos.config_terminate(&g.cfg)

        testing.expect(t, dos.load(&g.cfg, "data/ok") == nil)

        // 5 archetypes, 2 metas, 1 surface and 2 objects; Guard -> Alert and WoodPlanks -> Wooden
        entities, attachments := dos.config_capacity(&g.cfg)
        testing.expect_value(t, entities, 10)
        testing.expect_value(t, attachments, 2)
    }

    @(test)
    sizing__reload_grows_by_what_it_adds__test :: proc(t: ^testing.T) {
        g: Ld_Game
        ld_setup(t, &g)
        defer dos.config_terminate(&g.cfg)
        cfg := &g.cfg

        testing.expect(t, dos.load(cfg, "data/ok") == nil)
        guard, _ := dos.find_archetype(cfg, "core.Guard")
        g01, _ := dos.find(cfg, "bafford.Guard01")

        // one archetype and one attachment more
        testing.expect(t, dos.load(cfg, "data/grow") == nil)
        entities, attachments := dos.config_capacity(cfg)
        testing.expect_value(t, entities, 11)
        testing.expect_value(t, attachments, 3)

        again, _ := dos.find_archetype(cfg, "core.Guard")
        testing.expect(t, again == guard)
        testing.expect(t, dos.archetype_of(cfg, g01) == guard)
        testing.expect_value(t, dos.resolve(&g.max_hp, g01).value, 75)

        archer, ok := dos.find_archetype(cfg, "core.Archer")
        testing.expect(t, ok)
        testing.expect_value(t, dos.resolve(&g.vision, archer).range, 45)
    }

    @(test)
    sizing__same_shape_reload_does_not_grow__test :: proc(t: ^testing.T) {
        g: Ld_Game
        ld_setup(t, &g)
        defer dos.config_terminate(&g.cfg)

        testing.expect(t, dos.load(&g.cfg, "data/reload_a") == nil)
        before, before_att := dos.config_capacity(&g.cfg)
        testing.expect_value(t, before, 2) // one archetype and one object

        testing.expect(t, dos.load(&g.cfg, "data/reload_b") == nil)
        after, after_att := dos.config_capacity(&g.cfg)
        testing.expect_value(t, after, before)
        testing.expect_value(t, after_att, before_att)
    }

    @(test)
    sizing__code_doubles__test :: proc(t: ^testing.T) {
        cfg: dos.Config
        testing.expect(t, dos.config_init(&cfg, { keep_names = true }) == nil)
        defer dos.config_terminate(&cfg)

        mass: dos.Property(Ld_Mass)
        testing.expect(t, dos.property_init(&cfg, &mass, "mass") == nil)

        root, err := dos.archetype(&cfg, "Root")
        testing.expect(t, err == nil)
        testing.expect(t, dos.set_property(&mass, root, Ld_Mass{ 3 }) == nil)
        entities, _ := dos.config_capacity(&cfg)
        testing.expect_value(t, entities, 1)

        child, cerr := dos.archetype(&cfg, "Child", parent = "Root")
        testing.expect(t, cerr == nil)
        entities, _ = dos.config_capacity(&cfg)
        testing.expect_value(t, entities, 16)

        for i in 0..<14 {
            _, berr := dos.archetype(&cfg, fmt.tprintf("B%d", i))
            testing.expect(t, berr == nil)
        }
        entities, _ = dos.config_capacity(&cfg)
        testing.expect_value(t, entities, 16)

        _, derr := dos.archetype(&cfg, "Last")
        testing.expect(t, derr == nil)
        entities, _ = dos.config_capacity(&cfg)
        testing.expect_value(t, entities, 32)

        m1, _ := dos.meta(&cfg, "M1")
        m2, _ := dos.meta(&cfg, "M2")
        testing.expect(t, dos.attach(&cfg, child, m1) == nil)
        testing.expect(t, dos.attach(&cfg, child, m2) == nil)
        _, attachments := dos.config_capacity(&cfg)
        testing.expect_value(t, attachments, 16)

        testing.expect(t, dos.bake(&cfg) == nil)
        m := dos.resolve(&mass, child)
        testing.expect(t, m != nil && m.value == 3)
        testing.expect_value(t, len(dos.metas_of(&cfg, child)), 2)
    }
