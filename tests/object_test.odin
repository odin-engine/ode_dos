/*
    2026 (c) Oleh, https://github.com/zm69

    Tests for objects: spawning, spawn hooks, names and destruction.
*/
package ode_dos__tests

// Core
    import "core:testing"

// ODE
    import dos "../src"
    import ecs "../../ode_ecs/src"

///////////////////////////////////////////////////////////////////////////////
// Objects

    Obj_Health :: struct {
        current, max: int,
    }

    Obj_Ctx :: struct {
        health: ^dos.State(Obj_Health),
        spawned: int,
    }

    @(test)
    object__spawn_destroy__test :: proc(t: ^testing.T) {
        ctx: Obj_Ctx
        w: dos.World
        testing.expect(t, dos.world_init(&w, {max_archetypes = 32, max_objects = 16, keep_names = true, user_data = &ctx}) == nil)
        defer dos.world_terminate(&w)

        health: dos.State(Obj_Health)
        testing.expect(t, dos.state_init(&w, &health, "health") == nil)
        ctx.health = &health

        guard, _ := dos.archetype(&w, "Guard")
        wooden, _ := dos.meta(&w, "Wooden")

        testing.expect(t, dos.on_spawn(&w, proc(w: ^dos.World, obj: dos.object_id) {
            ctx := cast(^Obj_Ctx) dos.user_data(w)
            ctx.spawned += 1
            dos.add(ctx.health, obj, Obj_Health{ current = 100, max = 100 })
        }) == nil)

        g1, err := dos.spawn(&w, "Guard")
        testing.expect(t, err == nil)
        g2, err2 := dos.spawn(&w, guard)
        testing.expect(t, err2 == nil && g2 != g1)
        testing.expect_value(t, ctx.spawned, 2)

        testing.expect(t, dos.alive(&w, g1))
        testing.expect(t, dos.archetype_of(&w, g1) == guard)
        testing.expect(t, dos.get(&health, g1) != nil && dos.get(&health, g1).current == 100)

        _, missing := dos.spawn(&w, "Nope")
        testing.expect(t, missing == dos.DOS_Error.Name_Not_Found)
        _, wrong := dos.spawn(&w, dos.archetype_id(wooden))
        testing.expect(t, wrong == dos.DOS_Error.Wrong_Kind)

        testing.expect(t, dos.destroy(&w, g1) == nil)
        testing.expect(t, !dos.alive(&w, g1))
        testing.expect(t, dos.destroy(&w, g1) == ecs.API_Error.Entity_Id_Expired)
        testing.expect(t, dos.alive(&w, g2))
    }

    @(test)
    object__names__test :: proc(t: ^testing.T) {
        w: dos.World
        testing.expect(t, dos.world_init(&w, {max_archetypes = 32, max_objects = 16, keep_names = true}) == nil)
        defer dos.world_terminate(&w)

        dos.archetype(&w, "Guard")
        g1, _ := dos.spawn(&w, "Guard")
        g2, _ := dos.spawn(&w, "Guard")

        testing.expect(t, dos.set_name(&w, g1, "Guard01") == nil)
        found, ok := dos.find(&w, "Guard01")
        testing.expect(t, ok && found == g1)
        testing.expect_value(t, dos.name_of(&w, g1), "Guard01")
        testing.expect_value(t, dos.name_of(&w, g2), "")

        // object and archetype names are separate namespaces
        testing.expect(t, dos.set_name(&w, g2, "Guard") == nil)
        testing.expect_value(t, dos.name_of(&w, g2), "Guard")
        a, _ := dos.find_archetype(&w, "Guard")
        testing.expect_value(t, dos.name_of(&w, a), "Guard")

        testing.expect(t, dos.set_name(&w, g2, "Guard01") == dos.DOS_Error.Name_Already_Exists)

        // renaming releases the old name
        testing.expect(t, dos.set_name(&w, g1, "Captain") == nil)
        _, ok = dos.find(&w, "Guard01")
        testing.expect(t, !ok)

        // destroying releases the name
        testing.expect(t, dos.destroy(&w, g1) == nil)
        _, ok = dos.find(&w, "Captain")
        testing.expect(t, !ok)
        testing.expect(t, dos.set_name(&w, g2, "Captain") == nil)
    }
