/*
    2026 (c) Oleh, https://github.com/zm69

    The Thief demo: load KDL, resolve inherited config, follow links, apply an effect, run a
    frame loop with plain ODE_ECS, then save and load the game.
*/
package thief_demo

// Core
    import "core:fmt"
    import "core:os"

// ODE
    import dos "../../src"
    import ecs "../../../ode_ecs/src"
    import game "../thief_game"

main :: proc() {
    g: game.Game
    if err := game.setup(&g); err != nil {
        fmt.eprintln("setup failed:", err)
        return
    }
    defer dos.world_terminate(&g.world)
    w := &g.world

    if dos.load(w, "../thief_game/data") != nil {
        for e in dos.errors(w) do fmt.eprintln(dos.format_error(e, context.temp_allocator))
        return
    }

    guard, found := dos.find(w, "bafford.Guard01")
    if !found do return
    out := os.to_stream(os.stdout)

    fmt.println("mass:", dos.resolve(&g.mass, guard).value)       // 10 from core.Physical
    fmt.println("health:", dos.get(&g.health, guard).current)     // 75, materialized at spawn from the override
    dos.explain(w, &g.vision, guard, out)                         // 45 from the core.Alert meta

    planks, _ := dos.find_surface(w, "core.WoodPlanks")
    fmt.println("rope sticks to planks:", dos.surface_flag(w, planks, &g.rope))

    it := dos.outgoing(&g.contains, guard)
    for target, data in dos.next(&it) {
        fmt.println("carrying", dos.name_of(w, target), "in", data.slot)
    }

    dos.apply(w, guard, "KnockedOut")
    fmt.println("unconscious:", dos.is_set(&g.status, guard, game.Status.Unconscious))

    // frame loop: plain ODE_ECS
    dos.add(&g.velocity, guard, game.Velocity{ v = { 1, 0, 0 } })
    moving: ecs.View
    if ecs.view_init(&moving, dos.runtime(w), {dos.table(&g.transform), dos.table(&g.velocity)}) != nil do return
    ecs.rebuild(&moving)

    for _ in 0..<3 {
        transforms := ecs.slice(&moving, game.Transform)
        velocities := ecs.slice(&moving, game.Velocity)
        for i in 0..<len(transforms) do transforms[i].position += velocities[i].v
    }
    fmt.println("position:", dos.get(&g.transform, guard).position)

    if err := dos.save_game(w, "out/save01.bin"); err != nil {
        fmt.eprintln("save failed:", err)
        return
    }
    dos.destroy(w, guard)
    if err := dos.load_game(w, "out/save01.bin"); err != nil {
        fmt.eprintln("load failed:", err)
        return
    }
    restored, _ := dos.find(w, "bafford.Guard01")
    fmt.println("after load:", dos.get(&g.transform, restored).position)
    fmt.println()
    dos.dump(w, restored, out)
}
