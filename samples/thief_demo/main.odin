/*
    2026 (c) Oleh, https://github.com/zm69

    The Thief demo: load KDL, read what designers authored, build a plain ODE_ECS world out of it,
    run a frame loop, and save that world with ODE_ECS.
*/
package thief_demo

// Core
    import "core:fmt"
    import "core:os"

// ODE
    import dos "../../src"
    import ecs "../../../ode_ecs/src"
    import game "../thief_game"

///////////////////////////////////////////////////////////////////////////////
// The game's own runtime, which ODE_DOS never touches

    Of_Config :: struct { obj: dos.object_id } // what this entity was built from

    World :: struct {
        db:         ecs.Database,
        healths:    ecs.Table(game.Health),
        masses:     ecs.Table(game.Mass),
        positions:  ecs.Table(game.Transform),
        velocities: ecs.Table(game.Velocity),
        sources:    ecs.Table(Of_Config),
        statuses:   ecs.Flags_Table,
        of_object:  map[dos.object_id]ecs.entity_id,
    }

main :: proc() {
    g: game.Game
    if err := game.setup(&g); err != nil {
        fmt.eprintln("setup failed:", err)
        return
    }
    defer dos.config_terminate(&g.cfg)
    cfg := &g.cfg

    if dos.load(cfg, "../thief_game/data") != nil {
        for e in dos.errors(cfg) do fmt.eprintln(dos.format_error(e, context.temp_allocator))
        return
    }

    out := os.to_stream(os.stdout)
    guard, found := dos.find(cfg, "bafford.Guard01")
    if !found do return

    // what the designers said about this object
    mass, _ := dos.value(cfg, guard, "mass")
    m, _ := dos.as_float(mass)
    fmt.println("mass:", m)                      // 10, inherited from core.Physical
    dos.explain(cfg, guard, "vision-range", out) // 45, from the core.Alert meta

    planks, _ := dos.find_surface(cfg, "core.WoodPlanks")
    fmt.println("rope sticks to planks:", dos.has(cfg, planks, "can-attach-rope"))
    if sound, has := dos.value(cfg, planks, "footstep-sound"); has {
        name, _ := dos.as_string(sound)
        fmt.println("footsteps on planks:", name)
    }

    for l in dos.links_of(cfg, guard) {
        data: game.Contains
        dos.read_node(cfg, l.data, &data)
        fmt.println("carrying", dos.name_of(cfg, l.to), "in", data.slot)
    }

    // build the running game out of it
    w: World
    defer world_terminate(&w)
    if build(&w, cfg) != nil {
        fmt.eprintln("cannot build the world")
        return
    }

    // anything the files author but nothing reads is probably a typo
    for e in dos.unread(cfg) do fmt.eprintln("unused:", dos.format_error(e, context.temp_allocator))

    e := w.of_object[guard]
    fmt.println("health:", ecs.get_component(&w.healths, e).current)
    fmt.println("unconscious:", ecs.has_flag(&w.statuses, e, game.Status.Unconscious))

    // frame loop: plain ODE_ECS
    c, _ := ecs.add_component(&w.velocities, e)
    c^ = game.Velocity{ v = { 1, 0, 0 } }

    moving: ecs.View
    if ecs.view_init(&moving, &w.db, {&w.positions, &w.velocities}) != nil do return
    ecs.rebuild(&moving)

    for _ in 0..<3 {
        positions := ecs.slice(&moving, game.Transform)
        velocities := ecs.slice(&moving, game.Velocity)
        for i in 0..<len(positions) do positions[i].position += velocities[i].v
    }
    fmt.println("position:", ecs.get_component(&w.positions, e).position)

    // saving the game is plain ODE_ECS too
    if err := ecs.save_to_file(&w.db, "out/save01.bin"); err != nil {
        fmt.eprintln("save failed:", err)
        return
    }
    ecs.get_component(&w.positions, e).position = {}
    if err := ecs.load_from_file(&w.db, "out/save01.bin"); err != nil {
        fmt.eprintln("load failed:", err)
        return
    }
    fmt.println("after load:", ecs.get_component(&w.positions, e).position)

    fmt.println()
    dos.dump(cfg, guard, out)
}

///////////////////////////////////////////////////////////////////////////////
// Building the runtime from what the Config describes

build :: proc(w: ^World, cfg: ^dos.Config) -> ecs.Error {
    ecs.init(&w.db, 4096) or_return
    ecs.table_init(&w.healths, &w.db, 4096) or_return
    ecs.table_init(&w.masses, &w.db, 4096) or_return
    ecs.table_init(&w.positions, &w.db, 4096) or_return
    ecs.table_init(&w.velocities, &w.db, 4096) or_return
    ecs.table_init(&w.sources, &w.db, 4096) or_return
    ecs.flags_table_init(&w.statuses, &w.db, 4096) or_return
    w.of_object = make(map[dos.object_id]ecs.entity_id)

    for obj in dos.objects(cfg) {
        e := ecs.create_entity(&w.db) or_return
        w.of_object[obj] = e

        src := ecs.add_component(&w.sources, e) or_return
        src^ = Of_Config{ obj }

        if v, has := dos.value(cfg, obj, "max-hit-points"); has {
            hp, _ := dos.as_int(v)
            c := ecs.add_component(&w.healths, e) or_return
            c^ = game.Health{ current = int(hp), max = int(hp) }
        }

        mass: game.Mass
        if dos.read(cfg, obj, "mass", &mass) {
            c := ecs.add_component(&w.masses, e) or_return
            c^ = mass
        }

        transform: game.Transform
        if dos.read(cfg, obj, "transform", &transform) {
            c := ecs.add_component(&w.positions, e) or_return
            c^ = transform
        }

        for a in dos.args(cfg, obj, "status") {
            name, _ := dos.as_string(a)
            for v in game.Status {
                if name == status_name(v) do ecs.flag(&w.statuses, e, v) or_return
            }
        }
    }
    return nil
}

status_name :: proc(v: game.Status) -> string {
    switch v {
    case .Dead:        return "Dead"
    case .Unconscious: return "Unconscious"
    case .Alerted:     return "Alerted"
    case .Burning:     return "Burning"
    }
    return ""
}

world_terminate :: proc(w: ^World) {
    delete(w.of_object)
    ecs.terminate(&w.db)
}
