/*
    2026 (c) Oleh, https://github.com/zm69

    Sample01 - the README example, ready to run:

        cd samples/sample01 && odin run .

    It loads data/world.kdl, builds a plain ODE_ECS world out of what the file says, and prints
    where one value came from. Edit the .kdl and run it again - no Odin changes needed.
*/
package sample01

import "core:fmt"
import "core:os"

import dos "../../src"
import ecs "../../../ode_ecs/src"

Transform :: struct { position: [3]f32 }
Health    :: struct { current, max: int }
Of_Config :: struct { obj: dos.object_id }   // what this entity was built from

Game :: struct {
    cfg:       dos.Config,       // what designers author

    db:        ecs.Database,     // the running game: yours, plain ODE_ECS
    positions: ecs.Table(Transform),
    healths:   ecs.Table(Health),
    sources:   ecs.Table(Of_Config),
}

main :: proc() {
    g: Game
    defer dos.config_terminate(&g.cfg)
    defer ecs.terminate(&g.db)

    if err := dos.config_init(&g.cfg); err != nil {
        fmt.eprintln("cannot start:", err)
        return
    }

    if dos.load(&g.cfg, "data") != nil {          // archetypes, metas, surfaces, objects; bakes
        for e in dos.errors(&g.cfg) do fmt.eprintln(dos.format_error(e, context.temp_allocator))
        return
    }

    if err := build(&g); err != nil {
        fmt.eprintln("cannot build the world:", err)
        return
    }

    // what the build produced, straight out of your own tables
    entities := ecs.entities_slice(&g.sources)
    for src, i in ecs.slice(&g.sources) {
        hp := ecs.get_component(&g.healths, entities[i])
        fmt.printfln("%s: %d hp", dos.name_of(&g.cfg, src.obj), hp.current)
    }

    guard01, _ := dos.find(&g.cfg, "Guard01")
    dos.explain(&g.cfg, guard01, "mass", os.to_stream(os.stdout))   // mass = 10  [from Physical]

    // once everything has been read, whatever is left is probably a typo
    for e in dos.unread(&g.cfg) do fmt.eprintln(dos.format_error(e, context.temp_allocator))
}

// your runtime, built from what the files say
build :: proc(g: ^Game) -> ecs.Error {
    ecs.init(&g.db, 4096) or_return
    ecs.table_init(&g.positions, &g.db, 4096) or_return
    ecs.table_init(&g.healths, &g.db, 4096) or_return
    ecs.table_init(&g.sources, &g.db, 4096) or_return

    for obj in dos.objects(&g.cfg) {
        e := ecs.create_entity(&g.db) or_return

        src := ecs.add_component(&g.sources, e) or_return
        src^ = Of_Config{ obj }

        transform: Transform
        if dos.read(&g.cfg, obj, "transform", &transform) {
            c := ecs.add_component(&g.positions, e) or_return
            c^ = transform
        }

        if v, has := dos.value(&g.cfg, obj, "max-hit-points"); has {
            hp, _ := dos.as_int(v)                        // 75 for Guard01, 100 for the rest
            c := ecs.add_component(&g.healths, e) or_return
            c^ = Health{ current = int(hp), max = int(hp) }
        }
    }
    return nil
}

