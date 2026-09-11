/*
    2026 (c) Oleh, https://github.com/zm69

    Tests for runtime effects.
*/
package ode_dos__tests

// Core
    import "core:testing"

// ODE
    import dos "../src"
    import ecs "../../ode_ecs/src"

///////////////////////////////////////////////////////////////////////////////
// Effects

    Ef_Status :: enum u8 {
        Unconscious,
        Burning,
    }

    Ef_Game :: struct {
        status:   dos.State_Flags(Ef_Status),
        attached: int,
        detached: int,
    }

    @(test)
    effect__apply_unapply__test :: proc(t: ^testing.T) {
        g: Ef_Game
        w: dos.World
        testing.expect(t, dos.world_init(&w, {max_archetypes = 16, max_objects = 16, user_data = &g}) == nil)
        defer dos.world_terminate(&w)

        testing.expect(t, dos.state_flags_init(&w, &g.status, "status") == nil)
        dos.archetype(&w, "Guard")
        guard, _ := dos.spawn(&w, "Guard")
        other, _ := dos.spawn(&w, "Guard")

        testing.expect(t, dos.effect_register(&w, "KnockedOut", dos.Effect{
            on_attach = proc(w: ^dos.World, obj: dos.object_id) {
                g := cast(^Ef_Game) dos.user_data(w)
                g.attached += 1
                dos.set(&g.status, obj, Ef_Status.Unconscious)
            },
            on_detach = proc(w: ^dos.World, obj: dos.object_id) {
                g := cast(^Ef_Game) dos.user_data(w)
                g.detached += 1
                dos.unset(&g.status, obj, Ef_Status.Unconscious)
            },
        }) == nil)
        testing.expect(t, dos.effect_register(&w, "KnockedOut", dos.Effect{}) == dos.DOS_Error.Name_Already_Exists)
        testing.expect(t, dos.effect_register(&w, "Burning", dos.Effect{}) == nil)

        testing.expect(t, dos.apply(&w, guard, "KnockedOut") == nil)
        testing.expect(t, dos.affected(&w, guard, "KnockedOut"))
        testing.expect(t, !dos.affected(&w, other, "KnockedOut"))
        testing.expect(t, dos.is_set(&g.status, guard, Ef_Status.Unconscious))

        // applying again does not run the hook again
        testing.expect(t, dos.apply(&w, guard, "KnockedOut") == nil)
        testing.expect_value(t, g.attached, 1)

        // effects without hooks, and views over applied effects
        testing.expect(t, dos.apply(&w, other, "Burning") == nil)
        term, ok := dos.effect_term(&w, "Burning")
        testing.expect(t, ok)
        burning: ecs.View
        testing.expect(t, ecs.view_init(&burning, dos.runtime(&w), {term}) == nil)
        testing.expect(t, ecs.rebuild(&burning) == nil)
        testing.expect_value(t, ecs.view_len(&burning), 1)

        testing.expect(t, dos.unapply(&w, guard, "KnockedOut") == nil)
        testing.expect(t, !dos.affected(&w, guard, "KnockedOut"))
        testing.expect(t, !dos.is_set(&g.status, guard, Ef_Status.Unconscious))
        testing.expect(t, dos.unapply(&w, guard, "KnockedOut") == nil)
        testing.expect_value(t, g.detached, 1)

        testing.expect(t, dos.apply(&w, guard, "Missing") == dos.DOS_Error.Name_Not_Found)
    }
