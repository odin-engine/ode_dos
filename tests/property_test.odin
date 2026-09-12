/*
    2026 (c) Oleh, https://github.com/zm69

    Tests for Property(T): authoring, precedence, baking, and the value an object authors for
    itself, which is an override.
*/
package ode_dos__tests

// Core
    import "core:testing"

// ODE
    import dos "../src"

///////////////////////////////////////////////////////////////////////////////
// Types

    Prop_Mass   :: struct { value: f32 }
    Prop_Max_HP :: struct { value: int }
    Prop_Vision :: struct { range: f32 }
    Prop_Name   :: struct { text: string }

///////////////////////////////////////////////////////////////////////////////
// Precedence

    @(test)
    property__precedence__test :: proc(t: ^testing.T) {
        cfg: dos.Config
        testing.expect(t, dos.config_init(&cfg, { keep_names = true }) == nil)
        defer dos.config_terminate(&cfg)

        mass: dos.Property(Prop_Mass)
        max_hp: dos.Property(Prop_Max_HP)
        vision: dos.Property(Prop_Vision)
        testing.expect(t, dos.property_init(&cfg, &mass, "mass") == nil)
        testing.expect(t, dos.property_init(&cfg, &max_hp, "max-hit-points") == nil)
        testing.expect(t, dos.property_init(&cfg, &vision, "vision-range") == nil)

        physical, _ := dos.archetype(&cfg, "Physical")
        creature, _ := dos.archetype(&cfg, "Creature", parent = "Physical")
        guard, _ := dos.archetype(&cfg, "Guard", parent = "Creature")
        alert, _ := dos.meta(&cfg, "Alert")

        testing.expect(t, dos.set_property(&mass, physical, Prop_Mass{ 10 }) == nil)
        testing.expect(t, dos.set_property(&max_hp, creature, Prop_Max_HP{ 100 }) == nil)
        testing.expect(t, dos.set_property(&vision, guard, Prop_Vision{ 30 }) == nil)
        testing.expect(t, dos.set_property(&vision, alert, Prop_Vision{ 45 }) == nil)
        testing.expect(t, dos.attach(&cfg, guard, alert, 50) == nil)
        testing.expect(t, dos.bake(&cfg) == nil)

        // inherited, and the meta beats the archetype
        testing.expect_value(t, dos.resolve(&mass, guard).value, 10)
        testing.expect_value(t, dos.resolve(&max_hp, guard).value, 100)
        testing.expect_value(t, dos.resolve(&vision, guard).range, 45)

        // authored on the holder only
        testing.expect(t, dos.get_property(&mass, physical) != nil)
        testing.expect(t, dos.get_property(&mass, guard) == nil)

        g, _ := dos.object(&cfg, guard, "Guard01")
        v, src := dos.resolve_with_source(&vision, g)
        testing.expect(t, v != nil && src.kind == .Meta)
        testing.expect_value(t, dos.name_of(&cfg, dos.meta_id(src.id)), "Alert")

        _, msrc := dos.resolve_with_source(&mass, g)
        testing.expect(t, msrc.kind == .Authored)
        testing.expect_value(t, dos.name_of(&cfg, dos.archetype_id(msrc.id)), "Physical")

        // bake is idempotent and picks up changes
        testing.expect(t, dos.detach(&cfg, guard, alert) == nil)
        testing.expect(t, dos.bake(&cfg) == nil)
        testing.expect(t, dos.bake(&cfg) == nil)
        testing.expect_value(t, dos.resolve(&vision, guard).range, 30)
        testing.expect(t, dos.unset_property(&vision, guard) == nil)
        testing.expect(t, dos.bake(&cfg) == nil)
        testing.expect(t, dos.resolve(&vision, guard) == nil)
    }

///////////////////////////////////////////////////////////////////////////////
// Overrides

    @(test)
    property__object_override__test :: proc(t: ^testing.T) {
        cfg: dos.Config
        testing.expect(t, dos.config_init(&cfg, { keep_names = true }) == nil)
        defer dos.config_terminate(&cfg)

        mass: dos.Property(Prop_Mass)
        label: dos.Property(Prop_Name)
        testing.expect(t, dos.property_init(&cfg, &mass, "mass") == nil)
        testing.expect(t, dos.property_init(&cfg, &label, "label") == nil)

        guard, _ := dos.archetype(&cfg, "Guard")
        testing.expect(t, dos.set_property(&mass, guard, Prop_Mass{ 10 }) == nil)
        testing.expect(t, dos.set_property(&label, guard, Prop_Name{ "guard" }) == nil)
        testing.expect(t, dos.bake(&cfg) == nil)

        a, _ := dos.object(&cfg, guard, "A")
        b, _ := dos.object(&cfg, guard, "B")

        testing.expect_value(t, dos.resolve(&mass, a).value, 10)
        testing.expect(t, dos.get_property(&mass, a) == nil)

        // what an object authors wins, and only for that object
        testing.expect(t, dos.set_property(&mass, a, Prop_Mass{ 95 }) == nil)
        testing.expect_value(t, dos.resolve(&mass, a).value, 95)
        testing.expect_value(t, dos.resolve(&mass, b).value, 10)
        testing.expect(t, dos.get_property(&mass, a) != nil)

        _, src := dos.resolve_with_source(&mass, a)
        testing.expect(t, src.kind == .Override)
        testing.expect_value(t, dos.name_of(&cfg, a), "A")

        testing.expect(t, dos.unset_property(&mass, a) == nil)
        testing.expect_value(t, dos.resolve(&mass, a).value, 10)

        // config values are never serialized, so strings can be overridden too
        testing.expect(t, dos.set_property(&label, a, Prop_Name{ "captain" }) == nil)
        testing.expect_value(t, dos.resolve(&label, a).text, "captain")
        testing.expect_value(t, dos.resolve(&label, b).text, "guard")
    }

    @(test)
    property__wrong_kind__test :: proc(t: ^testing.T) {
        cfg: dos.Config
        testing.expect(t, dos.config_init(&cfg) == nil)
        defer dos.config_terminate(&cfg)

        mass: dos.Property(Prop_Mass)
        testing.expect(t, dos.property_init(&cfg, &mass, "mass") == nil)
        testing.expect(t, dos.property_init(&cfg, &mass, "mass") == dos.DOS_Error.Name_Already_Exists)

        guard, _ := dos.archetype(&cfg, "Guard")
        testing.expect(t, dos.set_property(&mass, dos.meta_id(guard), Prop_Mass{ 1 }) == dos.DOS_Error.Wrong_Kind)
        testing.expect(t, dos.set_property(&mass, dos.object_id(guard), Prop_Mass{ 1 }) == dos.DOS_Error.Wrong_Kind)
    }

///////////////////////////////////////////////////////////////////////////////
// Surfaces

    @(test)
    property__surface__test :: proc(t: ^testing.T) {
        cfg: dos.Config
        testing.expect(t, dos.config_init(&cfg, { keep_names = true }) == nil)
        defer dos.config_terminate(&cfg)

        sound: dos.Property(Prop_Name)
        testing.expect(t, dos.property_init(&cfg, &sound, "footstep-sound") == nil)

        planks, _ := dos.surface(&cfg, "Planks")
        wooden, _ := dos.meta(&cfg, "Wooden")
        testing.expect(t, dos.set_property(&sound, wooden, Prop_Name{ "wood" }) == nil)
        testing.expect(t, dos.attach(&cfg, planks, wooden) == nil)
        testing.expect(t, dos.bake(&cfg) == nil)

        testing.expect_value(t, dos.resolve(&sound, planks).text, "wood")
    }
