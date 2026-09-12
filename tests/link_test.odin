/*
    2026 (c) Oleh, https://github.com/zm69

    Tests for links between designed objects: both directions, their data and removal.
*/
package ode_dos__tests

// Core
    import "core:testing"

// ODE
    import dos "../src"

///////////////////////////////////////////////////////////////////////////////
// Types

    Lk_Slot :: enum u8 {
        Left_Hand,
        Right_Hand,
    }

    Lk_Contains :: struct {
        slot: Lk_Slot,
    }

///////////////////////////////////////////////////////////////////////////////
// Links

    @(test)
    link__both_directions__test :: proc(t: ^testing.T) {
        cfg: dos.Config
        testing.expect(t, dos.config_init(&cfg, { keep_names = true }) == nil)
        defer dos.config_terminate(&cfg)

        contains: dos.Link(Lk_Contains)
        testing.expect(t, dos.link_init(&cfg, &contains, "Contains", cap = 16) == nil)
        testing.expect(t, dos.link_init(&cfg, &contains, "Contains") == dos.DOS_Error.Name_Already_Exists)

        thing, _ := dos.archetype(&cfg, "Thing")
        guard, _ := dos.object(&cfg, thing, "Guard01")
        sword, _ := dos.object(&cfg, thing, "Sword01")
        torch, _ := dos.object(&cfg, thing, "Torch01")

        testing.expect(t, dos.link(&contains, guard, sword, Lk_Contains{ .Right_Hand }) == nil)
        testing.expect(t, dos.link(&contains, guard, torch, Lk_Contains{ .Left_Hand }) == nil)

        testing.expect(t, dos.linked(&contains, guard, sword))
        testing.expect(t, !dos.linked(&contains, sword, guard))
        testing.expect_value(t, dos.count_out(&contains, guard), 2)
        testing.expect_value(t, dos.count_in(&contains, sword), 1)

        d, ok := dos.link_data(&contains, guard, torch)
        testing.expect(t, ok && d.slot == .Left_Hand)

        // linking again updates the data
        testing.expect(t, dos.link(&contains, guard, torch, Lk_Contains{ .Right_Hand }) == nil)
        d2, _ := dos.link_data(&contains, guard, torch)
        testing.expect(t, d2.slot == .Right_Hand)
        testing.expect_value(t, dos.count_out(&contains, guard), 2)

        seen := 0
        it := dos.links_of(&contains, guard)
        for target, data in dos.next(&it) {
            testing.expect(t, target == sword || target == torch)
            testing.expect(t, data != nil)
            seen += 1
        }
        testing.expect_value(t, seen, 2)

        back := dos.links_to(&contains, sword)
        holder, _, has := dos.next(&back)
        testing.expect(t, has && holder == guard)

        testing.expect(t, dos.unlink(&contains, guard, sword) == nil)
        testing.expect(t, !dos.linked(&contains, guard, sword))
        testing.expect_value(t, dos.count_out(&contains, guard), 1)
    }
