/*
    2026 (c) Oleh, https://github.com/zm69

    Inspecting objects: what an object is, where each of its values comes from, and what it is
    linked to. Showing the source of every value is what makes a text workflow work without an
    editor.
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
    world__source_name :: proc(self: ^World, src: Value_Source) -> string {
        switch src.kind {
        case .None:            return ""
        case .Override:        return "override"
        case .Authored, .Meta: return world__display_config(self, src.id)
        }
        return ""
    }

    // Archetype, chain, metas, config values with their sources, state, flags, links and effects.
    world__dump :: proc(self: ^World, obj: object_id, out: io.Writer) {
        eid := ecs.entity_id(obj)
        a := world__archetype_of(self, obj)

        fmt.wprintf(out, "Object: %-26s archetype: %s\n", world__display_object(self, obj), world__display_config(self, ecs.entity_id(a)))
        fmt.wprint(out, "Chain:  ")
        world__write_chain(self, a, out)
        fmt.wprintln(out)

        metas := world__metas_into(self, ecs.entity_id(a), self.meta_scratch)
        if len(metas) > 0 {
            fmt.wprint(out, "Metas:  ")
            for m, i in metas {
                if i > 0 do fmt.wprint(out, ", ")
                fmt.wprintf(out, "%s (priority %d)", world__display_config(self, ecs.entity_id(m.meta)), m.priority)
            }
            fmt.wprintln(out)
        }

        world__dump_section(self, eid, .Property, "Properties", out)
        world__dump_section(self, eid, .Flag, "Flags", out)
        world__dump_section(self, eid, .State, "State", out)
        world__dump_section(self, eid, .State_Flags, "State flags", out)
        world__dump_links(self, eid, out)
        world__dump_effects(self, eid, out)
    }

    // "name = value  [from source]"
    world__explain :: proc(self: ^World, property: ^Property($T), obj: object_id, out: io.Writer) {
        for &b in self.bindings {
            if b.data == property {
                world__explain_binding(self, &b, obj, out)
                return
            }
        }
    }

///////////////////////////////////////////////////////////////////////////////
// Private

    @(private)
    world__explain_binding :: proc(self: ^World, b: ^Binding, obj: object_id, out: io.Writer) -> bool {
        v, _, src, ok := b.read(b.data, ecs.entity_id(obj), 0)
        if !ok {
            fmt.wprintf(out, "%s = (none)\n", b.name)
            return false
        }
        if src.kind == .Override {
            fmt.wprintf(out, "%s = %v  [override]\n", b.name, value_any(v, b.type_info))
        } else {
            fmt.wprintf(out, "%s = %v  [from %s]\n", b.name, value_any(v, b.type_info), world__source_name(self, src))
        }
        return true
    }

    @(private)
    world__write_chain :: proc(self: ^World, a: archetype_id, out: io.Writer) {
        fmt.wprint(out, world__display_config(self, ecs.entity_id(a)))
        for p in world__chain_of(self, a) do fmt.wprintf(out, " → %s", world__display_config(self, ecs.entity_id(p)))
    }

    @(private)
    world__dump_section :: proc(self: ^World, eid: ecs.entity_id, kind: Binding_Kind, title: string, out: io.Writer) {
        printed := false
        for &b in self.bindings {
            if b.kind != kind || b.read == nil do continue

            #partial switch kind {
            case .Property:
                v, _, src, ok := b.read(b.data, eid, 0)
                if !ok do continue
                section_header(&printed, title, out)
                fmt.wprintf(out, "  %-18s %-10s [%s]\n", b.name, fmt.tprint(value_any(v, b.type_info)), world__source_name(self, src))
            case .State:
                v, _, _, ok := b.read(b.data, eid, 0)
                if !ok do continue
                section_header(&printed, title, out)
                fmt.wprintf(out, "  %-18s %v\n", b.name, value_any(v, b.type_info))
            case .Flag:
                _, _, _, ok := b.read(b.data, eid, 0)
                if !ok do continue
                section_header(&printed, title, out)
                fmt.wprintf(out, "  %s\n", b.name)
            case .State_Flags:
                e := rt.type_info_base(b.type_info).variant.(rt.Type_Info_Enum)
                names := strings.builder_make(context.temp_allocator)
                for n, i in e.names {
                    if _, _, _, set := b.read(b.data, eid, int(e.values[i])); set {
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

    @(private)
    world__dump_links :: proc(self: ^World, eid: ecs.entity_id, out: io.Writer) {
        printed := false
        for &b in self.bindings {
            if b.kind != .Link || b.read == nil do continue
            for i := 0; ; i += 1 {
                v, target, _, ok := b.read(b.data, eid, i)
                if !ok do break
                section_header(&printed, "Links", out)
                fmt.wprintf(out, "  %s → %s  (%v)\n", b.name, world__display_object(self, object_id(target)), value_any(v, b.type_info))
            }
        }
    }

    @(private)
    world__dump_effects :: proc(self: ^World, eid: ecs.entity_id, out: io.Writer) {
        printed := false
        for e in self.effects {
            if !ecs.has_flag(e.table, eid, e.bit) do continue
            section_header(&printed, "Effects", out)
            for b in self.bindings {
                if b.hash == e.hash do fmt.wprintf(out, "  %s\n", b.name)
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
    world__display_object :: proc(self: ^World, obj: object_id) -> string {
        if n := world__object_name(self, obj); n != "" do return n
        return fmt.tprintf("#%d", ecs.entity_id(obj).ix)
    }

    @(private)
    world__display_config :: proc(self: ^World, eid: ecs.entity_id) -> string {
        if n := world__config_name(self, eid); n != "" do return n
        return fmt.tprintf("#%d", eid.ix)
    }
