/*
    2026 (c) Oleh, https://github.com/zm69

    Tests for loading KDL: values, precedence, objects, links, diagnostics and hot reload.
*/
package ode_dos__tests

// Core
    import "core:log"
    import "core:strings"
    import "core:testing"

// ODE
    import dos "../src"

///////////////////////////////////////////////////////////////////////////////
// Setup

    Ld_Mass      :: struct { value: f32 }
    Ld_Max_HP    :: struct { value: int }
    Ld_Air       :: struct { ms: int }
    Ld_Vision    :: struct { range: f32 }
    Ld_Sound     :: struct { name: string }
    Ld_Level     :: struct { v: u8 }
    Ld_Transform :: struct { position: [3]f32 }
    Ld_Health    :: struct { current, max: int }

    Ld_Slot :: enum u8 {
        Left_Hand,
        Right_Hand,
    }

    Ld_Contains :: struct {
        slot: Ld_Slot,
    }

    Ld_Status :: enum u8 {
        Dead,
        Alerted,
    }

    Ld_Game :: struct {
        w:         dos.World,
        mass:      dos.Property(Ld_Mass),
        max_hp:    dos.Property(Ld_Max_HP),
        air:       dos.Property(Ld_Air),
        vision:    dos.Property(Ld_Vision),
        sound:     dos.Property(Ld_Sound),
        level:     dos.Property(Ld_Level),
        rope:      dos.Flag,
        transform: dos.State(Ld_Transform),
        health:    dos.State(Ld_Health),
        status:    dos.State_Flags(Ld_Status),
        contains:  dos.Link(Ld_Contains),
        spawned:   int,
    }

    ld_setup :: proc(t: ^testing.T, g: ^Ld_Game) {
        w := &g.w
        testing.expect(t, dos.world_init(w, {max_archetypes = 64, max_objects = 64, keep_names = true, user_data = g}) == nil)
        testing.expect(t, dos.property_init(w, &g.mass, "mass") == nil)
        testing.expect(t, dos.property_init(w, &g.max_hp, "max-hit-points", overridable = true) == nil)
        testing.expect(t, dos.property_init(w, &g.air, "max-air-supply-ms") == nil)
        testing.expect(t, dos.property_init(w, &g.vision, "vision-range") == nil)
        testing.expect(t, dos.property_init(w, &g.sound, "footstep-sound") == nil)
        testing.expect(t, dos.property_init(w, &g.level, "level") == nil)
        testing.expect(t, dos.flag_init(w, &g.rope, "can-attach-rope") == nil)
        testing.expect(t, dos.state_init(w, &g.transform, "transform") == nil)
        testing.expect(t, dos.state_init(w, &g.health, "health") == nil)
        testing.expect(t, dos.state_flags_init(w, &g.status, "status") == nil)
        testing.expect(t, dos.link_init(w, &g.contains, "Contains") == nil)

        testing.expect(t, dos.on_spawn(w, proc(w: ^dos.World, obj: dos.object_id) {
            g := cast(^Ld_Game) dos.user_data(w)
            g.spawned += 1
            if hp := dos.resolve(&g.max_hp, obj); hp != nil {
                dos.add(&g.health, obj, Ld_Health{ current = hp.value, max = hp.value })
            }
        }) == nil)
    }

