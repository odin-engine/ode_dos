/*
    2026 (c) Oleh, https://github.com/zm69

    Command-line tooling over a Config: validate files, inspect an object, resolve one value, walk
    a chain or list links.
*/
package ode_dos

// Core
    import "core:fmt"
    import "core:io"
    import "core:strings"

///////////////////////////////////////////////////////////////////////////////
// CLI

    CLI_USAGE :: `commands:
  validate <path>            load path and report problems
  inspect  <object>          what an object is and where its values come from
  resolve  <object> <name>   one value and where it comes from
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
            return config__explain(cfg, obj, args[2], out) ? 0 : 1

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
            for l in links__of(cfg, obj) {
                fmt.wprintf(out, "  %s → %s", l.flavor, config__display(cfg, u32(l.to)))
                if text := node_text(l.data); text != "" do fmt.wprintf(out, "  (%s)", text)
                fmt.wprintln(out)
            }
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
        if full, ok := cli__unique_suffix(cfg, name, .Object); ok {
            if obj, found := config__find_object(cfg, full); found do return obj, true
        }
        fmt.wprintf(out, "unknown object %q\n", name)
        return object_id(NO_ID), false
    }

    @(private)
    cli__archetype :: proc(cfg: ^Config, name: string, out: io.Writer) -> (archetype_id, bool) {
        if a, ok := config__find_archetype(cfg, name); ok do return a, true
        if full, ok := cli__unique_suffix(cfg, name, .Archetype); ok {
            if a, found := config__find_archetype(cfg, full); found do return a, true
        }
        fmt.wprintf(out, "unknown archetype %q\n", name)
        return archetype_id(NO_ID), false
    }

    @(private)
    cli__unique_suffix :: proc(cfg: ^Config, short: string, kind: Config_Kind) -> (string, bool) {
        found := ""
        count := 0

        for c := cfg; c != nil; c = c.base {
            for ix in c.mine {
                e := config__entity(c, ix)
                if e == nil || e.kind != kind do continue

                full := e.name
                if strings.has_suffix(full, short) && len(full) > len(short) && full[len(full) - len(short) - 1] == '.' {
                    found = full
                    count += 1
                }
            }
        }
        return found, count == 1
    }
