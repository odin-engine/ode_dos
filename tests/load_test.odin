/*
    2026 (c) Oleh, https://github.com/zm69

    Tests for loading KDL: values with their inheritance, objects, links, hot reload and
    diagnostics.
*/
package ode_dos__tests

// Core
    import "core:log"
    import "core:strings"
    import "core:testing"

// ODE
    import dos "../src"

///////////////////////////////////////////////////////////////////////////////
// Types the tests read values into

    Ld_Transform :: struct { position: [3]f32 }

    Ld_Slot :: enum u8 {
        Left_Hand,
        Right_Hand,
    }

    Ld_Contains :: struct {
        slot: Ld_Slot,
    }

    ld_float :: proc(t: ^testing.T, cfg: ^dos.Config, id: $I, name: string, loc := #caller_location) -> f64 {
        v, has := dos.value(cfg, id, name)
        testing.expectf(t, has, "%s is not set", name, loc = loc)
        if !has do return 0

        f, ok := dos.as_float(v)
        testing.expectf(t, ok, "%s is not a number", name, loc = loc)
        return f
    }

///////////////////////////////////////////////////////////////////////////////
// Loading

    @(test)
    load__ok__test :: proc(t: ^testing.T) {
        cfg: dos.Config
        testing.expect(t, dos.config_init(&cfg) == nil)
        defer dos.config_terminate(&cfg)

        err := dos.load(&cfg, "data/ok")
        testing.expect(t, err == nil)
        for e in dos.errors(&cfg) do log.error(dos.format_error(e, context.temp_allocator))
        if err != nil do return

        guard, _ := dos.find_archetype(&cfg, "core.Guard")
        human, _ := dos.find_archetype(&cfg, "core.Human")
        sword, _ := dos.find_archetype(&cfg, "core.Sword")
        planks, _ := dos.find_surface(&cfg, "core.WoodPlanks")

        testing.expect_value(t, ld_float(t, &cfg, guard, "mass"), 10)          // core.Physical
        testing.expect_value(t, ld_float(t, &cfg, sword, "mass"), 2)
        testing.expect_value(t, ld_float(t, &cfg, human, "vision-range"), 20)
        testing.expect_value(t, ld_float(t, &cfg, guard, "vision-range"), 45)  // the Alert meta
        testing.expect_value(t, ld_float(t, &cfg, guard, "max-air-supply-ms"), 10000)
        testing.expect_value(t, ld_float(t, &cfg, guard, "max-hit-points"), 100)

        // a flag is a name with no argument
        testing.expect(t, dos.has(&cfg, planks, "can-attach-rope"))
        testing.expect(t, !dos.has(&cfg, guard, "can-attach-rope"))
        sound, _ := dos.value(&cfg, planks, "footstep-sound")
        s, _ := dos.as_string(sound)
        testing.expect_value(t, s, "wood")

        g01, found := dos.find(&cfg, "bafford.Guard01")
        testing.expect(t, found)
        s01, found2 := dos.find(&cfg, "bafford.Sword01")
        testing.expect(t, found2)
        if !found || !found2 do return

        testing.expect(t, dos.archetype_of(&cfg, g01) == guard)
        testing.expect_value(t, ld_float(t, &cfg, g01, "max-hit-points"), 75) // authored on the object
        testing.expect_value(t, ld_float(t, &cfg, g01, "mass"), 10)           // still inherited
        testing.expect(t, dos.has(&cfg, g01, "knocked-out"))

        // a name with several arguments is a list
        status := dos.args(&cfg, g01, "status")
        testing.expect_value(t, len(status), 2)
        if len(status) == 2 {
            a, _ := dos.as_string(status[0])
            b, _ := dos.as_string(status[1])
            testing.expect_value(t, a, "Alerted")
            testing.expect_value(t, b, "Dead")
        }

        // and a node with children fills a struct
        transform: Ld_Transform
        testing.expect(t, dos.read(&cfg, g01, "transform", &transform))
        testing.expect_value(t, transform.position, [3]f32{ 10, 0, 4 })

        // where each value came from
        testing.expect(t, dos.source_of(&cfg, g01, "max-hit-points").kind == .Override)
        mass_src := dos.source_of(&cfg, g01, "mass")
        testing.expect(t, mass_src.kind == .Authored)
        testing.expect_value(t, dos.source_name(&cfg, mass_src), "core.Physical")
        vision_src := dos.source_of(&cfg, g01, "vision-range")
        testing.expect(t, vision_src.kind == .Meta)
        testing.expect_value(t, dos.source_name(&cfg, vision_src), "core.Alert")

        links := dos.links_of(&cfg, g01)
        testing.expect_value(t, len(links), 1)
        if len(links) == 1 {
            testing.expect_value(t, links[0].flavor, "Contains")
            testing.expect(t, links[0].to == s01)

            data: Ld_Contains
            testing.expect(t, dos.read_node(&cfg, links[0].data, &data))
            testing.expect(t, data.slot == .Right_Hand)
        }

        testing.expect_value(t, len(dos.objects(&cfg)), 2)
    }

    @(test)
    load__reload__test :: proc(t: ^testing.T) {
        cfg: dos.Config
        testing.expect(t, dos.config_init(&cfg) == nil)
        defer dos.config_terminate(&cfg)

        testing.expect(t, dos.load(&cfg, "data/reload_a") == nil)
        crate, _ := dos.find_archetype(&cfg, "Crate")
        c01, _ := dos.find(&cfg, "Crate01")
        testing.expect_value(t, ld_float(t, &cfg, crate, "mass"), 5)
        testing.expect_value(t, ld_float(t, &cfg, c01, "mass"), 3)

        // the same names again update in place; the objects are the same ones
        testing.expect(t, dos.load(&cfg, "data/reload_b") == nil)
        again, _ := dos.find(&cfg, "Crate01")
        testing.expect(t, again == c01)
        testing.expect_value(t, ld_float(t, &cfg, crate, "mass"), 7)
        testing.expect_value(t, ld_float(t, &cfg, c01, "mass"), 9)
        testing.expect(t, dos.source_of(&cfg, c01, "mass").kind == .Override)
        testing.expect_value(t, len(dos.objects(&cfg)), 1)

        // and the load says what it touched
        changed := dos.changed_objects(&cfg)
        testing.expect_value(t, len(changed), 1)
        if len(changed) == 1 do testing.expect(t, changed[0] == c01)
        testing.expect_value(t, len(dos.changed_archetypes(&cfg)), 1)
    }

    @(test)
    load__adds_to_what_is_there__test :: proc(t: ^testing.T) {
        cfg: dos.Config
        testing.expect(t, dos.config_init(&cfg) == nil)
        defer dos.config_terminate(&cfg)

        testing.expect(t, dos.load(&cfg, "data/ok") == nil)
        guard, _ := dos.find_archetype(&cfg, "core.Guard")
        g01, _ := dos.find(&cfg, "bafford.Guard01")

        testing.expect(t, dos.load(&cfg, "data/grow") == nil)
        archer, ok := dos.find_archetype(&cfg, "core.Archer")
        testing.expect(t, ok)
        testing.expect_value(t, ld_float(t, &cfg, archer, "vision-range"), 45) // its own Alert meta

        // what was already there is untouched
        again, _ := dos.find_archetype(&cfg, "core.Guard")
        testing.expect(t, again == guard)
        testing.expect(t, dos.archetype_of(&cfg, g01) == guard)
        testing.expect_value(t, ld_float(t, &cfg, g01, "max-hit-points"), 75)
    }

