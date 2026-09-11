/*
    2026 (c) Oleh, https://github.com/zm69

    Tests for Property(T), config flags, overrides and bake precedence.
*/
package ode_dos__tests

// Core
    import "core:testing"

// ODE
    import dos "../src"

///////////////////////////////////////////////////////////////////////////////
// Property

    Prop_Mass   :: struct { value: f32 }
    Prop_Max_HP :: struct { value: int }
    Prop_Vision :: struct { range: f32 }

    @(test)
    property__precedence__test :: proc(t: ^testing.T) {
        w: dos.World
        testing.expect(t, dos.world_init(&w, {max_archetypes = 64, max_objects = 32, keep_names = true}) == nil)
        defer dos.world_terminate(&w)

        mass: dos.Property(Prop_Mass)
        max_hp: dos.Property(Prop_Max_HP)
        vision: dos.Property(Prop_Vision)
        testing.expect(t, dos.property_init(&w, &mass, "mass", overridable = true) == nil)
        testing.expect(t, dos.property_init(&w, &max_hp, "max-hit-points") == nil)
        testing.expect(t, dos.property_init(&w, &vision, "vision-range") == nil)

        physical, _ := dos.archetype(&w, "Physical")
        creature, _ := dos.archetype(&w, "Creature", parent = "Physical")
        human, _    := dos.archetype(&w, "Human", parent = "Creature")
        guard, _    := dos.archetype(&w, "Guard", parent = "Human")
        alert, _    := dos.meta(&w, "Alert")

        testing.expect(t, dos.set_property(&mass, physical, Prop_Mass{ 10 }) == nil)
        testing.expect(t, dos.set_property(&max_hp, creature, Prop_Max_HP{ 100 }) == nil)
        testing.expect(t, dos.set_property(&vision, human, Prop_Vision{ 20 }) == nil)
        testing.expect(t, dos.set_property(&vision, guard, Prop_Vision{ 30 }) == nil)
        testing.expect(t, dos.set_property(&vision, alert, Prop_Vision{ 45 }) == nil)
        testing.expect(t, dos.attach(&w, guard, alert, priority = 50) == nil)

        g, _ := dos.spawn(&w, "Guard")
        testing.expect(t, dos.resolve(&mass, g) == nil) // not baked yet

        testing.expect(t, dos.bake(&w) == nil)

        testing.expect_value(t, dos.resolve(&mass, g).value, 10)   // from Physical
        testing.expect_value(t, dos.resolve(&max_hp, g).value, 100) // from Creature
        testing.expect_value(t, dos.resolve(&vision, g).range, 45)  // the Alert meta beats Guard's own value
        testing.expect_value(t, dos.resolve(&vision, human).range, 20)
        testing.expect(t, dos.resolve(&max_hp, physical) == nil)

        // get_property is the authored value, not inherited
        testing.expect_value(t, dos.get_property(&vision, guard).range, 30)
        testing.expect(t, dos.get_property(&mass, guard) == nil)

        v, src := dos.resolve_with_source(&vision, g)
        testing.expect(t, v != nil && src.kind == .Meta)
        testing.expect_value(t, dos.name_of(&w, dos.meta_id(src.id)), "Alert")
        _, src = dos.resolve_with_source(&mass, g)
        testing.expect(t, src.kind == .Authored)
        testing.expect_value(t, dos.name_of(&w, dos.archetype_id(src.id)), "Physical")

        // overrides win and are per object
        g2, _ := dos.spawn(&w, "Guard")
        testing.expect(t, dos.override(&mass, g, Prop_Mass{ 95 }) == nil)
        testing.expect_value(t, dos.resolve(&mass, g).value, 95)
        testing.expect_value(t, dos.resolve(&mass, g2).value, 10)
        testing.expect(t, dos.local(&mass, g2) == nil)
        _, src = dos.resolve_with_source(&mass, g)
        testing.expect(t, src.kind == .Override)
        testing.expect(t, dos.clear_override(&mass, g) == nil)
        testing.expect_value(t, dos.resolve(&mass, g).value, 10)

        // bake is idempotent and picks up changes
        testing.expect(t, dos.detach(&w, guard, alert) == nil)
        testing.expect(t, dos.bake(&w) == nil)
        testing.expect(t, dos.bake(&w) == nil)
        testing.expect_value(t, dos.resolve(&vision, g).range, 30)
        testing.expect(t, dos.unset_property(&vision, guard) == nil)
        testing.expect(t, dos.bake(&w) == nil)
        testing.expect_value(t, dos.resolve(&vision, g).range, 20)
    }

    @(test)
    property__wrong_kind__test :: proc(t: ^testing.T) {
        w: dos.World
        testing.expect(t, dos.world_init(&w, {max_archetypes = 16, max_objects = 8}) == nil)
        defer dos.world_terminate(&w)

        mass, other: dos.Property(Prop_Mass)
        testing.expect(t, dos.property_init(&w, &mass, "mass", overridable = true) == nil)
        testing.expect(t, dos.property_init(&w, &other, "mass") == dos.DOS_Error.Name_Already_Exists)

        wooden, _ := dos.meta(&w, "Wooden")
        testing.expect(t, dos.set_property(&mass, dos.archetype_id(wooden), Prop_Mass{ 1 }) == dos.DOS_Error.Wrong_Kind)
    }

