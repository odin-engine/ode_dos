/*
    2026 (c) Oleh, https://github.com/zm69

    Reading KDL nodes into Odin values by reflection: positional arguments fill fields in order
    (a fixed array takes several), key=value pairs and child nodes set fields by name (kebab-case or
    snake_case, any letter case), enums are read by name and integers are range-checked.
*/
package ode_dos

// Base
    import rt "base:runtime"

// Core
    import "core:fmt"

// ODE
    import kdl "../../ode_kdl/src"

///////////////////////////////////////////////////////////////////////////////
// Decode_Context

    // Passed to decode procs; report problems with decode_error.
    Decode_Context :: struct {
        world:  ^World,
        loader: rawptr,
        file:   int,
    }

    // Records a problem at loc; the load fails.
    decode_context__error :: proc(ctx: ^Decode_Context, loc: kdl.Location, format: string, args: ..any) {
        ld := cast(^Loader)ctx.loader
        loader__report(ld, ld.files[ctx.file], loc, 1, "", format, ..args)
    }

///////////////////////////////////////////////////////////////////////////////
// Binding by reflection

    binder__bind_node :: proc(ctx: ^Decode_Context, node: ^Load_Node, ti: ^rt.Type_Info, out: rawptr) -> bool {
        base := rt.type_info_base(ti)

        #partial switch v in base.variant {
        case rt.Type_Info_Struct:
            count := int(v.field_count)

            fi := 0
            for i := 0; i < len(node.args); {
                if fi >= count {
                    decode_context__error(ctx, node.args[i].location, "too many values for %v", ti)
                    return false
                }
                fti := v.types[fi]
                fptr := rawptr(uintptr(out) + v.offsets[fi])

                if arr, is_array := rt.type_info_base(fti).variant.(rt.Type_Info_Array); is_array {
                    for k in 0..<arr.count {
                        if i >= len(node.args) {
                            decode_context__error(ctx, node.location, "%s needs %d values", v.names[fi], arr.count)
                            return false
                        }
                        if !binder__bind_value(ctx, node.args[i], arr.elem, rawptr(uintptr(fptr) + uintptr(k * arr.elem_size))) do return false
                        i += 1
                    }
                } else {
                    if !binder__bind_value(ctx, node.args[i], fti, fptr) do return false
                    i += 1
                }
                fi += 1
            }

            for p in node.props {
                idx := binder__field_index(v, p.name)
                if idx < 0 {
                    binder__unknown_field(ctx, v, p.name, p.location, ti)
                    return false
                }
                if !binder__bind_value(ctx, Load_Value{ value = p.value, location = p.location }, v.types[idx], rawptr(uintptr(out) + v.offsets[idx])) do return false
            }

            for c in node.children {
                idx := binder__field_index(v, c.name)
                if idx < 0 {
                    binder__unknown_field(ctx, v, c.name, c.location, ti)
                    return false
                }
                if !binder__bind_node(ctx, c, v.types[idx], rawptr(uintptr(out) + v.offsets[idx])) do return false
            }
            return true

        case rt.Type_Info_Array:
            if len(node.args) != v.count || len(node.props) > 0 || len(node.children) > 0 {
                decode_context__error(ctx, node.location, "%s needs %d values", node.name, v.count)
                return false
            }
            for k in 0..<v.count {
                if !binder__bind_value(ctx, node.args[k], v.elem, rawptr(uintptr(out) + uintptr(k * v.elem_size))) do return false
            }
            return true

        case:
            if len(node.args) != 1 || len(node.props) > 0 || len(node.children) > 0 {
                decode_context__error(ctx, node.location, "%s needs one value", node.name)
                return false
            }
            return binder__bind_value(ctx, node.args[0], ti, out)
        }
    }

    binder__bind_value :: proc(ctx: ^Decode_Context, v: Load_Value, ti: ^rt.Type_Info, out: rawptr) -> bool {
        base := rt.type_info_base(ti)

        #partial switch t in base.variant {
        case rt.Type_Info_Integer:
            n, is_number := v.value.variant.(kdl.Number)
            i, is_int := n.(i64)
            if !is_number || !is_int {
                decode_context__error(ctx, v.location, "expected an integer for %v", ti)
                return false
            }
            if !binder__int_fits(i, base.size, t.signed) {
                decode_context__error(ctx, v.location, "%d is out of range for %v", i, ti)
                return false
            }
            binder__write_int(out, base.size, i)
            return true

        case rt.Type_Info_Float:
            f: f64
            n, is_number := v.value.variant.(kdl.Number)
            switch x in n {
            case i64:    f = f64(x)
            case f64:    f = x
            case string: is_number = false
            }
            if !is_number {
                decode_context__error(ctx, v.location, "expected a number for %v", ti)
                return false
            }
            switch base.size {
            case 2: (^f16)(out)^ = f16(f)
            case 4: (^f32)(out)^ = f32(f)
            case 8: (^f64)(out)^ = f
            }
            return true

        case rt.Type_Info_Boolean:
            b, is_bool := v.value.variant.(bool)
            if !is_bool {
                decode_context__error(ctx, v.location, "expected #true or #false")
                return false
            }
            binder__write_int(out, base.size, b ? 1 : 0)
            return true

        case rt.Type_Info_String:
            s, is_string := v.value.variant.(string)
            if t.is_cstring || !is_string {
                decode_context__error(ctx, v.location, "expected a string for %v", ti)
                return false
            }
            (^string)(out)^ = world__intern(ctx.world, s)
            return true

        case rt.Type_Info_Enum:
            s, is_string := v.value.variant.(string)
            if !is_string {
                decode_context__error(ctx, v.location, "expected a name of %v", ti)
                return false
            }
            for name, i in t.names {
                if names_match(name, s) {
                    binder__write_int(out, base.size, i64(t.values[i]))
                    return true
                }
            }
            ld := cast(^Loader)ctx.loader
            loader__report(ld, ld.files[ctx.file], v.location, len(s) + 2, suggest(s, t.names), "unknown %v %q", ti, s)
            return false

        case:
            decode_context__error(ctx, v.location, "%v cannot be read from KDL; give the binding a decode proc", ti)
            return false
        }
    }

