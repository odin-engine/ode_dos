/*
    2026 (c) Oleh, https://github.com/zm69

    The game side: build a plain ODE_ECS world out of what a Config describes, then save and load
    it with ODE_ECS. ODE_DOS never sees these entities.
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

    Rt_Health   :: struct { current, max: int }
    Rt_Position :: struct { v: [3]f32 }
    Rt_Of_Config :: struct { obj: dos.object_id } // what this entity was built from

    Rt_Status :: enum u8 {
        Dead,
        Alerted,
    }

    @(test)
    runtime__built_from_config__test :: proc(t: ^testing.T) {
        PATH :: "out/runtime_save.bin"
        defer os.remove(PATH)

        cfg: dos.Config
        testing.expect(t, dos.config_init(&cfg) == nil)
        defer dos.config_terminate(&cfg)
        testing.expect(t, dos.load(&cfg, "data/ok") == nil)

        // the game's own world
        db: ecs.Database
        defer ecs.terminate(&db)
        testing.expect(t, ecs.init(&db, 64) == nil)

        healths: ecs.Table(Rt_Health)
        positions: ecs.Table(Rt_Position)
        sources: ecs.Table(Rt_Of_Config)
        statuses: ecs.Flags_Table
        testing.expect(t, ecs.table_init(&healths, &db, 64) == nil)
        testing.expect(t, ecs.table_init(&positions, &db, 64) == nil)
        testing.expect(t, ecs.table_init(&sources, &db, 64) == nil)
        testing.expect(t, ecs.flags_table_init(&statuses, &db, 64) == nil)

        guard_entity: ecs.entity_id

        for obj in dos.objects(&cfg) {
            e, cerr := ecs.create_entity(&db)
            testing.expect(t, cerr == nil)

            src, _ := ecs.add_component(&sources, e)
            src^ = Rt_Of_Config{ obj }   // the link back into config space

            if v, has := dos.value(&cfg, obj, "max-hit-points"); has {
                hp, _ := dos.as_int(v)
                c, _ := ecs.add_component(&healths, e)
                c^ = Rt_Health{ int(hp), int(hp) }
            }

            transform: Ld_Transform
            if dos.read(&cfg, obj, "transform", &transform) {
                c, _ := ecs.add_component(&positions, e)
                c^ = Rt_Position{ transform.position }
            }

            for a in dos.args(&cfg, obj, "status") {
                name, _ := dos.as_string(a)
                for v in Rt_Status {
                    if name == rt_status_name(v) do ecs.flag(&statuses, e, v)
                }
            }

            if dos.name_of(&cfg, obj) == "bafford.Guard01" do guard_entity = e
        }

        testing.expect(t, !ecs.is_expired(&db, guard_entity))
        h := ecs.get_component(&healths, guard_entity)
        testing.expect(t, h != nil && h.current == 75) // the object's own value
        p := ecs.get_component(&positions, guard_entity)
        testing.expect(t, p != nil && p.v == [3]f32{ 10, 0, 4 })
        testing.expect(t, ecs.has_flag(&statuses, guard_entity, Rt_Status.Alerted))
        testing.expect(t, ecs.has_flag(&statuses, guard_entity, Rt_Status.Dead))

        // the entity remembers what it was built from
        back := ecs.get_component(&sources, guard_entity)
        testing.expect(t, back != nil)
        if back != nil do testing.expect_value(t, dos.name_of(&cfg, back.obj), "bafford.Guard01")

        // saving is plain ODE_ECS
        testing.expect(t, ecs.save_to_file(&db, PATH) == nil)
        h.current = 5
        testing.expect(t, ecs.load_from_file(&db, PATH) == nil)
        h2 := ecs.get_component(&healths, guard_entity)
        testing.expect(t, h2 != nil && h2.current == 75)
    }

    @(private = "file")
    rt_status_name :: proc(v: Rt_Status) -> string {
        switch v {
        case .Dead:    return "Dead"
        case .Alerted: return "Alerted"
        }
        return ""
    }
