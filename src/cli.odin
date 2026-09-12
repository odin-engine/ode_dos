/*
    2026 (c) Oleh, https://github.com/zm69

    Command-line tooling. A generic tool cannot know a game's Odin types, so the game builds its
    own tool: it declares everything as usual, loads its data and hands the arguments to cli_run.
*/
package ode_dos

// Core
    import "core:fmt"
    import "core:io"
    import "core:strings"

// ODE
    import ecs "../../ode_ecs/src"

///////////////////////////////////////////////////////////////////////////////
// CLI

    CLI_USAGE :: `commands:
  validate <path>            load path and report problems
  inspect  <object>          what an object is and where its values come from
  resolve  <object> <name>   one property value and where it comes from
  chain    <archetype>       the inheritance chain
  links    <object>          outgoing links`

    // Runs one command and returns the process exit code.
    cli__run :: proc(cfg: ^Config, args: []string, out: io.Writer) -> int {
        if len(args) == 0 do return cli__usage(out)

        switch args[0] {
        case "validate":
            if len(args) != 2 do return cli__usage(out)
            err := config__load(cfg, args[1])
            for e in config__errors(cfg) do fmt.wprintln(out, load_error__format(e, context.temp_allocator))
            if err != nil {
                if len(config__errors(cfg)) == 0 do fmt.wprintln(out, err)
                fmt.wprintf(out, "%d problem(s)\n", max(len(config__errors(cfg)), 1))
                return 1
            }
            fmt.wprintln(out, "ok")
            return 0

        case "inspect":
            if len(args) != 2 do return cli__usage(out)
            obj, ok := cli__object(cfg, args[1], out)
            if !ok do return 1
            config__dump(cfg, obj, out)
            return 0

        case "resolve":
            if len(args) != 3 do return cli__usage(out)
            obj, ok := cli__object(cfg, args[1], out)
            if !ok do return 1
            b := config__find_binding(cfg, args[2])
            if b == nil || b.kind != .Property {
                fmt.wprintf(out, "unknown property %q\n", args[2])
                return 1
            }
            return config__explain_binding(cfg, b, ecs.entity_id(obj), out) ? 0 : 1

        case "chain":
            if len(args) != 2 do return cli__usage(out)
            a, ok := cli__archetype(cfg, args[1], out)
            if !ok do return 1
            config__write_chain(cfg, a, out)
            fmt.wprintln(out)
            return 0

        case "links":
            if len(args) != 2 do return cli__usage(out)
            obj, ok := cli__object(cfg, args[1], out)
            if !ok do return 1
            config__dump_links(cfg, ecs.entity_id(obj), out)
            return 0

        case "help", "-h", "--help":
            fmt.wprintln(out, CLI_USAGE)
            return 0
        }

        fmt.wprintf(out, "unknown command %q\n", args[0])
        return cli__usage(out)
    }

///////////////////////////////////////////////////////////////////////////////
// Private

    @(private)
    cli__usage :: proc(out: io.Writer) -> int {
        fmt.wprintln(out, CLI_USAGE)
        return 2
    }

    // By full name, or by the part after the last dot when that is unique.
    @(private)
    cli__object :: proc(cfg: ^Config, name: string, out: io.Writer) -> (object_id, bool) {
        if obj, ok := config__find_object(cfg, name); ok do return obj, true
        for c := cfg; c != nil; c = c.base {
            if full, ok := cli__unique_suffix(c.object_strings, name); ok {
                if obj, found := config__find_object(cfg, full); found do return obj, true
            }
        }
        fmt.wprintf(out, "unknown object %q\n", name)
        return {}, false
    }

    @(private)
    cli__archetype :: proc(cfg: ^Config, name: string, out: io.Writer) -> (archetype_id, bool) {
        if a, ok := config__find_archetype(cfg, name); ok do return a, true
        for c := cfg; c != nil; c = c.base {
            if full, ok := cli__unique_suffix(c.config_strings, name); ok {
                if a, found := config__find_archetype(cfg, full); found do return a, true
            }
        }
        fmt.wprintf(out, "unknown archetype %q\n", name)
        return {}, false
    }

    @(private)
    cli__unique_suffix :: proc(names: map[u64]string, short: string) -> (string, bool) {
        found := ""
        count := 0
        for _, full in names {
            if strings.has_suffix(full, short) && len(full) > len(short) && full[len(full) - len(short) - 1] == '.' {
                found = full
                count += 1
            }
        }
        return found, count == 1
    }
