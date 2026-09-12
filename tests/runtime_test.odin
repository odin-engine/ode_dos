/*
    2026 (c) Oleh, https://github.com/zm69

    The game side: build a plain ODE_ECS world out of what Reflection describes, then save and
    load it with ODE_ECS. ODE_DOS never sees these entities.
*/
package ode_dos__tests

// Core
    import "core:os"
    import "core:testing"

// ODE
    import dos "../src"
    import ecs "../../ode_ecs/src"

///////////////////////////////////////////////////////////////////////////////
// Runtime

    Rt_Health :: struct { current, max: int }
    Rt_Position :: struct { v: [3]f32 }

    @(test)
    runtime__built_from_reflection__test :: proc(t: ^testing.T) {
        PATH :: "out/runtime_save.bin"
        defer os.remove(PATH)

        g: Ld_Game
        ld_setup(t, &g)
        defer dos.config_terminate(&g.cfg)
        testing.expect(t, dos.load(&g.cfg, "data/ok") == nil)

        // the game's own world
        db: ecs.Database
        defer ecs.terminate(&db)
        testing.expect(t, ecs.init(&db, 64) == nil)

        healths: ecs.Table(Rt_Health)
        positions: ecs.Table(Rt_Position)
        statuses: ecs.Flags_Table
        testing.expect(t, ecs.table_init(&healths, &db, 64) == nil)
        testing.expect(t, ecs.table_init(&positions, &db, 64) == nil)
        testing.expect(t, ecs.flags_table_init(&statuses, &db, 64) == nil)

        guard_entity: ecs.entity_id

        for obj in dos.objects(&g.cfg) {
            e, cerr := ecs.create_entity(&db)
            testing.expect(t, cerr == nil)

            if hp := dos.resolve(&g.max_hp, obj); hp != nil {
                c, _ := ecs.add_component(&healths, e)
                c^ = Rt_Health{ hp.value, hp.value }
            }
            if p := dos.resolve(&g.transform, obj); p != nil {
                c, _ := ecs.add_component(&positions, e)
                c^ = Rt_Position{ p.position }
            }
            testing.expect(t, ecs.set_flags(&statuses, e, dos.bits_of(&g.status, obj)) == nil)

            if dos.name_of(&g.cfg, obj) == "bafford.Guard01" do guard_entity = e
        }

        testing.expect(t, !ecs.is_expired(&db, guard_entity))
        h := ecs.get_component(&healths, guard_entity)
        testing.expect(t, h != nil && h.current == 75) // the object's own max-hit-points
        p := ecs.get_component(&positions, guard_entity)
        testing.expect(t, p != nil && p.v == [3]f32{ 10, 0, 4 })
        testing.expect(t, ecs.has_flag(&statuses, guard_entity, Ld_Status.Alerted))

        // saving is plain ODE_ECS
        testing.expect(t, ecs.save_to_file(&db, PATH) == nil)

        h.current = 5
        testing.expect(t, ecs.load_from_file(&db, PATH) == nil)
        h2 := ecs.get_component(&healths, guard_entity)
        testing.expect(t, h2 != nil && h2.current == 75)
    }