///////////////////////////////////////////////////////////////////////////////
// Flags

    @(test)
    property__flags__test :: proc(t: ^testing.T) {
        w: dos.World
        testing.expect(t, dos.world_init(&w, {max_archetypes = 64, max_objects = 32}) == nil)
        defer dos.world_terminate(&w)

        rope, flammable: dos.Flag
        testing.expect(t, dos.flag_init(&w, &rope, "can-attach-rope") == nil)
        testing.expect(t, dos.flag_init(&w, &flammable, "flammable") == nil)

        physical, _ := dos.archetype(&w, "Physical")
        creature, _ := dos.archetype(&w, "Creature", parent = "Physical")
        human, _    := dos.archetype(&w, "Human", parent = "Creature")
        wooden, _   := dos.meta(&w, "Wooden")
        planks, _   := dos.surface(&w, "WoodPlanks")
        stone, _    := dos.surface(&w, "Stone")

        testing.expect(t, dos.set_flag(&flammable, physical, true) == nil)
        testing.expect(t, dos.set_flag(&flammable, human, false) == nil)
        testing.expect(t, dos.set_flag(&rope, wooden, true) == nil)
        testing.expect(t, dos.set_flag(&flammable, wooden, true) == nil)
        testing.expect(t, dos.attach(&w, planks, wooden) == nil)
        testing.expect(t, dos.bake(&w) == nil)

        // the nearest authored value wins, per flag
        testing.expect(t, dos.resolve_flag(&flammable, creature))
        testing.expect(t, !dos.resolve_flag(&flammable, human))
        testing.expect(t, !dos.resolve_flag(&rope, human))

        h, _ := dos.spawn(&w, "Human")
        testing.expect(t, !dos.resolve_flag(&flammable, h))

        testing.expect(t, dos.surface_flag(&w, planks, &rope))
        testing.expect(t, dos.surface_flag(&w, planks, &flammable))
        testing.expect(t, !dos.surface_flag(&w, stone, &rope))
    }

///////////////////////////////////////////////////////////////////////////////
// Config sets

    @(test)
    property__unload_set__test :: proc(t: ^testing.T) {
        w: dos.World
        testing.expect(t, dos.world_init(&w, {max_archetypes = 64, max_objects = 32}) == nil)
        defer dos.world_terminate(&w)

        items, _ := dos.create_config_set(&w, "items")

        durability: dos.Property(Prop_Max_HP)
        sharp: dos.Flag
        testing.expect(t, dos.property_init(&w, &durability, "durability", set = items) == nil)
        testing.expect(t, dos.flag_init(&w, &sharp, "sharp", set = items) == nil)

        sword, _ := dos.archetype(&w, "items.Sword", set = items)
        testing.expect(t, dos.set_property(&durability, sword, Prop_Max_HP{ 50 }) == nil)
        testing.expect(t, dos.set_flag(&sharp, sword, true) == nil)
        testing.expect(t, dos.bake(&w) == nil)
        testing.expect_value(t, dos.resolve(&durability, sword).value, 50)
        testing.expect(t, dos.resolve_flag(&sharp, sword))

        // what was declared in the set goes with it; bake still works and names are free again
        testing.expect(t, dos.unload_config_set(&w, items) == nil)
        testing.expect(t, dos.bake(&w) == nil)

        again, _ := dos.create_config_set(&w, "items")
        durability2: dos.Property(Prop_Max_HP)
        testing.expect(t, dos.property_init(&w, &durability2, "durability", set = again) == nil)
    }

///////////////////////////////////////////////////////////////////////////////
// Plain data

    Prop_Name :: struct { text: string }

    @(test)
    property__non_pod__test :: proc(t: ^testing.T) {
        w: dos.World
        testing.expect(t, dos.world_init(&w, {max_archetypes = 16, max_objects = 8}) == nil)
        defer dos.world_terminate(&w)

        // configuration may hold strings; objects just cannot override it
        label: dos.Property(Prop_Name)
        testing.expect(t, dos.property_init(&w, &label, "label") == nil)
        guard, _ := dos.archetype(&w, "Guard")
        testing.expect(t, dos.set_property(&label, guard, Prop_Name{ "guard" }) == nil)
        testing.expect(t, dos.bake(&w) == nil)

        obj, _ := dos.spawn(&w, "Guard")
        testing.expect_value(t, dos.resolve(&label, obj).text, "guard")
        testing.expect(t, dos.override(&label, obj, Prop_Name{ "x" }) == dos.DOS_Error.Not_Overridable)
        testing.expect(t, dos.clear_override(&label, obj) == dos.DOS_Error.Not_Overridable)
        testing.expect(t, dos.local(&label, obj) == nil)

        // overrides are saved with the game, so they need plain data
        named: dos.Property(Prop_Name)
        testing.expect(t, dos.property_init(&w, &named, "named", overridable = true) == dos.DOS_Error.Type_Not_POD)

        // runtime tables are always saved, so they must be plain data
        state: dos.State(Prop_Name)
        testing.expect(t, dos.state_init(&w, &state, "name-state") == dos.DOS_Error.Type_Not_POD)
        link: dos.Link(Prop_Name)
        testing.expect(t, dos.link_init(&w, &link, "Named") == dos.DOS_Error.Type_Not_POD)
    }
