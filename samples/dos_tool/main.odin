/*
    2026 (c) Oleh, https://github.com/zm69

    A game-built ODE_DOS tool: the game's declarations plus cli_run.

        dos_tool <data> validate <path>
        dos_tool <data> inspect  Guard01
        dos_tool <data> resolve  Guard01 vision-range
        dos_tool <data> chain    Guard
        dos_tool <data> links    Guard01
*/
package dos_tool

// Core
    import "core:fmt"
    import "core:os"

// ODE
    import dos "../../src"
    import game "../thief_game"

main :: proc() {
    os.exit(run())
}

run :: proc() -> int {
    args := os.args
    if len(args) < 3 {
        fmt.eprintln("usage: dos_tool <data> <command> [args]")
        fmt.eprintln(dos.CLI_USAGE)
        return 2
    }

    g: game.Game
    if err := game.setup(&g); err != nil {
        fmt.eprintln("setup failed:", err)
        return 1
    }
    defer dos.config_terminate(&g.cfg)

    // validate loads its own path
    if args[2] != "validate" && dos.load(&g.cfg, args[1]) != nil {
        for e in dos.errors(&g.cfg) do fmt.eprintln(dos.format_error(e, context.temp_allocator))
        return 1
    }

    return dos.cli_run(&g.cfg, args[2:], os.to_stream(os.stdout))
}
