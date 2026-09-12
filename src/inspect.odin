/*
    2026 (c) Oleh, https://github.com/zm69

    Inspecting designed objects: what an object is, where each of its values comes from, and what
    it is linked to. Showing the source of every value is what makes a text workflow work without
    an editor.
*/
package ode_dos

// Base
    import rt "base:runtime"

// Core
    import "core:fmt"
    import "core:io"
    import "core:strings"

// ODE
    import ecs "../../ode_ecs/src"

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

    // Archetype, chain, metas, values with their sources, flags, effects and links.
    config__dump :: proc(self: ^Config, obj: object_id, out: io.Writer) {
        cfg := self
        eid := ecs.entity_id(obj)
        a := config__archetype_of(self, obj)

        fmt.wprintf(out, "Object: %-26s archetype: %s\n", config__display(cfg, eid), config__display(cfg, ecs.entity_id(a)))
        fmt.wprint(out, "Chain:  ")
        config__write_chain(cfg, a, out)
        fmt.wprintln(out)

        metas := config__metas_into(cfg, ecs.entity_id(a), cfg.root.meta_scratch)
        if len(metas) > 0 {
            fmt.wprint(out, "Metas:  ")
            for m, i in metas {
                if i > 0 do fmt.wprint(out, ", ")
                fmt.wprintf(out, "%s (priority %d)", config__display(cfg, ecs.entity_id(m.meta)), m.priority)
            }
            fmt.wprintln(out)
        }

        config__dump_section(cfg, eid, .Property, "Properties", out)
        config__dump_section(cfg, eid, .Flag, "Flags", out)
        config__dump_section(cfg, eid, .State_Flags, "State flags", out)
        config__dump_section(cfg, eid, .Effect, "Effects", out)
        config__dump_links(cfg, eid, out)
    }

    // "name = value  [from source]"
    config__explain :: proc(self: ^Config, property: ^Property($T), obj: object_id, out: io.Writer) {
        for c := self; c != nil; c = c.base {
            for &b in c.bindings {
                if b.data == property {
                    config__explain_binding(self, &b, ecs.entity_id(obj), out)
                    return
                }
            }
        }
    }

///////////////////////////////////////////////////////////////////////////////
// Private

    @(private)
    config__explain_binding :: proc(self: ^Config, b: ^Binding, holder: ecs.entity_id, out: io.Writer) -> bool {
        v, _, src, ok := b.read(b.data, holder, 0)
        if !ok {
            fmt.wprintf(out, "%s = (none)\n", b.name)
            return false
        }
        if src.kind == .Override {
            fmt.wprintf(out, "%s = %v  [override]\n", b.name, value_any(v, b.type_info))
        } else {
            fmt.wprintf(out, "%s = %v  [from %s]\n", b.name, value_any(v, b.type_info), config__source_name(self, src))
        }
        return true
    }

    @(private)
    config__write_chain :: proc(self: ^Config, a: archetype_id, out: io.Writer) {
        fmt.wprint(out, config__display(self, ecs.entity_id(a)))
        for p in config__chain_of(self, a) do fmt.wprintf(out, " → %s", config__display(self, ecs.entity_id(p)))
    }

    @(private)
    config__dump_section :: proc(self: ^Config, holder: ecs.entity_id, kind: Binding_Kind, title: string, out: io.Writer) {
        printed := false
        for c := self; c != nil; c = c.base {
            for &b in c.bindings {
                if b.kind != kind || b.read == nil do continue

                #partial switch kind {
                case .Property:
                    v, _, src, ok := b.read(b.data, holder, 0)
                    if !ok do continue
                    section_header(&printed, title, out)
                    fmt.wprintf(out, "  %-18s %-10s [%s]\n", b.name, fmt.tprint(value_any(v, b.type_info)), config__source_name(self, src))
                case .Flag, .Effect:
                    _, _, _, ok := b.read(b.data, holder, 0)
                    if !ok do continue
                    section_header(&printed, title, out)
                    fmt.wprintf(out, "  %s\n", b.name)
                case .State_Flags:
                    e := rt.type_info_base(b.type_info).variant.(rt.Type_Info_Enum)
                    names := strings.builder_make(context.temp_allocator)
                    for n, i in e.names {
                        if _, _, _, set := b.read(b.data, holder, int(e.values[i])); set {
                            if strings.builder_len(names) > 0 do strings.write_string(&names, ", ")
                            strings.write_string(&names, n)
                        }
                    }
                    if strings.builder_len(names) == 0 do continue
                    section_header(&printed, title, out)
                    fmt.wprintf(out, "  %-18s %s\n", b.name, strings.to_string(names))
                }
            }
        }
    }

    @(private)
    config__dump_links :: proc(self: ^Config, holder: ecs.entity_id, out: io.Writer) {
        printed := false
        for c := self; c != nil; c = c.base {
            for &b in c.bindings {
                if b.kind != .Link || b.read == nil do continue
                for i := 0; ; i += 1 {
                    v, target, _, ok := b.read(b.data, holder, i)
                    if !ok do break
                    section_header(&printed, "Links", out)
                    fmt.wprintf(out, "  %s → %s  (%v)\n", b.name, config__display(self, target), value_any(v, b.type_info))
                }
            }
        }
    }

    @(private)
    section_header :: proc(printed: ^bool, title: string, out: io.Writer) {
        if printed^ do return
        fmt.wprintf(out, "\n%s\n", title)
        printed^ = true
    }

    // A single-field struct shows as its field.
    @(private)
    value_any :: proc(v: rawptr, ti: ^rt.Type_Info) -> any {
        base := rt.type_info_base(ti)
        if s, is_struct := base.variant.(rt.Type_Info_Struct); is_struct && s.field_count == 1 {
            return any{ rawptr(uintptr(v) + s.offsets[0]), s.types[0].id }
        }
        return any{ v, ti.id }
    }

    // The name, or "#index" when names are not kept.
    @(private)
    config__display :: proc(self: ^Config, eid: ecs.entity_id) -> string {
        if n := config__name_of(self, eid); n != "" do return n
        return fmt.tprintf("#%d", eid.ix)
    }
