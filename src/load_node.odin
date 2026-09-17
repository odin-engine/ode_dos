/*
    2026 (c) Oleh, https://github.com/zm69

    KDL input as compact node records, parsed with ODE_KDL's streaming pull parser. Records and
    their strings live in the Config's arena, so a value can still be read long after the load.
*/
package ode_dos

// Core
    import "core:os"
    import "core:strings"

// ODE
    import kdl "../../ode_kdl/src"

///////////////////////////////////////////////////////////////////////////////
// Load_Node

    Load_Value :: struct {
        value:    kdl.Value,
        location: kdl.Location,
    }

    Load_Property :: struct {
        name:     string,
        value:    kdl.Value,
        location: kdl.Location,
    }

    Load_Node :: struct {
        name:     string,
        location: kdl.Location,
        file:     int, // index into the load's files
        args:     []Load_Value,
        props:    []Load_Property,
        children: []^Load_Node,
    }

///////////////////////////////////////////////////////////////////////////////
// Private

    @(private)
    Node_Builder :: struct {
        node:     ^Load_Node,
        args:     [dynamic]Load_Value,
        props:    [dynamic]Load_Property,
        children: [dynamic]^Load_Node,
    }

    @(private)
    load__parse_file :: proc(ld: ^Loader, file: int, path: string) -> (nodes: []^Load_Node, ok: bool) {
        f, ferr := os.open(path)
        if ferr != nil {
            loader__report(ld, path, {}, 0, "", "cannot open file: %v", ferr)
            return nil, false
        }
        defer os.close(f)

        parser: kdl.Parser
        if err := kdl.init(&parser, os.to_stream(f), false, ld.allocator); err != nil {
            loader__report(ld, path, {}, 0, "", "cannot read file: %v", err)
            return nil, false
        }
        defer kdl.destroy(&parser)

        stack := make([dynamic]Node_Builder, 0, 16, ld.allocator)
        top := make([dynamic]^Load_Node, 0, 32, ld.persist)

        for {
            ev := kdl.next_event(&parser)
            switch ev.type {
            case .EOF:
                return top[:], true

            case .Parse_Error:
                msg, _ := ev.value.variant.(string)
                loader__report(ld, path, ev.location, 1, "", "KDL syntax error: %s", msg)
                return nil, false

            case .Start_Node:
                n := new(Load_Node, ld.persist)
                n.name = strings.clone(ev.name, ld.persist)
                n.location = ev.location
                n.file = file
                append(&stack, Node_Builder{
                    node     = n,
                    args     = make([dynamic]Load_Value, 0, 4, ld.persist),
                    props    = make([dynamic]Load_Property, 0, 2, ld.persist),
                    children = make([dynamic]^Load_Node, 0, 4, ld.persist),
                })

            case .Argument:
                b := &stack[len(stack) - 1]
                append(&b.args, Load_Value{ value = load__clone_value(ev.value, ld.persist), location = ev.location })

            case .Property:
                b := &stack[len(stack) - 1]
                append(&b.props, Load_Property{
                    name     = strings.clone(ev.name, ld.persist),
                    value    = load__clone_value(ev.value, ld.persist),
                    location = ev.location,
                })

            case .End_Node:
                b := pop(&stack)
                b.node.args = b.args[:]
                b.node.props = b.props[:]
                b.node.children = b.children[:]
                if len(stack) > 0 {
                    append(&stack[len(stack) - 1].children, b.node)
                } else {
                    append(&top, b.node)
                    kdl.compact(&parser)
                }

            case .Comment:
            }
        }
    }

    // Event strings die with the next event, so values keep their own copies.
    @(private)
    load__clone_value :: proc(v: kdl.Value, allocator := context.allocator) -> kdl.Value {
        res := v
        if ann, has := v.type_annotation.?; has do res.type_annotation = strings.clone(ann, allocator)

        switch x in v.variant {
        case string:
            res.variant = strings.clone(x, allocator)
        case kdl.Number:
            if s, is_text := x.(string); is_text do res.variant = kdl.Number(strings.clone(s, allocator))
        case bool:
        }
        return res
    }
