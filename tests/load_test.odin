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
        cfg:       dos.Config,
        mass:      dos.Property(Ld_Mass),
        max_hp:    dos.Property(Ld_Max_HP),
        air:       dos.Property(Ld_Air),
        vision:    dos.Property(Ld_Vision),
        sound:     dos.Property(Ld_Sound),
        level:     dos.Property(Ld_Level),
        transform: dos.Property(Ld_Transform),
        rope:      dos.Flag,
        status:    dos.State_Flags(Ld_Status),
        effects:   dos.Effects,
        contains:  dos.Link(Ld_Contains),
    }

    ld_setup :: proc(t: ^testing.T, g: ^Ld_Game) {
        cfg := &g.cfg
        testing.expect(t, dos.config_init(cfg, { keep_names = true, user_data = g }) == nil)
        testing.expect(t, dos.property_init(cfg, &g.mass, "mass") == nil)
        testing.expect(t, dos.property_init(cfg, &g.max_hp, "max-hit-points") == nil)
        testing.expect(t, dos.property_init(cfg, &g.air, "max-air-supply-ms") == nil)
        testing.expect(t, dos.property_init(cfg, &g.vision, "vision-range") == nil)
        testing.expect(t, dos.property_init(cfg, &g.sound, "footstep-sound") == nil)
        testing.expect(t, dos.property_init(cfg, &g.level, "level") == nil)
        testing.expect(t, dos.property_init(cfg, &g.transform, "transform") == nil)
        testing.expect(t, dos.flag_init(cfg, &g.rope, "can-attach-rope") == nil)
        testing.expect(t, dos.state_flags_init(cfg, &g.status, "status") == nil)
        testing.expect(t, dos.effects_init(cfg, &g.effects) == nil)
        testing.expect(t, dos.link_init(cfg, &g.contains, "Contains") == nil)
        _, err := dos.effect_register(&g.effects, "KnockedOut")
        testing.expect(t, err == nil)
    }

///////////////////////////////////////////////////////////////////////////////
// Loading

    @(test)
    load__ok__test :: proc(t: ^testing.T) {
        g: Ld_Game
        ld_setup(t, &g)
        defer dos.config_terminate(&g.cfg)
        cfg := &g.cfg

        err := dos.load(cfg, "data/ok")
        testing.expect(t, err == nil)
        for e in dos.errors(cfg) do log.error(dos.format_error(e, context.temp_allocator))
        if err != nil do return

        guard, _ := dos.find_archetype(cfg, "core.Guard")
        human, _ := dos.find_archetype(cfg, "core.Human")
        sword, _ := dos.find_archetype(cfg, "core.Sword")
        planks, _ := dos.find_surface(cfg, "core.WoodPlanks")

        testing.expect_value(t, dos.resolve(&g.mass, guard).value, 10)
        testing.expect_value(t, dos.resolve(&g.mass, sword).value, 2)
        testing.expect_value(t, dos.resolve(&g.vision, human).range, 20)
        testing.expect_value(t, dos.resolve(&g.vision, guard).range, 45) // the Alert meta, default priority 50
        testing.expect_value(t, dos.resolve(&g.air, guard).ms, 10000)
        testing.expect_value(t, dos.resolve(&g.max_hp, guard).value, 100)
        testing.expect_value(t, dos.resolve(&g.sound, planks).name, "wood")
        testing.expect(t, dos.resolve_flag(&g.rope, planks))
        testing.expect(t, !dos.resolve_flag(&g.rope, guard))

        g01, found := dos.find(cfg, "bafford.Guard01")
        testing.expect(t, found)
        s01, found2 := dos.find(cfg, "bafford.Sword01")
        testing.expect(t, found2)
        if !found || !found2 do return

        testing.expect(t, dos.archetype_of(cfg, g01) == guard)
        testing.expect_value(t, dos.resolve(&g.max_hp, g01).value, 75) // authored on the object
        testing.expect_value(t, dos.resolve(&g.transform, g01).position, [3]f32{ 10, 0, 4 })
        testing.expect(t, dos.is_state_flag(&g.status, g01, Ld_Status.Alerted))
        testing.expect_value(t, len(dos.objects(cfg)), 2)

        d, linked := dos.link_data(&g.contains, g01, s01)
        testing.expect(t, linked && d.slot == .Right_Hand)
    }

    @(test)
    load__reload__test :: proc(t: ^testing.T) {
        g: Ld_Game
        ld_setup(t, &g)
        defer dos.config_terminate(&g.cfg)
        cfg := &g.cfg

        testing.expect(t, dos.load(cfg, "data/reload_a") == nil)
        crate, _ := dos.find_archetype(cfg, "Crate")
        testing.expect_value(t, dos.resolve(&g.mass, crate).value, 5)
        c01, _ := dos.find(cfg, "Crate01")
        testing.expect_value(t, dos.resolve(&g.mass, c01).value, 5)

        // the same names again update in place; the objects are the same ones
        testing.expect(t, dos.load(cfg, "data/reload_b") == nil)
        testing.expect_value(t, dos.resolve(&g.mass, crate).value, 7)
        again, _ := dos.find(cfg, "Crate01")
        testing.expect(t, again == c01)
        testing.expect_value(t, len(dos.objects(cfg)), 1)

        // and the load says what it touched
        changed := dos.changed_objects(cfg)
        testing.expect_value(t, len(changed), 1)
        if len(changed) == 1 do testing.expect(t, changed[0] == c01)
        testing.expect_value(t, len(dos.changed_archetypes(cfg)), 1)
    }

    @(test)
    load__object_override_reload__test :: proc(t: ^testing.T) {
        g: Ld_Game
        ld_setup(t, &g)
        defer dos.config_terminate(&g.cfg)
        cfg := &g.cfg

        testing.expect(t, dos.load(cfg, "data/override_a") == nil)
        obj, _ := dos.find(cfg, "Crate01")
        testing.expect_value(t, dos.resolve(&g.mass, obj).value, 3)

        // a designer edits the object's own value and saves
        testing.expect(t, dos.load(cfg, "data/override_b") == nil)
        testing.expect_value(t, dos.resolve(&g.mass, obj).value, 9)
        _, src := dos.resolve_with_source(&g.mass, obj)
        testing.expect(t, src.kind == .Override)
    }

