/*
    2026 (c) Oleh, https://github.com/zm69

    Inspecting designed objects: what an object is, where each of its values comes from, and what
    it is linked to. Showing the source of every value is what makes a text workflow work without
    an editor. Values print as they were authored, since ODE_DOS does not know their Odin types.
*/
package ode_dos

// Core
    import "core:fmt"
    import "core:io"
    import "core:strings"

// ODE
    import kdl "../../ode_kdl/src"

///////////////////////////////////////////////////////////////////////////////
// Inspect

    // "override", the name of the archetype or meta a value came from, or "" when none.
    config__source_name :: proc(self: ^Config, src: Value_Source) -> string {
        switch src.kind {
        case .None:            return ""
        case .Override:        return "override"
        case .Authored, .Meta: return config__display(self, src.id)
        }
        return ""
    }

    // Archetype, chain, metas, every value with its source, and the links.
    config__dump :: proc(self: ^Config, obj: object_id, out: io.Writer) {
        a := config__archetype_of(self, obj)

        fmt.wprintf(out, "Object: %-26s archetype: %s\n", config__display(self, u32(obj)), config__display(self, u32(a)))
        fmt.wprint(out, "Chain:  ")
        config__write_chain(self, a, out)
        fmt.wprintln(out)

        metas := config__metas(self, u32(a))
        if len(metas) > 0 {
            fmt.wprint(out, "Metas:  ")
            for m, i in metas {
                if i > 0 do fmt.wprint(out, ", ")
                fmt.wprintf(out, "%s (priority %d)", config__display(self, u32(m.meta)), m.priority)
            }
            fmt.wprintln(out)
        }

        values := values__resolved(self, u32(obj))
        if len(values) > 0 {
            fmt.wprintln(out, "\nValues")
            for v in values {
                fmt.wprintf(out, "  %-18s %-16s [%s]\n", v.name, node_text(v.node), config__source_name(self, v.source))
            }
        }

        links := links__of(self, obj)
        if len(links) > 0 {
            fmt.wprintln(out, "\nLinks")
            for l in links {
                fmt.wprintf(out, "  %s → %s", l.flavor, config__display(self, u32(l.to)))
                if text := node_text(l.data); text != "" do fmt.wprintf(out, "  (%s)", text)
                fmt.wprintln(out)
            }
        }
    }

    // "name = value  [from source]"
    config__explain :: proc(self: ^Config, obj: object_id, name: string, out: io.Writer) -> bool {
        node := values__node(self, u32(obj), name)
        if node == nil {
            fmt.wprintf(out, "%s = (none)\n", name)
            return false
        }

        src := values__source(self, u32(obj), name)
        if src.kind == .Override {
            fmt.wprintf(out, "%s = %s  [override]\n", name, node_text(node))
        } else {
            fmt.wprintf(out, "%s = %s  [from %s]\n", name, node_text(node), config__source_name(self, src))
        }
        return true
    }

///////////////////////////////////////////////////////////////////////////////
// Private

    @(private)
    config__write_chain :: proc(self: ^Config, a: archetype_id, out: io.Writer) {
        fmt.wprint(out, config__display(self, u32(a)))
        for p in config__chain_of(self, a) do fmt.wprintf(out, " → %s", config__display(self, u32(p)))
    }

    // The name, or "#index" when the entity has none.
    @(private)
    config__display :: proc(self: ^Config, ix: u32) -> string {
        if n := config__name_of(self, ix); n != "" do return n
        return fmt.tprintf("#%d", ix)
    }

    // A value as it was authored: its arguments, then its children in braces.
    @(private)
    node_text :: proc(node: ^Load_Node) -> string {
        if node == nil do return ""

        b := strings.builder_make(context.temp_allocator)
        for a, i in node.args {
            if i > 0 do strings.write_byte(&b, ' ')
            strings.write_string(&b, value_text(a.value))
        }

        if len(node.children) > 0 {
            if strings.builder_len(b) > 0 do strings.write_byte(&b, ' ')
            strings.write_string(&b, "{ ")
            for c, i in node.children {
                if i > 0 do strings.write_string(&b, ", ")
                strings.write_string(&b, c.name)
                if text := node_text(c); text != "" {
                    strings.write_byte(&b, ' ')
                    strings.write_string(&b, text)
                }
            }
            strings.write_string(&b, " }")
        }

        if strings.builder_len(b) == 0 do return "#true" // a name on its own is a flag
        return strings.to_string(b)
    }

    @(private)
    value_text :: proc(v: kdl.Value) -> string {
        switch x in v.variant {
        case string:
            return x
        case bool:
            return x ? "#true" : "#false"
        case kdl.Number:
            switch n in x {
            case i64:    return fmt.tprintf("%d", n)
            case f64:    return fmt.tprintf("%v", n)
            case string: return n
            }
        }
        return ""
    }
