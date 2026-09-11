/*
    2026 (c) Oleh, https://github.com/zm69

    Tests for inspecting objects and for the command-line tooling.
*/
package ode_dos__tests

// Core
    import "core:os"
    import "core:strings"
    import "core:testing"

// ODE
    import dos "../src"
    import game "../samples/thief_game"

///////////////////////////////////////////////////////////////////////////////
// Inspect

    @(test)
    inspect__dump__test :: proc(t: ^testing.T) {
        g: Ld_Game
        ld_setup(t, &g)
        defer dos.world_terminate(&g.w)

        testing.expect(t, dos.load(&g.w, "data/ok") == nil)
        g01, found := dos.find(&g.w, "bafford.Guard01")
        testing.expect(t, found)
        if !found do return

        b := strings.builder_make(context.temp_allocator)
        dos.dump(&g.w, g01, strings.to_writer(&b))
        text := strings.to_string(b)

        for want in ([]string{
            "Object: bafford.Guard01",
            "archetype: core.Guard",
            "Chain:  core.Guard → core.Human → core.Creature → core.Physical",
            "Metas:  core.Alert (priority 50)",
            "[core.Physical]",
            "[override]",
            "[core.Alert]",
            "Alerted",
            "Contains → bafford.Sword01  (Right_Hand)",
        }) {
            testing.expectf(t, strings.contains(text, want), "dump lacks %q:\n%s", want, text)
        }
    }

    @(test)
    inspect__explain_and_cli__test :: proc(t: ^testing.T) {
        g: Ld_Game
        ld_setup(t, &g)
        defer dos.world_terminate(&g.w)

        testing.expect(t, dos.load(&g.w, "data/ok") == nil)
        g01, _ := dos.find(&g.w, "bafford.Guard01")

        b := strings.builder_make(context.temp_allocator)
        out := strings.to_writer(&b)

        dos.explain(&g.w, &g.vision, g01, out)
        testing.expect_value(t, strings.to_string(b), "vision-range = 45  [from core.Alert]\n")

        strings.builder_reset(&b)
        testing.expect_value(t, dos.cli_run(&g.w, {"chain", "Guard"}, out), 0)
        testing.expect_value(t, strings.to_string(b), "core.Guard → core.Human → core.Creature → core.Physical\n")

        strings.builder_reset(&b)
        testing.expect_value(t, dos.cli_run(&g.w, {"resolve", "Guard01", "max-hit-points"}, out), 0)
        testing.expect_value(t, strings.to_string(b), "max-hit-points = 75  [override]\n")

        strings.builder_reset(&b)
        testing.expect_value(t, dos.cli_run(&g.w, {"links", "Guard01"}, out), 0)
        testing.expect(t, strings.contains(strings.to_string(b), "Contains → bafford.Sword01"))

        strings.builder_reset(&b)
        testing.expect_value(t, dos.cli_run(&g.w, {"validate", "data/bad/unknown_parent.kdl"}, out), 1)
        testing.expect(t, strings.contains(strings.to_string(b), `did you mean "Human"?`))

        strings.builder_reset(&b)
        testing.expect_value(t, dos.cli_run(&g.w, {"inspect", "Nobody"}, out), 1)
        testing.expect_value(t, dos.cli_run(&g.w, {"bogus"}, out), 2)
    }

    // dump of the sample game's Guard01, byte for byte
    @(test)
    inspect__golden__test :: proc(t: ^testing.T) {
        g: game.Game
        testing.expect(t, game.setup(&g) == nil)
        defer dos.world_terminate(&g.world)

        testing.expect(t, dos.load(&g.world, "../samples/thief_game/data") == nil)
        guard, found := dos.find(&g.world, "bafford.Guard01")
        testing.expect(t, found)
        if !found do return

        b := strings.builder_make(context.temp_allocator)
        dos.dump(&g.world, guard, strings.to_writer(&b))

        data, err := os.read_entire_file_from_path("golden/guard01_inspect.txt", context.temp_allocator)
        testing.expect(t, err == nil)
        want, _ := strings.replace_all(string(data), "\r\n", "\n", context.temp_allocator)
        testing.expect_value(t, strings.to_string(b), want)
    }