///////////////////////////////////////////////////////////////////////////////
// Diagnostics

    @(private = "file")
    ld_expect_failure :: proc(t: ^testing.T, file: string, contains: string, suggestion := "", loc := #caller_location) {
        g: Ld_Game
        ld_setup(t, &g)
        defer dos.config_terminate(&g.cfg)
        cfg := &g.cfg

        path := strings.concatenate({ "data/bad/", file }, context.temp_allocator)
        testing.expect(t, dos.load(cfg, path) == dos.DOS_Error.Load_Failed, loc = loc)

        errs := dos.errors(cfg)
        testing.expect(t, len(errs) > 0, loc = loc)
        if len(errs) == 0 do return

        testing.expectf(t, strings.contains(errs[0].message, contains), "%s: message %q lacks %q", file, errs[0].message, contains, loc = loc)
        if suggestion != "" do testing.expectf(t, errs[0].suggestion == suggestion, "%s: suggestion %q, expected %q", file, errs[0].suggestion, suggestion, loc = loc)

        // a failed load changes nothing
        _, created := dos.find_archetype(cfg, "A")
        testing.expect(t, !created, loc = loc)
    }

    @(test)
    load__diagnostics__test :: proc(t: ^testing.T) {
        ld_expect_failure(t, "unknown_parent.kdl", `unknown archetype "Humn"`, "Human")
        ld_expect_failure(t, "duplicate.kdl", "declared twice")
        ld_expect_failure(t, "unknown_config.kdl", `unknown value "masss"`, "mass")
        ld_expect_failure(t, "wrong_type.kdl", "expected a number")
        ld_expect_failure(t, "out_of_range.kdl", "out of range")
        ld_expect_failure(t, "cycle.kdl", "inheritance cycle")
        ld_expect_failure(t, "bad_enum.kdl", `unknown status flag "Sleeping"`)
        ld_expect_failure(t, "syntax.kdl", "KDL syntax error")
        ld_expect_failure(t, "unknown_top.kdl", `unknown node "archetyp"`, "archetype")
    }

    @(test)
    load__format_error__test :: proc(t: ^testing.T) {
        g: Ld_Game
        ld_setup(t, &g)
        defer dos.config_terminate(&g.cfg)

        testing.expect(t, dos.load(&g.cfg, "data/bad/unknown_parent.kdl") == dos.DOS_Error.Load_Failed)
        errs := dos.errors(&g.cfg)
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