///////////////////////////////////////////////////////////////////////////////
// Diagnostics

    @(private = "file")
    ld_expect_failure :: proc(t: ^testing.T, file: string, contains: string, suggestion := "", loc := #caller_location) {
        cfg: dos.Config
        testing.expect(t, dos.config_init(&cfg) == nil, loc = loc)
        defer dos.config_terminate(&cfg)

        path := strings.concatenate({ "data/bad/", file }, context.temp_allocator)
        testing.expect(t, dos.load(&cfg, path) == dos.DOS_Error.Load_Failed, loc = loc)

        errs := dos.errors(&cfg)
        testing.expect(t, len(errs) > 0, loc = loc)
        if len(errs) == 0 do return

        testing.expectf(t, strings.contains(errs[0].message, contains), "%s: message %q lacks %q", file, errs[0].message, contains, loc = loc)
        if suggestion != "" do testing.expectf(t, errs[0].suggestion == suggestion, "%s: suggestion %q, expected %q", file, errs[0].suggestion, suggestion, loc = loc)

        // a failed load changes nothing
        _, created := dos.find_archetype(&cfg, "A")
        testing.expect(t, !created, loc = loc)
    }

    @(test)
    load__diagnostics__test :: proc(t: ^testing.T) {
        ld_expect_failure(t, "unknown_parent.kdl", `unknown archetype "Humn"`, "Human")
        ld_expect_failure(t, "duplicate.kdl", "declared twice")
        ld_expect_failure(t, "cycle.kdl", "inheritance cycle")
        ld_expect_failure(t, "syntax.kdl", "KDL syntax error")
        ld_expect_failure(t, "unknown_top.kdl", `unknown node "archetyp"`, "archetype")
        ld_expect_failure(t, "no_archetype.kdl", `needs archetype="Name"`)
        ld_expect_failure(t, "unknown_object.kdl", `unknown object "Nobody"`)
        ld_expect_failure(t, "meta_on_meta.kdl", "a meta cannot carry metas")
    }

    @(test)
    load__format_error__test :: proc(t: ^testing.T) {
        cfg: dos.Config
        testing.expect(t, dos.config_init(&cfg) == nil)
        defer dos.config_terminate(&cfg)

        testing.expect(t, dos.load(&cfg, "data/bad/unknown_parent.kdl") == dos.DOS_Error.Load_Failed)
        errs := dos.errors(&cfg)
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
