/*
    2026 (c) Oleh, https://github.com/zm69

    Tests for reading values: into Odin types by reflection, as raw nodes, and what happens when a
    value is not what the game expected or nothing reads it at all.
*/
package ode_dos__tests

// Core
    import "core:strings"
    import "core:testing"

// ODE
    import dos "../src"

///////////////////////////////////////////////////////////////////////////////
// Types

    Vl_Stats :: struct {
        hit_points: int,
        mana:       u8,
    }

    Vl_Weight :: struct { value: f32 }

///////////////////////////////////////////////////////////////////////////////
// Reading

    @(test)
    values__read__test :: proc(t: ^testing.T) {
        cfg: dos.Config
        testing.expect(t, dos.config_init(&cfg) == nil)
        defer dos.config_terminate(&cfg)
        testing.expect(t, dos.load(&cfg, "data/values") == nil)

        obj, found := dos.find(&cfg, "Thing01")
        testing.expect(t, found)
        if !found do return

        // children fill fields by name, in any case and with either separator
        stats: Vl_Stats
        testing.expect(t, dos.read(&cfg, obj, "stats", &stats))
        testing.expect_value(t, stats.hit_points, 30)
        testing.expect_value(t, stats.mana, 5)

        // an enum is read by name
        slot: Ld_Slot
        testing.expect(t, dos.read(&cfg, obj, "slot", &slot))
        testing.expect(t, slot == .Right_Hand)

        // the raw node is there for anything unusual
        node := dos.node(&cfg, obj, "stats")
        testing.expect(t, node != nil)
        if node != nil do testing.expect_value(t, len(node.children), 2)

        testing.expect(t, !dos.has(&cfg, obj, "nothing-like-this"))
        testing.expect(t, dos.node(&cfg, obj, "nothing-like-this") == nil)
    }

    @(test)
    values__wrong_type_is_an_error__test :: proc(t: ^testing.T) {
        cfg: dos.Config
        testing.expect(t, dos.config_init(&cfg) == nil)
        defer dos.config_terminate(&cfg)
        testing.expect(t, dos.load(&cfg, "data/values") == nil)
        testing.expect_value(t, len(dos.errors(&cfg)), 0)

        obj, _ := dos.find(&cfg, "Thing01")

        // the files say weight "heavy"; the game wants a number
        weight: Vl_Weight
        testing.expect(t, !dos.read(&cfg, obj, "weight", &weight))

        errs := dos.errors(&cfg)
        testing.expect_value(t, len(errs), 1)
        if len(errs) == 0 do return

        testing.expect(t, strings.contains(errs[0].message, "expected a number"))
        testing.expect(t, strings.has_suffix(errs[0].file, "things.kdl"))
        testing.expect_value(t, errs[0].line, 7)
    }

    @(test)
    values__unread_finds_what_nobody_wants__test :: proc(t: ^testing.T) {
        cfg: dos.Config
        testing.expect(t, dos.config_init(&cfg) == nil)
        defer dos.config_terminate(&cfg)
        testing.expect(t, dos.load(&cfg, "data/values") == nil)

        obj, _ := dos.find(&cfg, "Thing01")

        stats: Vl_Stats
        slot: Ld_Slot
        weight: Vl_Weight
        dos.read(&cfg, obj, "stats", &stats)
        dos.read(&cfg, obj, "slot", &slot)
        dos.read(&cfg, obj, "weight", &weight)

        left := dos.unread(&cfg)
        testing.expect_value(t, len(left), 1)
        if len(left) == 0 do return

        testing.expect(t, strings.contains(left[0].message, `nothing reads "unused-value"`))
        testing.expect_value(t, left[0].line, 8)

        // reading it empties the report
        v, has := dos.value(&cfg, obj, "unused-value")
        testing.expect(t, has)
        n, _ := dos.as_int(v)
        testing.expect_value(t, n, 1)
        testing.expect_value(t, len(dos.unread(&cfg)), 0)
    }