///////////////////////////////////////////////////////////////////////////////
// Private

    // Letter case and '-'/'_' are ignored.
    @(private)
    names_match :: proc(a, b: string) -> bool {
        i, j := 0, 0
        for {
            for i < len(a) && (a[i] == '-' || a[i] == '_') do i += 1
            for j < len(b) && (b[j] == '-' || b[j] == '_') do j += 1
            if i == len(a) || j == len(b) do return i == len(a) && j == len(b)
            if ascii_lower(a[i]) != ascii_lower(b[j]) do return false
            i += 1
            j += 1
        }
    }

    @(private)
    ascii_lower :: #force_inline proc "contextless" (c: byte) -> byte {
        return c >= 'A' && c <= 'Z' ? c + 32 : c
    }

    @(private)
    binder__field_index :: proc(v: rt.Type_Info_Struct, name: string) -> int {
        for i in 0..<int(v.field_count) {
            if names_match(v.names[i], name) do return i
        }
        return -1
    }

    @(private)
    binder__unknown_field :: proc(ctx: ^Decode_Context, v: rt.Type_Info_Struct, name: string, loc: kdl.Location, ti: ^rt.Type_Info) {
        ld := cast(^Loader)ctx.loader
        loader__report(ld, ld.files[ctx.file], loc, len(name), suggest(name, v.names[:v.field_count]), "%v has no field %q", ti, name)
    }

    @(private)
    binder__int_fits :: proc(v: i64, size: int, signed: bool) -> bool {
        if size >= 8 do return signed || v >= 0
        bits := uint(size * 8)
        if signed do return v >= -(i64(1) << (bits - 1)) && v <= (i64(1) << (bits - 1)) - 1
        return v >= 0 && v <= (i64(1) << bits) - 1
    }

    @(private)
    binder__write_int :: proc(out: rawptr, size: int, v: i64) {
        switch size {
        case 1: (^u8)(out)^  = u8(v)
        case 2: (^u16)(out)^ = u16(v)
        case 4: (^u32)(out)^ = u32(v)
        case 8: (^u64)(out)^ = u64(v)
        }
    }

    // A World-owned copy that lives as long as the World.
    @(private)
    world__intern :: proc(self: ^World, s: string) -> string {
        copy := fmt.aprint(s, allocator = self.allocator)
        append(&self.value_strings, copy)
        return copy
    }
