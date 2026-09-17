/*
    2026 (c) Oleh, https://github.com/zm69

    What the Thief demo and its tool share: the Odin types the game reads values into, and a Config
    to load the mission into. Nothing about the data is declared here - the files decide what exists.
*/
package thief_game

// ODE
    import dos "../../src"

///////////////////////////////////////////////////////////////////////////////
// The types this game reads values into

    Mass      :: struct { value: f32 }
    Transform :: struct { position: [3]f32 }
    Health    :: struct { current, max: int }
    Velocity  :: struct { v: [3]f32 }

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
        cfg: dos.Config,
    }

///////////////////////////////////////////////////////////////////////////////
// Setup

    // The Game must not move afterwards.
    setup :: proc(g: ^Game) -> dos.Error {
        return dos.config_init(&g.cfg, { user_data = g })
    }
