/*
    2026 (c) Oleh, https://github.com/zm69

    Tests for runtime state: State(T) and State_Flags(E).
*/
package ode_dos__tests

// Core
    import "core:testing"

// ODE
    import dos "../src"
    import ecs "../../ode_ecs/src"

///////////////////////////////////////////////////////////////////////////////
// State

    St_Health :: struct {
        current, max: int,
    }

    St_Status :: enum u8 {
        Dead,
        Unconscious,
        Alerted,
        Burning,
    }

    @(test)
    state__values__test :: proc(t: ^testing.T) {
        w: dos.World
        testing.expect(t, dos.world_init(&w, {max_objects = 16}) == nil)
        defer dos.world_terminate(&w)

        dos.archetype(&w, "Guard")
        obj, _ := dos.spawn(&w, "Guard")

        health, other: dos.State(St_Health)
        testing.expect(t, dos.state_init(&w, &health, "health") == nil)
        testing.expect(t, dos.state_init(&w, &other, "health") == dos.DOS_Error.Name_Already_Exists)

        testing.expect(t, !dos.has(&health, obj))
        testing.expect(t, dos.get(&health, obj) == nil)

        testing.expect(t, dos.add(&health, obj, St_Health{ current = 100, max = 100 }) == nil)
        testing.expect(t, dos.has(&health, obj))
        dos.get(&health, obj).current -= 10
        testing.expect_value(t, dos.get(&health, obj).current, 90)

        // add overwrites
        testing.expect(t, dos.add(&health, obj, St_Health{ current = 5, max = 100 }) == nil)
        testing.expect_value(t, dos.get(&health, obj).current, 5)

        testing.expect(t, dos.remove(&health, obj) == nil)
        testing.expect(t, !dos.has(&health, obj))
    }

    @(test)
    state__flags__test :: proc(t: ^testing.T) {
        w: dos.World
        testing.expect(t, dos.world_init(&w, {max_objects = 16}) == nil)
        defer dos.world_terminate(&w)

        dos.archetype(&w, "Guard")
        a, _ := dos.spawn(&w, "Guard")
        b, _ := dos.spawn(&w, "Guard")

        health: dos.State(St_Health)
        status: dos.State_Flags(St_Status)
        testing.expect(t, dos.state_init(&w, &health, "health") == nil)
        testing.expect(t, dos.state_flags_init(&w, &status, "status") == nil)

        testing.expect(t, dos.set(&status, a, St_Status.Dead) == nil)
        testing.expect(t, dos.set(&status, a, St_Status.Alerted) == nil)
        testing.expect(t, dos.is_set(&status, a, St_Status.Dead))
        testing.expect(t, !dos.is_set(&status, a, St_Status.Burning))
        testing.expect(t, dos.flags_of(&status, a) == bit_set[St_Status]{.Dead, .Alerted})
        testing.expect(t, dos.unset(&status, a, St_Status.Dead) == nil)
        testing.expect(t, dos.flags_of(&status, a) == bit_set[St_Status]{.Alerted})
        testing.expect(t, dos.flags_of(&status, b) == bit_set[St_Status]{})

        // gameplay views mix State tables and flag terms
        dos.add(&health, a, St_Health{ current = 1, max = 1 })
        dos.add(&health, b, St_Health{ current = 1, max = 1 })

        alerted: ecs.View
        testing.expect(t, ecs.view_init(&alerted, dos.runtime(&w), {dos.table(&health), ecs.flags_term(dos.table(&status), ecs.flags_of(St_Status.Alerted))}) == nil)
        testing.expect(t, ecs.rebuild(&alerted) == nil)
        testing.expect_value(t, ecs.view_len(&alerted), 1)

        testing.expect(t, dos.set(&status, b, St_Status.Alerted) == nil)
        testing.expect_value(t, ecs.view_len(&alerted), 2)
    }
