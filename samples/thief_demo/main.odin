/*
    2026 (c) Oleh, https://github.com/zm69

    The Thief demo: load KDL, read what designers authored through Reflection, build a plain
    ODE_ECS world out of it, run a frame loop, and save that world with ODE_ECS.
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

    Health   :: struct { current, max: int }
    Position :: struct { v: [3]f32 }
    Velocity :: struct { v: [3]f32 }

    World :: struct {
        db:         ecs.Database,
        healths:    ecs.Table(Health),
        positions:  ecs.Table(Position),
        velocities: ecs.Table(Velocity),
        statuses:   ecs.Flags_Table,
        effects:    ecs.Flags_Table,
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

    fmt.println("mass:", dos.resolve(&g.mass, guard).value)         // 10 from core.Physical
    fmt.println("hit points:", dos.resolve(&g.max_hp, guard).value) // 75, the object's own value
    dos.explain(cfg, &g.vision, guard, out)                           // 45 from the core.Alert meta

    planks, _ := dos.find_surface(cfg, "core.WoodPlanks")
    fmt.println("rope sticks to planks:", dos.resolve_flag(&g.rope, planks))

    it := dos.links_of(&g.contains, guard)
    for target, data in dos.next(&it) {
        fmt.println("carrying", dos.name_of(cfg, target), "in", data.slot)
    }

    // build the running game out of what the designers authored
    w: World
    defer world_terminate(&w)
    if build(&w, &g) != nil {
        fmt.eprintln("cannot build the world")
        return
    }

    e := w.of_object[guard]
    fmt.println("health:", ecs.get_component(&w.healths, e).current)
    fmt.println("unconscious:", ecs.has_flag(&w.statuses, e, game.Status.Unconscious))

    // frame loop: plain ODE_ECS
    c, _ := ecs.add_component(&w.velocities, e)
    c^ = Velocity{ v = { 1, 0, 0 } }

    moving: ecs.View
    if ecs.view_init(&moving, &w.db, {&w.positions, &w.velocities}) != nil do return
    ecs.rebuild(&moving)

    for _ in 0..<3 {
        positions := ecs.slice(&moving, Position)
        velocities := ecs.slice(&moving, Velocity)
        for i in 0..<len(positions) do positions[i].v += velocities[i].v
    }
    fmt.println("position:", ecs.get_component(&w.positions, e).v)

    // saving the game is plain ODE_ECS too
    if err := ecs.save_to_file(&w.db, "out/save01.bin"); err != nil {
        fmt.eprintln("save failed:", err)
        return
    }
    ecs.get_component(&w.positions, e).v = {}
    if err := ecs.load_from_file(&w.db, "out/save01.bin"); err != nil {
        fmt.eprintln("load failed:", err)
        return
    }
    fmt.println("after load:", ecs.get_component(&w.positions, e).v)

    fmt.println()
    dos.dump(cfg, guard, out)
}

///////////////////////////////////////////////////////////////////////////////
// Building the runtime from Reflection

build :: proc(w: ^World, g: ^game.Game) -> ecs.Error {
    ecs.init(&w.db, 4096) or_return
    ecs.table_init(&w.healths, &w.db, 4096) or_return
    ecs.table_init(&w.positions, &w.db, 4096) or_return
    ecs.table_init(&w.velocities, &w.db, 4096) or_return
    ecs.flags_table_init(&w.statuses, &w.db, 4096) or_return
    ecs.flags_table_init(&w.effects, &w.db, 4096) or_return
    w.of_object = make(map[dos.object_id]ecs.entity_id)

    for obj in dos.objects(&g.cfg) {
        e := ecs.create_entity(&w.db) or_return
        w.of_object[obj] = e

        if hp := dos.resolve(&g.max_hp, obj); hp != nil {
            c := ecs.add_component(&w.healths, e) or_return
            c^ = Health{ current = hp.value, max = hp.value }
        }
        if p := dos.resolve(&g.transform, obj); p != nil {
            c := ecs.add_component(&w.positions, e) or_return
            c^ = Position{ v = p.position }
        }
        ecs.set_flags(&w.statuses, e, dos.bits_of(&g.status, obj)) or_return
        ecs.set_flags(&w.effects, e, dos.bits_of(&g.effects, obj)) or_return
    }
    return nil
}

world_terminate :: proc(w: ^World) {
    delete(w.of_object)
    ecs.terminate(&w.db)
}
