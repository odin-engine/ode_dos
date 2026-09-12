/*
    2026 (c) Oleh, https://github.com/zm69

    Tests for links: typed relations between objects, iteration and autosnapping.
*/
package ode_dos__tests

// Core
    import "core:testing"

// ODE
    import dos "../src"
    import ecs "../../ode_ecs/src"

///////////////////////////////////////////////////////////////////////////////
// Links

    Ln_Slot :: enum u8 {
        Left_Hand,
        Right_Hand,
        Belt,
    }

    Ln_Contains :: struct {
        slot: Ln_Slot,
    }

    @(test)
    link__basics__test :: proc(t: ^testing.T) {
        w: dos.World
        testing.expect(t, dos.world_init(&w, {max_objects = 16}) == nil)
        defer dos.world_terminate(&w)

        dos.archetype(&w, "Guard")
        dos.archetype(&w, "Sword")
        g, _  := dos.spawn(&w, "Guard")
        s1, _ := dos.spawn(&w, "Sword")
        s2, _ := dos.spawn(&w, "Sword")

        contains, other: dos.Link(Ln_Contains)
        testing.expect(t, dos.link_init(&w, &contains, "Contains") == nil)
        testing.expect(t, dos.link_init(&w, &other, "Contains") == dos.DOS_Error.Name_Already_Exists)

        testing.expect(t, dos.link(&contains, g, s1, Ln_Contains{ slot = .Right_Hand }) == nil)
        testing.expect(t, dos.link(&contains, g, s2, Ln_Contains{ slot = .Belt }) == nil)

        testing.expect(t, dos.linked(&contains, g, s1))
        testing.expect(t, !dos.linked(&contains, s1, g))

        d, ok := dos.link_data(&contains, g, s1)
        testing.expect(t, ok && d.slot == .Right_Hand)

        // linking again updates the data
        testing.expect(t, dos.link(&contains, g, s1, Ln_Contains{ slot = .Left_Hand }) == nil)
        d, ok = dos.link_data(&contains, g, s1)
        testing.expect(t, ok && d.slot == .Left_Hand)
        testing.expect_value(t, dos.count_out(&contains, g), 2)
        testing.expect_value(t, dos.count_in(&contains, s1), 1)

        // both directions
        seen := 0
        it := dos.outgoing(&contains, g)
        for target, data in dos.next(&it) {
            testing.expect(t, target == s1 || target == s2)
            testing.expect(t, data != nil)
            seen += 1
        }
        testing.expect_value(t, seen, 2)

        seen = 0
        it2 := dos.incoming(&contains, s1)
        for source, _ in dos.next(&it2) {
            testing.expect(t, source == g)
            seen += 1
        }
        testing.expect_value(t, seen, 1)

        first, _, has_first := dos.first_target(&contains, g)
        testing.expect(t, has_first && (first == s1 || first == s2))

        testing.expect(t, dos.unlink(&contains, g, s2) == nil)
        testing.expect_value(t, dos.count_out(&contains, g), 1)
    }

    @(test)
    link__autosnap__test :: proc(t: ^testing.T) {
        w: dos.World
        testing.expect(t, dos.world_init(&w, {max_objects = 16}) == nil)
        defer dos.world_terminate(&w)

        dos.archetype(&w, "Guard")
        dos.archetype(&w, "Sword")
        g, _  := dos.spawn(&w, "Guard")
        s1, _ := dos.spawn(&w, "Sword")
        s2, _ := dos.spawn(&w, "Sword")

        contains: dos.Link(Ln_Contains)
        testing.expect(t, dos.link_init(&w, &contains, "Contains") == nil)

        testing.expect(t, dos.link(&contains, g, s1, Ln_Contains{}) == nil)
        testing.expect(t, dos.link(&contains, g, s2, Ln_Contains{}) == nil)

        // destroying either end removes the link
        testing.expect(t, dos.destroy(&w, s1) == nil)
        testing.expect(t, !dos.linked(&contains, g, s1))
        testing.expect_value(t, dos.count_out(&contains, g), 1)

        testing.expect(t, dos.unlink_all_from(&contains, g) == nil)
        testing.expect_value(t, dos.count_out(&contains, g), 0)

        testing.expect(t, dos.link(&contains, g, s2, Ln_Contains{}) == nil)
        testing.expect(t, dos.unlink_all_to(&contains, s2) == nil)
        testing.expect_value(t, dos.count_in(&contains, s2), 0)

        // a link flavor works as a view term: has at least one outgoing link
        carrying: ecs.View
        testing.expect(t, ecs.view_init(&carrying, dos.runtime(&w), {dos.link_table(&contains)}) == nil)
        testing.expect(t, dos.link(&contains, g, s2, Ln_Contains{}) == nil)
        testing.expect_value(t, ecs.view_len(&carrying), 1)
        testing.expect(t, dos.destroy(&w, g) == nil)
        testing.expect_value(t, ecs.view_len(&carrying), 0)
    }
