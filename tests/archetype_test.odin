/*
    2026 (c) Oleh, https://github.com/zm69

    Tests for archetypes, metas, surfaces and objects created in code.
*/
package ode_dos__tests

// Core
    import "core:testing"

// ODE
    import dos "../src"

///////////////////////////////////////////////////////////////////////////////
// Archetypes

    @(test)
    archetype__create_and_find__test :: proc(t: ^testing.T) {
        cfg: dos.Config
        testing.expect(t, dos.config_init(&cfg) == nil)
        defer dos.config_terminate(&cfg)

        physical, err := dos.archetype(&cfg, "Physical")
        testing.expect(t, err == nil)
        creature, err2 := dos.archetype(&cfg, "Creature", parent = "Physical")
        testing.expect(t, err2 == nil)
        guard, _ := dos.archetype(&cfg, "Guard", parent = "Creature")

        found, ok := dos.find_archetype(&cfg, "Creature")
        testing.expect(t, ok && found == creature)
        testing.expect_value(t, dos.name_of(&cfg, creature), "Creature")

        _, dup := dos.archetype(&cfg, "Physical")
        testing.expect(t, dup == dos.DOS_Error.Name_Already_Exists)
        _, missing := dos.archetype(&cfg, "Ghost", parent = "Nothing")
        testing.expect(t, missing == dos.DOS_Error.Name_Not_Found)

        m, merr := dos.meta(&cfg, "Wooden")
        testing.expect(t, merr == nil)
        _, wrong := dos.archetype(&cfg, "Chair", parent = "Wooden")
        testing.expect(t, wrong == dos.DOS_Error.Wrong_Kind)

        s, serr := dos.surface(&cfg, "Planks")
        testing.expect(t, serr == nil)
        testing.expect_value(t, dos.name_of(&cfg, m), "Wooden")
        testing.expect_value(t, dos.name_of(&cfg, s), "Planks")

        parent, has_parent := dos.parent_of(&cfg, creature)
        testing.expect(t, has_parent && parent == physical)
        _, root_parent := dos.parent_of(&cfg, physical)
        testing.expect(t, !root_parent)

        chain := dos.chain_of(&cfg, guard)
        testing.expect_value(t, len(chain), 2)
        if len(chain) == 2 {
            testing.expect(t, chain[0] == creature)
            testing.expect(t, chain[1] == physical)
        }
        testing.expect(t, dos.is_kind_of(&cfg, guard, physical))
        testing.expect(t, dos.is_kind_of(&cfg, guard, guard))
        testing.expect(t, !dos.is_kind_of(&cfg, physical, guard))
    }

    @(test)
    archetype__metas__test :: proc(t: ^testing.T) {
        cfg: dos.Config
        testing.expect(t, dos.config_init(&cfg) == nil)
        defer dos.config_terminate(&cfg)

        guard, _ := dos.archetype(&cfg, "Guard")
        planks, _ := dos.surface(&cfg, "Planks")
        alert, _ := dos.meta(&cfg, "Alert")
        wooden, _ := dos.meta(&cfg, "Wooden")

        testing.expect(t, dos.attach(&cfg, guard, alert, 50) == nil)
        testing.expect(t, dos.attach(&cfg, guard, wooden, 10) == nil)
        testing.expect(t, dos.attach(&cfg, planks, wooden) == nil)

        metas := dos.metas_of(&cfg, guard)
        testing.expect_value(t, len(metas), 2)
        if len(metas) == 2 {
            testing.expect(t, metas[0].meta == alert) // highest priority first
            testing.expect_value(t, metas[0].priority, 50)
        }

        // attaching again updates the priority
        testing.expect(t, dos.attach(&cfg, guard, wooden, 90) == nil)
        metas = dos.metas_of(&cfg, guard)
        if len(metas) == 2 do testing.expect(t, metas[0].meta == wooden)

        testing.expect(t, dos.detach(&cfg, guard, wooden) == nil)
        testing.expect_value(t, len(dos.metas_of(&cfg, guard)), 1)
        testing.expect_value(t, len(dos.metas_of(&cfg, planks)), 1)
    }

    @(test)
    archetype__objects__test :: proc(t: ^testing.T) {
        cfg: dos.Config
        testing.expect(t, dos.config_init(&cfg) == nil)
        defer dos.config_terminate(&cfg)

        creature, _ := dos.archetype(&cfg, "Creature")
        guard, _ := dos.archetype(&cfg, "Guard", parent = "Creature")
        sword, _ := dos.archetype(&cfg, "Sword")
        wooden, _ := dos.meta(&cfg, "Wooden")

        g1, err := dos.object(&cfg, guard, "Guard01")
        testing.expect(t, err == nil)
        g2, _ := dos.object(&cfg, guard)              // unnamed
        s1, _ := dos.object(&cfg, sword, "Sword01")

        testing.expect(t, dos.archetype_of(&cfg, g1) == guard)
        testing.expect_value(t, dos.name_of(&cfg, g1), "Guard01")
        testing.expect_value(t, dos.name_of(&cfg, g2), "")

        found, ok := dos.find(&cfg, "Guard01")
        testing.expect(t, ok && found == g1)
        _, missing := dos.find(&cfg, "Nobody")
        testing.expect(t, !missing)

        _, wrong := dos.object(&cfg, dos.archetype_id(wooden), "Bad")
        testing.expect(t, wrong == dos.DOS_Error.Wrong_Kind)
        _, dup := dos.object(&cfg, guard, "Guard01")
        testing.expect(t, dup == dos.DOS_Error.Name_Already_Exists)

        testing.expect_value(t, len(dos.objects(&cfg)), 3)
        testing.expect_value(t, len(dos.objects_of(&cfg, guard)), 2)
        testing.expect_value(t, len(dos.objects_of(&cfg, creature)), 2) // derived archetypes count
        testing.expect_value(t, len(dos.objects_of(&cfg, sword)), 1)
        testing.expect(t, dos.objects_of(&cfg, sword)[0] == s1)

        testing.expect(t, dos.set_name(&cfg, g1, "Captain") == nil)
        testing.expect_value(t, dos.name_of(&cfg, g1), "Captain")
        _, old := dos.find(&cfg, "Guard01")
        testing.expect(t, !old)
        testing.expect(t, dos.set_name(&cfg, g2, "Captain") == dos.DOS_Error.Name_Already_Exists)
    }
