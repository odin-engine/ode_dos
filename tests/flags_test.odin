/*
    2026 (c) Oleh, https://github.com/zm69

    Tests for authored bits: Flag, State_Flags(E) and Effects, including copying them into a
    plain ODE_ECS Flags_Table the way a game does.
*/
package ode_dos__tests

// Core
    import "core:testing"

// ODE
    import dos "../src"
    import ecs "../../ode_ecs/src"

///////////////////////////////////////////////////////////////////////////////
// Types

    Fl_Status :: enum u8 {
        Dead,
        Unconscious,
        Alerted,
    }

///////////////////////////////////////////////////////////////////////////////
// Flag

    @(test)
    flag__inherits_and_overrides__test :: proc(t: ^testing.T) {
        cfg: dos.Config
        testing.expect(t, dos.config_init(&cfg, { keep_names = true }) == nil)
        defer dos.config_terminate(&cfg)

        rope: dos.Flag
        testing.expect(t, dos.flag_init(&cfg, &rope, "can-attach-rope") == nil)
        testing.expect(t, dos.flag_init(&cfg, &rope, "can-attach-rope") == dos.DOS_Error.Name_Already_Exists)

        wooden, _ := dos.meta(&cfg, "Wooden")
        crate, _ := dos.archetype(&cfg, "Crate")
        planks, _ := dos.surface(&cfg, "Planks")
        testing.expect(t, dos.set_flag(&rope, wooden) == nil)
        testing.expect(t, dos.attach(&cfg, crate, wooden) == nil)
        testing.expect(t, dos.attach(&cfg, planks, wooden) == nil)
        testing.expect(t, dos.bake(&cfg) == nil)

        testing.expect(t, dos.resolve_flag(&rope, crate))
        testing.expect(t, dos.resolve_flag(&rope, planks))

        a, _ := dos.object(&cfg, crate, "A")
        b, _ := dos.object(&cfg, crate, "B")
        testing.expect(t, dos.resolve_flag(&rope, a))

        // an object can turn an inherited flag off
        testing.expect(t, dos.set_flag(&rope, a, false) == nil)
        testing.expect(t, !dos.resolve_flag(&rope, a))
        testing.expect(t, dos.resolve_flag(&rope, b))
    }

///////////////////////////////////////////////////////////////////////////////
// State_Flags

    @(test)
    state_flags__authored__test :: proc(t: ^testing.T) {
        cfg: dos.Config
        testing.expect(t, dos.config_init(&cfg, { keep_names = true }) == nil)
        defer dos.config_terminate(&cfg)

        status: dos.State_Flags(Fl_Status)
        testing.expect(t, dos.state_flags_init(&cfg, &status, "status") == nil)

        guard, _ := dos.archetype(&cfg, "Guard")
        testing.expect(t, dos.set_state_flag(&status, guard, Fl_Status.Alerted) == nil)
        testing.expect(t, dos.bake(&cfg) == nil)

        a, _ := dos.object(&cfg, guard, "A")
        testing.expect(t, dos.is_state_flag(&status, a, Fl_Status.Alerted))
        testing.expect(t, !dos.is_state_flag(&status, a, Fl_Status.Dead))

        testing.expect(t, dos.set_state_flag(&status, a, Fl_Status.Dead) == nil)
        set := dos.state_flags_of(&status, a)
        testing.expect(t, Fl_Status.Dead in set && Fl_Status.Alerted in set)

        // the bits drop straight into a game's own Flags_Table
        db: ecs.Database
        defer ecs.terminate(&db)
        testing.expect(t, ecs.init(&db, 8) == nil)

        flags: ecs.Flags_Table
        testing.expect(t, ecs.flags_table_init(&flags, &db, 8) == nil)
        e, _ := ecs.create_entity(&db)
        testing.expect(t, ecs.set_flags(&flags, e, dos.bits_of(&status, a)) == nil)

        testing.expect(t, ecs.has_flag(&flags, e, Fl_Status.Dead))
        testing.expect(t, ecs.has_flag(&flags, e, Fl_Status.Alerted))
        testing.expect(t, !ecs.has_flag(&flags, e, Fl_Status.Unconscious))
    }

///////////////////////////////////////////////////////////////////////////////
// Effects

    @(test)
    effects__registry__test :: proc(t: ^testing.T) {
        cfg: dos.Config
        testing.expect(t, dos.config_init(&cfg, { keep_names = true }) == nil)
        defer dos.config_terminate(&cfg)

        fx: dos.Effects
        testing.expect(t, dos.effects_init(&cfg, &fx, 2) == nil)

        knocked, err := dos.effect_register(&fx, "KnockedOut")
        testing.expect(t, err == nil)
        burning, err2 := dos.effect_register(&fx, "Burning")
        testing.expect(t, err2 == nil)
        testing.expect(t, knocked != burning)
        testing.expect_value(t, dos.effect_count(&fx), 2)

        _, full := dos.effect_register(&fx, "Frozen")
        testing.expect(t, full == dos.DOS_Error.Out_Of_Flags)
        _, dup := dos.effect_register(&fx, "Burning")
        testing.expect(t, dup == dos.DOS_Error.Name_Already_Exists)

        bit, found := dos.effect_bit(&fx, "Burning")
        testing.expect(t, found && bit == burning)
        testing.expect_value(t, dos.effect_name(&fx, knocked), "KnockedOut")

        guard, _ := dos.archetype(&cfg, "Guard")
        testing.expect(t, dos.set_effect(&fx, guard, "Burning") == nil)
        testing.expect(t, dos.set_effect(&fx, guard, "Nothing") == dos.DOS_Error.Name_Not_Found)
        testing.expect(t, dos.bake(&cfg) == nil)

        a, _ := dos.object(&cfg, guard, "A")
        testing.expect(t, dos.has_effect(&fx, a, "Burning"))
        testing.expect(t, !dos.has_effect(&fx, a, "KnockedOut"))

        testing.expect(t, dos.set_effect(&fx, a, "KnockedOut") == nil)
        bits := dos.bits_of(&fx, a)
        testing.expect(t, knocked in bits && burning in bits)
    }
