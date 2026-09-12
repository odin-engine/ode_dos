/*
    2026 (c) Oleh, https://github.com/zm69

    Tests for archetypes, metas, surfaces and inheritance.
*/
package ode_dos__tests

// Core
    import "core:testing"

// ODE
    import dos "../src"

///////////////////////////////////////////////////////////////////////////////
// Archetypes

    @(test)
    archetype__forest__test :: proc(t: ^testing.T) {
        w: dos.World
        testing.expect(t, dos.world_init(&w, {max_objects = 16, keep_names = true}) == nil)
        defer dos.world_terminate(&w)

        physical, e1 := dos.archetype(&w, "Physical")
        creature, e2 := dos.archetype(&w, "Creature", parent = "Physical")
        human, e3    := dos.archetype(&w, "Human", parent = "Creature")
        guard, e4    := dos.archetype(&w, "Guard", parent = "Human")
        testing.expect(t, e1 == nil && e2 == nil && e3 == nil && e4 == nil)

        found, ok := dos.find_archetype(&w, "Human")
        testing.expect(t, ok && found == human)
        testing.expect_value(t, dos.name_of(&w, guard), "Guard")

        _, dup := dos.archetype(&w, "Guard")
        testing.expect(t, dup == dos.DOS_Error.Name_Already_Exists)
        _, unknown := dos.archetype(&w, "EliteGuard", parent = "Humn")
        testing.expect(t, unknown == dos.DOS_Error.Name_Not_Found)
        _, empty := dos.archetype(&w, "")
        testing.expect(t, empty == dos.DOS_Error.Invalid_Name)

        p, has_parent := dos.parent_of(&w, guard)
        testing.expect(t, has_parent && p == human)
        _, has_parent = dos.parent_of(&w, physical)
        testing.expect(t, !has_parent)

        chain := dos.chain_of(&w, guard)
        testing.expect_value(t, len(chain), 3)
        if len(chain) == 3 {
            testing.expect(t, chain[0] == human && chain[1] == creature && chain[2] == physical)
        }

        testing.expect(t, dos.is_kind_of(&w, guard, creature))
        testing.expect(t, dos.is_kind_of(&w, guard, guard))
        testing.expect(t, !dos.is_kind_of(&w, creature, guard))
    }

    @(test)
    archetype__kinds__test :: proc(t: ^testing.T) {
        w: dos.World
        testing.expect(t, dos.world_init(&w, {max_objects = 16}) == nil)
        defer dos.world_terminate(&w)

        wooden, _ := dos.meta(&w, "Wooden")
        planks, _ := dos.surface(&w, "WoodPlanks")

        // a meta or surface is not an archetype
        _, err := dos.archetype(&w, "Crate", parent = "Wooden")
        testing.expect(t, err == dos.DOS_Error.Wrong_Kind)
        _, ok := dos.find_archetype(&w, "Wooden")
        testing.expect(t, !ok)

        m, found_meta := dos.find_meta(&w, "Wooden")
        testing.expect(t, found_meta && m == wooden)
        s, found_surface := dos.find_surface(&w, "WoodPlanks")
        testing.expect(t, found_surface && s == planks)

        // names are shared across kinds
        _, dup := dos.meta(&w, "WoodPlanks")
        testing.expect(t, dup == dos.DOS_Error.Name_Already_Exists)
    }

///////////////////////////////////////////////////////////////////////////////
// Metas

    @(test)
    archetype__metas__test :: proc(t: ^testing.T) {
        w: dos.World
        testing.expect(t, dos.world_init(&w, {max_objects = 16, keep_names = true}) == nil)
        defer dos.world_terminate(&w)

        guard, _  := dos.archetype(&w, "Guard")
        wooden, _ := dos.meta(&w, "Wooden")
        alert, _  := dos.meta(&w, "Alert")
        alpha, _  := dos.meta(&w, "Alpha")

        testing.expect(t, dos.attach(&w, guard, wooden, priority = 10) == nil)
        testing.expect(t, dos.attach(&w, guard, alert, priority = 50) == nil)

        metas := dos.metas_of(&w, guard)
        testing.expect_value(t, len(metas), 2)
        if len(metas) == 2 {
            testing.expect(t, metas[0].meta == alert && metas[0].priority == 50)
            testing.expect(t, metas[1].meta == wooden)
        }

        // re-attaching changes the priority; equal priorities sort by name
        testing.expect(t, dos.attach(&w, guard, wooden, priority = 60) == nil)
        testing.expect(t, dos.attach(&w, guard, alpha, priority = 60) == nil)
        metas = dos.metas_of(&w, guard)
        testing.expect_value(t, len(metas), 3)
        if len(metas) == 3 {
            testing.expect(t, metas[0].meta == alpha && metas[1].meta == wooden && metas[2].meta == alert)
        }

        testing.expect(t, dos.detach(&w, guard, alpha) == nil)
        testing.expect_value(t, len(dos.metas_of(&w, guard)), 2)

        planks, _ := dos.surface(&w, "WoodPlanks")
        testing.expect(t, dos.attach(&w, planks, wooden) == nil)
        testing.expect_value(t, len(dos.metas_of(&w, planks)), 1)
    }

///////////////////////////////////////////////////////////////////////////////
// Config sets

    @(test)
    archetype__config_sets__test :: proc(t: ^testing.T) {
        w: dos.World
        testing.expect(t, dos.world_init(&w, {max_objects = 16, keep_names = true}) == nil)
        defer dos.world_terminate(&w)

        items, _ := dos.create_config_set(&w, "items")
        dlc, _   := dos.create_config_set(&w, "dlc")

        physical, _ := dos.archetype(&w, "Physical")
        wooden, _   := dos.meta(&w, "Wooden")

        // a parent in CORE is allowed from any set
        sword, err := dos.archetype(&w, "items.Sword", parent = "Physical", set = items)
        testing.expect(t, err == nil)
        testing.expect(t, dos.is_kind_of(&w, sword, physical))
        testing.expect(t, dos.attach(&w, sword, wooden) == nil)

        // a parent in another non-CORE set is not
        _, cross := dos.archetype(&w, "dlc.Saber", parent = "items.Sword", set = dlc)
        testing.expect(t, cross == dos.DOS_Error.Parent_Not_Allowed)

        // unloading a set removes its archetypes and frees their names
        testing.expect(t, dos.unload_config_set(&w, items) == nil)
        _, ok := dos.find_archetype(&w, "items.Sword")
        testing.expect(t, !ok)

        again, _ := dos.create_config_set(&w, "items")
        _, err = dos.archetype(&w, "items.Sword", parent = "Physical", set = again)
        testing.expect(t, err == nil)
    }
