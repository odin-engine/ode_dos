/*
    2026 (c) Oleh, https://github.com/zm69

    Tests for saving and loading runtime state.
*/
package ode_dos__tests

// Core
    import "core:os"
    import "core:testing"

// ODE
    import dos "../src"

///////////////////////////////////////////////////////////////////////////////
// Save and load

    Sv_Health   :: struct { current, max: int }
    Sv_Mass     :: struct { value: f32 }
    Sv_Contains :: struct { slot: int }

    Sv_Status :: enum u8 {
        Dead,
        Alerted,
    }

    Sv_Game :: struct {
        w:        dos.World,
        health:   dos.State(Sv_Health),
        status:   dos.State_Flags(Sv_Status),
        contains: dos.Link(Sv_Contains),
        mass:     dos.Property(Sv_Mass),
    }

    // Both games must declare the same things in the same order.
    @(private = "file")
    sv_setup :: proc(t: ^testing.T, g: ^Sv_Game) {
        testing.expect(t, dos.world_init(&g.w, {max_archetypes = 16, max_objects = 16}) == nil)
        testing.expect(t, dos.state_init(&g.w, &g.health, "health") == nil)
        testing.expect(t, dos.state_flags_init(&g.w, &g.status, "status") == nil)
        testing.expect(t, dos.link_init(&g.w, &g.contains, "Contains") == nil)
        testing.expect(t, dos.property_init(&g.w, &g.mass, "mass") == nil)
        testing.expect(t, dos.effect_register(&g.w, "Burning", dos.Effect{}) == nil)

        guard, _ := dos.archetype(&g.w, "Guard")
        dos.archetype(&g.w, "Sword")
        testing.expect(t, dos.set_property(&g.mass, guard, Sv_Mass{ 10 }) == nil)
        testing.expect(t, dos.bake(&g.w) == nil)
    }

    @(test)
    save__round_trip__test :: proc(t: ^testing.T) {
        PATH :: "out/save_round_trip.bin"
        defer os.remove(PATH)

        a: Sv_Game
        sv_setup(t, &a)
        defer dos.world_terminate(&a.w)

        guard, _ := dos.spawn(&a.w, "Guard")
        sword, _ := dos.spawn(&a.w, "Sword")
        testing.expect(t, dos.set_name(&a.w, guard, "Guard01") == nil)
        testing.expect(t, dos.add(&a.health, guard, Sv_Health{ current = 70, max = 100 }) == nil)
        testing.expect(t, dos.set(&a.status, guard, Sv_Status.Alerted) == nil)
        testing.expect(t, dos.link(&a.contains, guard, sword, Sv_Contains{ slot = 2 }) == nil)
        testing.expect(t, dos.override(&a.mass, guard, Sv_Mass{ 95 }) == nil)
        testing.expect(t, dos.apply(&a.w, guard, "Burning") == nil)

        testing.expect(t, dos.save_game(&a.w, PATH) == nil)

        b: Sv_Game
        sv_setup(t, &b)
        defer dos.world_terminate(&b.w)
        testing.expect(t, dos.load_game(&b.w, PATH) == nil)

        g, found := dos.find(&b.w, "Guard01")
        testing.expect(t, found)
        if !found do return

        testing.expect(t, dos.alive(&b.w, g))
        a_guard, _ := dos.find_archetype(&b.w, "Guard")
        testing.expect(t, dos.archetype_of(&b.w, g) == a_guard)
        testing.expect(t, dos.get(&b.health, g) != nil && dos.get(&b.health, g).current == 70)
        testing.expect(t, dos.is_set(&b.status, g, Sv_Status.Alerted))
        testing.expect_value(t, dos.count_out(&b.contains, g), 1)
        testing.expect_value(t, dos.resolve(&b.mass, g).value, 95)
        testing.expect(t, dos.affected(&b.w, g, "Burning"))
    }
