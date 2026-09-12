/*
    2026 (c) Oleh, https://github.com/zm69

    Tests for Reflection: designed objects, their names and the queries a game runs over them.
*/
package ode_dos__tests

// Core
    import "core:testing"

// ODE
    import dos "../src"

///////////////////////////////////////////////////////////////////////////////
// Objects

    @(test)
    reflection__objects__test :: proc(t: ^testing.T) {
        cfg: dos.Config
        testing.expect(t, dos.config_init(&cfg, { keep_names = true }) == nil)
        defer dos.config_terminate(&cfg)

        creature, _ := dos.archetype(&cfg, "Creature")
        guard, _ := dos.archetype(&cfg, "Guard", parent = "Creature")
        sword, _ := dos.archetype(&cfg, "Sword")
        wooden, _ := dos.meta(&cfg, "Wooden")

        g1, err := dos.object(&cfg, guard, "Guard01")
        testing.expect(t, err == nil)
        g2, _ := dos.object(&cfg, guard)          // unnamed
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

        // renaming releases the old name
        testing.expect(t, dos.set_name(&cfg, g1, "Captain") == nil)
        testing.expect_value(t, dos.name_of(&cfg, g1), "Captain")
        _, old := dos.find(&cfg, "Guard01")
        testing.expect(t, !old)
        testing.expect(t, dos.set_name(&cfg, g2, "Captain") == dos.DOS_Error.Name_Already_Exists)
        testing.expect(t, dos.set_name(&cfg, g2, "Guard02") == nil)
        testing.expect_value(t, len(dos.objects(&cfg)), 3)
    }
