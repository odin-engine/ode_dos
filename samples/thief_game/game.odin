/*
    2026 (c) Oleh, https://github.com/zm69

    The declarations shared by the Thief demo and its tool: the Odin types, the properties, flags,
    state flags, effects and link flavors a designer can author, declared by one setup proc.
    Everything here is configuration; the runtime is the demo's own ODE_ECS Database.
*/
package thief_game

// ODE
    import dos "../../src"

///////////////////////////////////////////////////////////////////////////////
// Types

    Mass      :: struct { value: f32 }
    Max_HP    :: struct { value: int }
    Vision    :: struct { range: f32 }
    Sound     :: struct { name: string }
    Transform :: struct { position: [3]f32 }

    Slot :: enum u8 {
        Left_Hand,
        Right_Hand,
        Belt,
    }

    Contains :: struct {
        slot: Slot,
    }

    Status :: enum u8 {
        Dead,
        Unconscious,
        Alerted,
        Burning,
    }

    Game :: struct {
        cfg:       dos.Config,

        mass:      dos.Property(Mass),
        max_hp:    dos.Property(Max_HP),
        vision:    dos.Property(Vision),
        footsteps: dos.Property(Sound),
        transform: dos.Property(Transform),

        rope:      dos.Flag,
        status:    dos.State_Flags(Status),
        effects:   dos.Effects,
        contains:  dos.Link(Contains),
    }

///////////////////////////////////////////////////////////////////////////////
// Setup

    // Declares everything; the Game must not move afterwards.
    setup :: proc(g: ^Game) -> dos.Error {
        cfg := &g.cfg
        dos.config_init(cfg, { keep_names = true, user_data = g }) or_return

        dos.property_init(cfg, &g.mass, "mass") or_return
        dos.property_init(cfg, &g.max_hp, "max-hit-points") or_return
        dos.property_init(cfg, &g.vision, "vision-range") or_return
        dos.property_init(cfg, &g.footsteps, "footstep-sound") or_return
        dos.property_init(cfg, &g.transform, "transform") or_return

        dos.flag_init(cfg, &g.rope, "can-attach-rope") or_return
        dos.state_flags_init(cfg, &g.status, "status") or_return
        dos.link_init(cfg, &g.contains, "Contains") or_return

        dos.effects_init(cfg, &g.effects) or_return
        _ = dos.effect_register(&g.effects, "KnockedOut") or_return

        return nil
    }