///////////////////////////////////////////////////////////////////////////////
// Loading

    @(test)
    load__ok__test :: proc(t: ^testing.T) {
        g: Ld_Game
        ld_setup(t, &g)
        defer dos.world_terminate(&g.w)
        w := &g.w

        err := dos.load(w, "data/ok")
        testing.expect(t, err == nil)
        for e in dos.errors(w) do log.error(dos.format_error(e, context.temp_allocator))
        if err != nil do return

        guard, _ := dos.find_archetype(w, "core.Guard")
        human, _ := dos.find_archetype(w, "core.Human")
        sword, _ := dos.find_archetype(w, "core.Sword")
        planks, _ := dos.find_surface(w, "core.WoodPlanks")

        testing.expect_value(t, dos.resolve(&g.mass, guard).value, 10)
        testing.expect_value(t, dos.resolve(&g.mass, sword).value, 2)
        testing.expect_value(t, dos.resolve(&g.vision, human).range, 20)
        testing.expect_value(t, dos.resolve(&g.vision, guard).range, 45) // the Alert meta, default priority 50
        testing.expect_value(t, dos.resolve(&g.air, guard).ms, 10000)
        testing.expect_value(t, dos.resolve(&g.max_hp, guard).value, 100)
        testing.expect_value(t, dos.resolve(&g.sound, planks).name, "wood")
        testing.expect(t, dos.surface_flag(w, planks, &g.rope))
        testing.expect(t, !dos.resolve_flag(&g.rope, guard))

        g01, found := dos.find(w, "bafford.Guard01")
        testing.expect(t, found)
        s01, found2 := dos.find(w, "bafford.Sword01")
        testing.expect(t, found2)
        if !found || !found2 do return

        testing.expect(t, dos.archetype_of(w, g01) == guard)
        testing.expect_value(t, dos.resolve(&g.max_hp, g01).value, 75) // per-object override
        testing.expect_value(t, dos.get(&g.health, g01).current, 75)   // the spawn hook saw the override
        testing.expect_value(t, dos.get(&g.transform, g01).position, [3]f32{ 10, 0, 4 })
        testing.expect(t, dos.is_set(&g.status, g01, Ld_Status.Alerted))
        testing.expect_value(t, g.spawned, 2)

        d, linked := dos.link_data(&g.contains, g01, s01)
        testing.expect(t, linked && d.slot == .Right_Hand)
    }

    @(test)
    load__reload__test :: proc(t: ^testing.T) {
        g: Ld_Game
        ld_setup(t, &g)
        defer dos.world_terminate(&g.w)
        w := &g.w

        testing.expect(t, dos.load(w, "data/reload_a") == nil)
        crate, _ := dos.find_archetype(w, "Crate")
        testing.expect_value(t, dos.resolve(&g.mass, crate).value, 5)
        c01, _ := dos.find(w, "Crate01")

        // the same names again update in place; existing objects are kept
        testing.expect(t, dos.load(w, "data/reload_b") == nil)
        testing.expect_value(t, dos.resolve(&g.mass, crate).value, 7)
        again, _ := dos.find(w, "Crate01")
        testing.expect(t, again == c01)
        testing.expect_value(t, g.spawned, 1)
    }

///////////////////////////////////////////////////////////////////////////////
// Diagnostics

    @(private = "file")
    ld_expect_failure :: proc(t: ^testing.T, file: string, contains: string, suggestion := "", loc := #caller_location) {
        g: Ld_Game
        ld_setup(t, &g)
        defer dos.world_terminate(&g.w)
        w := &g.w

        path := strings.concatenate({ "data/bad/", file }, context.temp_allocator)
        testing.expect(t, dos.load(w, path) == dos.DOS_Error.Load_Failed, loc = loc)

        errs := dos.errors(w)
        testing.expect(t, len(errs) > 0, loc = loc)
        if len(errs) == 0 do return

        testing.expectf(t, strings.contains(errs[0].message, contains), "%s: message %q lacks %q", file, errs[0].message, contains, loc = loc)
        if suggestion != "" do testing.expectf(t, errs[0].suggestion == suggestion, "%s: suggestion %q, expected %q", file, errs[0].suggestion, suggestion, loc = loc)

        // a failed load changes nothing
        _, created := dos.find_archetype(w, "A")
        testing.expect(t, !created, loc = loc)
    }

    @(test)
    load__diagnostics__test :: proc(t: ^testing.T) {
        ld_expect_failure(t, "unknown_parent.kdl", `unknown archetype "Humn"`, "Human")
        ld_expect_failure(t, "duplicate.kdl", "declared twice")
        ld_expect_failure(t, "unknown_config.kdl", `unknown property "masss"`, "mass")
        ld_expect_failure(t, "wrong_type.kdl", "expected a number")
        ld_expect_failure(t, "out_of_range.kdl", "out of range")
        ld_expect_failure(t, "cycle.kdl", "inheritance cycle")
        ld_expect_failure(t, "bad_enum.kdl", `unknown status flag "Sleeping"`)
        ld_expect_failure(t, "syntax.kdl", "KDL syntax error")
        ld_expect_failure(t, "unknown_top.kdl", `unknown node "archetyp"`, "archetype")
        ld_expect_failure(t, "override_string.kdl", "is not overridable")
    }

    @(test)
    load__format_error__test :: proc(t: ^testing.T) {
        g: Ld_Game
        ld_setup(t, &g)
        defer dos.world_terminate(&g.w)

        testing.expect(t, dos.load(&g.w, "data/bad/unknown_parent.kdl") == dos.DOS_Error.Load_Failed)
        errs := dos.errors(&g.w)
        testing.expect_value(t, len(errs), 1)
        if len(errs) != 1 do return

        testing.expect_value(t, errs[0].line, 2)
        testing.expect_value(t, errs[0].column, 24)

        text := dos.format_error(errs[0], context.temp_allocator)
        testing.expectf(t, strings.contains(text, "unknown_parent.kdl:2:24"), "no location in:\n%s", text)
        testing.expectf(t, strings.contains(text, `archetype "EliteGuard" parent="Humn"`), "no source line in:\n%s", text)
        testing.expectf(t, strings.contains(text, "^^^^^^"), "no underline in:\n%s", text)
        testing.expectf(t, strings.contains(text, `did you mean "Human"?`), "no suggestion in:\n%s", text)
    }
