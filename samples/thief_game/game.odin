/*
    2026 (c) Oleh, https://github.com/zm69

    The declarations shared by the Thief demo and its tool: the Odin types, config values,
    state, flags, links and effects, declared by one setup proc.
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
    Velocity  :: struct { v: [3]f32 }
    Health    :: struct { current, max: int }

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
        world:     dos.World,

        mass:      dos.Property(Mass),   // configuration
        max_hp:    dos.Property(Max_HP),
        vision:    dos.Property(Vision),
        footsteps: dos.Property(Sound),
        rope:      dos.Flag,

        transform: dos.State(Transform), // runtime
        velocity:  dos.State(Velocity),
        health:    dos.State(Health),
        status:    dos.State_Flags(Status),

        contains:  dos.Link(Contains),
    }

///////////////////////////////////////////////////////////////////////////////
// Setup

    // Declares everything; the Game must not move afterwards.
    setup :: proc(g: ^Game) -> dos.Error {
        w := &g.world
        dos.world_init(w, { max_objects = 4096, keep_names = true, user_data = g }) or_return

        dos.property_init(w, &g.mass, "mass") or_return
        dos.property_init(w, &g.max_hp, "max-hit-points") or_return
        dos.property_init(w, &g.vision, "vision-range") or_return
        dos.property_init(w, &g.footsteps, "footstep-sound") or_return
        dos.flag_init(w, &g.rope, "can-attach-rope") or_return

        dos.state_init(w, &g.transform, "transform") or_return
        dos.state_init(w, &g.velocity, "velocity") or_return
        dos.state_init(w, &g.health, "health") or_return
        dos.state_flags_init(w, &g.status, "status") or_return

        dos.link_init(w, &g.contains, "Contains") or_return

        // config becomes state at spawn
        dos.on_spawn(w, proc(w: ^dos.World, obj: dos.object_id) {
            g := cast(^Game) dos.user_data(w)
            if hp := dos.resolve(&g.max_hp, obj); hp != nil {
                dos.add(&g.health, obj, Health{ current = hp.value, max = hp.value })
            }
        }) or_return

        dos.effect_register(w, "KnockedOut", dos.Effect{
            on_attach = proc(w: ^dos.World, obj: dos.object_id) {
                g := cast(^Game) dos.user_data(w)
                dos.set(&g.status, obj, Status.Unconscious)
            },
            on_detach = proc(w: ^dos.World, obj: dos.object_id) {
                g := cast(^Game) dos.user_data(w)
                dos.unset(&g.status, obj, Status.Unconscious)
            },
        }) or_return

        return nil
    }
