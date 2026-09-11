/*
    2026 (c) Oleh, https://github.com/zm69

    Loading KDL: parse every file, collect declarations, resolve names, validate everything, and
    only then write to the World, so a failed load changes nothing. Loading names that already
    exist in the same config set updates them, which is the hot-reload path.
*/
package ode_dos

// Base
    import rt "base:runtime"

// Core
    import "core:fmt"
    import "core:mem/virtual"
    import "core:os"
    import "core:slice"
    import "core:strings"

// ODE
    import ecs "../../ode_ecs/src"
    import kdl "../../ode_kdl/src"

///////////////////////////////////////////////////////////////////////////////
// Load

    // Loads a .kdl file, or every .kdl file below a directory, into a config set; then bakes and
    // spawns the declared objects. On failure nothing changes and errors() lists the problems.
    world__load :: proc(self: ^World, path: string, set := CORE) -> Error {
        when VALIDATIONS do assert(world__is_valid(self))

        clear(&self.load_errors)
        virtual.arena_free_all(&self.error_arena)

        if !world__set_is_loaded(self, set) do return DOS_Error.Config_Set_Not_Found

        ld: Loader
        ld.world = self
        ld.set = set
        if err := virtual.arena_init_growing(&ld.arena); err != nil do return err
        defer virtual.arena_destroy(&ld.arena)
        ld.allocator = virtual.arena_allocator(&ld.arena)
        loader__init(&ld)

        loader__collect_files(&ld, path)
        if !ld.failed do loader__parse(&ld)
        if !ld.failed do loader__declare(&ld)
        if !ld.failed do loader__resolve(&ld)
        if ld.failed do return DOS_Error.Load_Failed

        return loader__commit(&ld)
    }

///////////////////////////////////////////////////////////////////////////////
// Loader

    @(private)
    Loader :: struct {
        world:     ^World,
        set:       config_set_id,
        arena:     virtual.Arena,
        allocator: rt.Allocator,
        failed:    bool,

        files: [dynamic]string,
        roots: [dynamic][]^Load_Node, // top-level nodes per file

        decls:        [dynamic]Decl,
        decl_by_name: map[string]int,
        decl_by_ix:   map[int]int, // reloaded config eid.ix -> decl

        objects:        [dynamic]Object_Decl,
        object_by_name: map[string]int,

        links: [dynamic]Link_Decl,
    }

    // A config entity declared in this load (decl >= 0) or already in the World.
    @(private)
    Ref :: struct {
        decl: int,
        eid:  ecs.entity_id,
    }

    @(private)
    Obj_Ref :: struct {
        decl: int,
        obj:  object_id,
    }

    @(private)
    Staged :: struct {
        binding: ^Binding,
        op:      Binding_Op,
        value:   rawptr,
    }

    @(private)
    Meta_Use :: struct {
        ref:      Ref,
        priority: i32,
    }

    @(private)
    Decl :: struct {
        kind:        Config_Kind,
        name:        string,
        namespace:   string,
        node:        ^Load_Node,
        existing:    bool,
        eid:         ecs.entity_id,
        has_parent:  bool,
        parent_name: string,
        parent_loc:  kdl.Location,
        parent:      Ref,
        priority:    i32, // metas: default attach priority
        metas:       [dynamic]Meta_Use,
        values:      [dynamic]Staged,
    }

    @(private)
    Object_Decl :: struct {
        name:           string,
        namespace:      string,
        node:           ^Load_Node,
        archetype_name: string,
        archetype_loc:  kdl.Location,
        archetype:      Ref,
        existing:       bool,
        obj:            object_id,
        values:         [dynamic]Staged,
    }

    @(private)
    Link_Decl :: struct {
        node:      ^Load_Node,
        namespace: string,
        binding:   ^Binding,
        from, to:  Obj_Ref,
        value:     rawptr,
    }

    @(private)
    TOP_LEVEL_NODES := []string{ "namespace", "archetype", "meta", "surface", "object", "link" }

    @(private)
    loader__init :: proc(ld: ^Loader) {
        a := ld.allocator
        ld.files          = make([dynamic]string, 0, 16, a)
        ld.roots          = make([dynamic][]^Load_Node, 0, 16, a)
        ld.decls          = make([dynamic]Decl, 0, 64, a)
        ld.decl_by_name   = make(map[string]int, allocator = a)
        ld.decl_by_ix     = make(map[int]int, allocator = a)
        ld.objects        = make([dynamic]Object_Decl, 0, 64, a)
        ld.object_by_name = make(map[string]int, allocator = a)
        ld.links          = make([dynamic]Link_Decl, 0, 64, a)
    }

///////////////////////////////////////////////////////////////////////////////
// Files and parsing

    @(private)
    loader__collect_files :: proc(ld: ^Loader, path: string) {
        if strings.has_suffix(path, ".kdl") {
            append(&ld.files, strings.clone(path, ld.allocator))
            return
        }

        walker := os.walker_create_path(path)
        defer os.walker_destroy(&walker)
        for fi in os.walker_walk(&walker) {
            if fi.type == .Regular && strings.has_suffix(fi.name, ".kdl") {
                append(&ld.files, strings.clone(fi.fullpath, ld.allocator))
            }
        }
        if p, err := os.walker_error(&walker); err != nil {
            loader__report(ld, path, {}, 0, "", "cannot read %s: %v", p, err)
            return
        }
        if len(ld.files) == 0 {
            loader__report(ld, path, {}, 0, "", "no .kdl files in %s", path)
            return
        }
        slice.sort(ld.files[:])
    }

    @(private)
    loader__parse :: proc(ld: ^Loader) {
        for path, i in ld.files {
            nodes, _ := load__parse_file(ld, i, path)
            append(&ld.roots, nodes)
        }
    }

///////////////////////////////////////////////////////////////////////////////
// Declarations

    @(private)
    loader__declare :: proc(ld: ^Loader) {
        for nodes in ld.roots {
            ns := ""
            for node in nodes {
                switch node.name {
                case "namespace":
                    if name, ok := loader__name_arg(ld, node); ok do ns = name
                case "archetype", "meta", "surface":
                    loader__declare_config(ld, node, ns)
                case "object":
                    loader__declare_object(ld, node, ns)
                case "link":
                    append(&ld.links, Link_Decl{ node = node, namespace = ns })
                case:
                    loader__error_node(ld, node, suggest(node.name, TOP_LEVEL_NODES), "unknown node %q", node.name)
                }
            }
        }
    }

    @(private)
    loader__declare_config :: proc(ld: ^Loader, node: ^Load_Node, ns: string) {
        w := ld.world
        short, ok := loader__name_arg(ld, node)
        if !ok do return

        name := loader__qualify(ld, ns, short)
        kind: Config_Kind
        switch node.name {
        case "archetype": kind = .Archetype
        case "meta":      kind = .Meta
        case "surface":   kind = .Surface
        }

        if prev, dup := ld.decl_by_name[name]; dup {
            first := ld.decls[prev].node
            loader__error_node(ld, node, "", "%q is declared twice; first at %s:%d", name, ld.files[first.file], first.location.line)
            return
        }

        d := Decl{
            kind      = kind,
            name      = name,
            namespace = ns,
            node      = node,
            parent    = Ref{ decl = -1 },
            metas     = make([dynamic]Meta_Use, 0, 2, ld.allocator),
            values    = make([dynamic]Staged, 0, 4, ld.allocator),
        }

        if eid, existing_kind, found := world__find_config(w, name); found {
            if existing_kind != kind || w.config_set_of[eid.ix] != ld.set {
                loader__error_node(ld, node, "", "%q already exists as a %v in config set %q", name, existing_kind, w.sets[w.config_set_of[eid.ix]].name)
                return
            }
            d.existing = true
            d.eid = eid
            ld.decl_by_ix[int(eid.ix)] = len(ld.decls)
        }

        for p in node.props {
            switch {
            case p.name == "parent" && kind == .Archetype:
                s, is_string := p.value.variant.(string)
                if !is_string {
                    loader__error_at(ld, node, p.location, len(p.name), "", "parent must be a name")
                    continue
                }
                d.has_parent = true
                d.parent_name = s
                d.parent_loc = p.location
            case p.name == "priority" && kind == .Meta:
                if v, is_int := loader__int_value(ld, node, p.value, p.location, "priority"); is_int do d.priority = i32(v)
            case:
                loader__error_at(ld, node, p.location, len(p.name), "", "%s does not take %s=", node.name, p.name)
            }
        }

        ld.decl_by_name[name] = len(ld.decls)
        append(&ld.decls, d)
    }

    @(private)
    loader__declare_object :: proc(ld: ^Loader, node: ^Load_Node, ns: string) {
        short, ok := loader__name_arg(ld, node)
        if !ok do return

        name := loader__qualify(ld, ns, short)
        if prev, dup := ld.object_by_name[name]; dup {
            first := ld.objects[prev].node
            loader__error_node(ld, node, "", "%q is declared twice; first at %s:%d", name, ld.files[first.file], first.location.line)
            return
        }

        o := Object_Decl{
            name      = name,
            namespace = ns,
            node      = node,
            archetype = Ref{ decl = -1 },
            values    = make([dynamic]Staged, 0, 4, ld.allocator),
        }

        for p in node.props {
            s, is_string := p.value.variant.(string)
            if p.name != "archetype" || !is_string {
                loader__error_at(ld, node, p.location, len(p.name), "", "an object takes archetype=\"Name\"")
                continue
            }
            o.archetype_name = s
            o.archetype_loc = p.location
        }
        if o.archetype_name == "" {
            loader__error_node(ld, node, "", "object %q needs archetype=\"Name\"", name)
            return
        }

        if obj, found := world__find(ld.world, name); found {
            o.existing = true
            o.obj = obj
        }

        ld.object_by_name[name] = len(ld.objects)
        append(&ld.objects, o)
    }

///////////////////////////////////////////////////////////////////////////////
// Resolution

    @(private)
    loader__resolve :: proc(ld: ^Loader) {
        for &d, i in ld.decls {
            if d.has_parent {
                d.has_parent = false
                ref, kind, found := loader__find_config(ld, d.namespace, d.parent_name)
                switch {
                case !found:
                    loader__error_at(ld, d.node, d.parent_loc, len("parent"), loader__suggest_config(ld, d.namespace, d.parent_name, .Archetype), "unknown archetype %q", d.parent_name)
                case kind != .Archetype:
                    loader__error_at(ld, d.node, d.parent_loc, len("parent"), "", "%q is a %v, not an archetype", d.parent_name, kind)
                case !loader__parent_allowed(ld, ref):
                    loader__error_at(ld, d.node, d.parent_loc, len("parent"), "", "%q is in another config set; a parent must be in the same set or in CORE", d.parent_name)
                case:
                    d.parent = ref
                    d.has_parent = true
                }
            }
            for child in d.node.children do loader__config_item(ld, i, child)
        }
        if !ld.failed do loader__check_cycles(ld)

        for &o, i in ld.objects {
            ref, kind, found := loader__find_config(ld, o.namespace, o.archetype_name)
            switch {
            case !found:
                loader__error_at(ld, o.node, o.archetype_loc, len("archetype"), loader__suggest_config(ld, o.namespace, o.archetype_name, .Archetype), "unknown archetype %q", o.archetype_name)
                continue
            case kind != .Archetype:
                loader__error_at(ld, o.node, o.archetype_loc, len("archetype"), "", "%q is a %v, not an archetype", o.archetype_name, kind)
                continue
            }
            o.archetype = ref
            for child in o.node.children do loader__object_item(ld, i, child)
        }

        for &l in ld.links do loader__resolve_link(ld, &l)
    }

    @(private)
    loader__config_item :: proc(ld: ^Loader, di: int, node: ^Load_Node) {
        d := &ld.decls[di]

        if node.name == "meta" {
            if d.kind == .Meta {
                loader__error_node(ld, node, "", "a meta cannot carry metas")
                return
            }
            name, ok := loader__name_arg(ld, node)
            if !ok do return

            ref, kind, found := loader__find_config(ld, d.namespace, name)
            if !found {
                loader__error_at(ld, node, node.args[0].location, len(name) + 2, loader__suggest_config(ld, d.namespace, name, .Meta), "unknown meta %q", name)
                return
            }
            if kind != .Meta {
                loader__error_at(ld, node, node.args[0].location, len(name) + 2, "", "%q is a %v, not a meta", name, kind)
                return
            }

            use := Meta_Use{ ref = ref, priority = loader__meta_priority(ld, ref) }
            for p in node.props {
                if p.name != "priority" {
                    loader__error_at(ld, node, p.location, len(p.name), "", "meta takes priority=N")
                    continue
                }
                if v, is_int := loader__int_value(ld, node, p.value, p.location, "priority"); is_int do use.priority = i32(v)
            }
            append(&d.metas, use)
            return
        }

        b := world__find_binding(ld.world, node.name)
        if b == nil {
            if loader__is_group(node) {
                for c in node.children do loader__config_item(ld, di, c)
                return
            }
            loader__error_node(ld, node, loader__suggest_binding(ld, node.name, {.Property, .Flag}), "unknown property %q", node.name)
            return
        }

        #partial switch b.kind {
        case .Property:
            if value, ok := loader__decode(ld, b, node); ok do append(&d.values, Staged{ binding = b, op = .Author, value = value })
        case .Flag:
            v := new(bool, ld.allocator)
            v^ = true
            if len(node.args) > 1 || len(node.props) > 0 || len(node.children) > 0 {
                loader__error_node(ld, node, "", "flag %q takes one #true or #false", node.name)
                return
            }
            if len(node.args) == 1 {
                bv, is_bool := node.args[0].value.variant.(bool)
                if !is_bool {
                    loader__error_at(ld, node, node.args[0].location, 1, "", "expected #true or #false")
                    return
                }
                v^ = bv
            }
            append(&d.values, Staged{ binding = b, op = .Author, value = v })
        case:
            loader__error_node(ld, node, "", "%q is %v; set it on an object", node.name, b.kind)
        }
    }

    @(private)
    loader__object_item :: proc(ld: ^Loader, oi: int, node: ^Load_Node) {
        o := &ld.objects[oi]

        b := world__find_binding(ld.world, node.name)
        if b == nil {
            if loader__is_group(node) {
                for c in node.children do loader__object_item(ld, oi, c)
                return
            }
            loader__error_node(ld, node, loader__suggest_binding(ld, node.name, {.Property, .State, .State_Flags}), "unknown value %q", node.name)
            return
        }

        #partial switch b.kind {
        case .Property:
            if !b.overridable {
                loader__error_node(ld, node, "", "%q is not overridable; declare it with property_init(..., overridable = true)", node.name)
                return
            }
            if value, ok := loader__decode(ld, b, node); ok do append(&o.values, Staged{ binding = b, op = .Override, value = value })
        case .State:
            if value, ok := loader__decode(ld, b, node); ok do append(&o.values, Staged{ binding = b, op = .Add, value = value })
        case .State_Flags:
            if len(node.props) > 0 || len(node.children) > 0 {
                loader__error_node(ld, node, "", "%q takes flag names", node.name)
                return
            }
            e := rt.type_info_base(b.type_info).variant.(rt.Type_Info_Enum)
            for a in node.args {
                s, is_string := a.value.variant.(string)
                if !is_string {
                    loader__error_at(ld, node, a.location, 1, "", "expected a flag name")
                    continue
                }
                bit := -1
                for n, i in e.names {
                    if names_match(n, s) do bit = int(e.values[i])
                }
                if bit < 0 {
                    loader__error_at(ld, node, a.location, len(s) + 2, suggest(s, e.names), "unknown %s flag %q", node.name, s)
                    continue
                }
                v := new(int, ld.allocator)
                v^ = bit
                append(&o.values, Staged{ binding = b, op = .Set_Bit, value = v })
            }
        case .Flag:
            loader__error_node(ld, node, "", "%q is a config flag; set it on an archetype", node.name)
        case:
            loader__error_node(ld, node, "", "%q cannot be set on an object", node.name)
        }
    }

    @(private)
    loader__resolve_link :: proc(ld: ^Loader, l: ^Link_Decl) {
        node := l.node
        name, ok := loader__name_arg(ld, node)
        if !ok do return

        b := world__find_binding(ld.world, name)
        if b == nil || b.kind != .Link {
            loader__error_at(ld, node, node.args[0].location, len(name) + 2, loader__suggest_binding(ld, name, {.Link}), "unknown link flavor %q", name)
            return
        }
        l.binding = b

        from_name, to_name: string
        from_loc, to_loc: kdl.Location
        for p in node.props {
            s, is_string := p.value.variant.(string)
            switch {
            case p.name == "from" && is_string:
                from_name, from_loc = s, p.location
            case p.name == "to" && is_string:
                to_name, to_loc = s, p.location
            case:
                loader__error_at(ld, node, p.location, len(p.name), "", "a link takes from=\"Object\" and to=\"Object\"")
            }
        }
        if from_name == "" || to_name == "" {
            loader__error_node(ld, node, "", "a link needs from=\"Object\" and to=\"Object\"")
            return
        }

        found: bool
        if l.from, found = loader__find_object(ld, l.namespace, from_name); !found {
            loader__error_at(ld, node, from_loc, len("from"), loader__suggest_object(ld, l.namespace, from_name), "unknown object %q", from_name)
        }
        if l.to, found = loader__find_object(ld, l.namespace, to_name); !found {
            loader__error_at(ld, node, to_loc, len("to"), loader__suggest_object(ld, l.namespace, to_name), "unknown object %q", to_name)
        }

        // only the children describe the payload
        payload := Load_Node{ name = name, location = node.location, file = node.file, children = node.children }
        if value, decoded := loader__decode(ld, b, &payload); decoded do l.value = value
    }

    // The parent of ref as it will be after this load.
    @(private)
    loader__parent_step :: proc(ld: ^Loader, ref: Ref) -> (Ref, bool) {
        if ref.decl >= 0 {
            d := &ld.decls[ref.decl]
            return d.parent, d.has_parent
        }
        if i, reloaded := ld.decl_by_ix[int(ref.eid.ix)]; reloaded {
            d := &ld.decls[i]
            return d.parent, d.has_parent
        }
        p, err := ecs.parent_of(world__core_db(ld.world), ref.eid)
        if err != nil || ecs.is_not_set(p) do return {}, false
        return Ref{ decl = -1, eid = p }, true
    }

    @(private)
    loader__check_cycles :: proc(ld: ^Loader) {
        limit := len(ld.decls) + ld.world.cfg.max_archetypes + 1
        for d, i in ld.decls {
            if !d.has_parent do continue
            cur := d.parent
            for _ in 0..<limit {
                if cur.decl == i || (cur.decl < 0 && d.existing && cur.eid == d.eid) {
                    loader__error_at(ld, d.node, d.parent_loc, len("parent"), "", "inheritance cycle through %q", d.name)
                    break
                }
                next, has := loader__parent_step(ld, cur)
                if !has do break
                cur = next
            }
        }
    }

///////////////////////////////////////////////////////////////////////////////
// Commit

    @(private)
    loader__commit :: proc(ld: ^Loader) -> Error {
        w := ld.world
        core := world__core_db(w)

        // entities; reloaded ones start over
        for &d in ld.decls {
            if d.existing {
                for &b in w.bindings {
                    if (b.kind == .Property || b.kind == .Flag) && b.apply != nil do b.apply(b.data, .Unauthor, d.eid, {}, nil) or_return
                }
                if ecs.pair_count_of(&w.attachments, d.eid) > 0 do ecs_err(ecs.pair_remove_all(&w.attachments, d.eid)) or_return
                if d.kind == .Archetype do _ = ecs.remove_parent(core, d.eid)
            } else {
                d.eid = world__create_config(w, d.name, d.kind, ld.set) or_return
            }
            if d.kind == .Meta do w.meta_priority[d.eid.ix] = d.priority
        }

        for d in ld.decls {
            if d.has_parent do ecs_err(ecs.set_parent(core, d.eid, loader__ref_eid(ld, d.parent))) or_return
            for m in d.metas do world__attach(w, d.eid, d.kind, meta_id(loader__ref_eid(ld, m.ref)), int(m.priority)) or_return
            for v in d.values do v.binding.apply(v.binding.data, v.op, d.eid, {}, v.value) or_return
        }

        // spawn hooks see baked values and the object's overrides
        world__bake(w) or_return

        for &o in ld.objects {
            if !o.existing {
                o.obj = world__create_object(w, archetype_id(loader__ref_eid(ld, o.archetype))) or_return
                world__set_object_name(w, o.obj, o.name) or_return
            }
            for v in o.values {
                if v.op == .Override do v.binding.apply(v.binding.data, v.op, ecs.entity_id(o.obj), {}, v.value) or_return
            }
            if !o.existing do world__run_spawn_hooks(w, o.obj)
            for v in o.values {
                if v.op != .Override do v.binding.apply(v.binding.data, v.op, ecs.entity_id(o.obj), {}, v.value) or_return
            }
        }

        for l in ld.links {
            from, to := loader__obj(ld, l.from), loader__obj(ld, l.to)
            l.binding.apply(l.binding.data, .Link, ecs.entity_id(from), ecs.entity_id(to), l.value) or_return
        }

        return nil
    }

///////////////////////////////////////////////////////////////////////////////
// Private helpers

    @(private)
    loader__report :: proc(ld: ^Loader, file: string, loc: kdl.Location, span: int, suggestion: string, format: string, args: ..any) {
        ld.failed = true
        a := virtual.arena_allocator(&ld.world.error_arena)
        append(&ld.world.load_errors, Load_Error{
            file       = strings.clone(file, a),
            line       = loc.line,
            column     = loc.column,
            span       = span,
            message    = fmt.aprintf(format, ..args, allocator = a),
            suggestion = strings.clone(suggestion, a),
        })
    }

    @(private)
    loader__error_at :: proc(ld: ^Loader, node: ^Load_Node, loc: kdl.Location, span: int, suggestion: string, format: string, args: ..any) {
        loader__report(ld, ld.files[node.file], loc, span, suggestion, format, ..args)
    }

    @(private)
    loader__error_node :: proc(ld: ^Loader, node: ^Load_Node, suggestion: string, format: string, args: ..any) {
        loader__report(ld, ld.files[node.file], node.location, len(node.name), suggestion, format, ..args)
    }

    // The node's first argument as a name.
    @(private)
    loader__name_arg :: proc(ld: ^Loader, node: ^Load_Node) -> (string, bool) {
        if len(node.args) == 0 {
            loader__error_node(ld, node, "", "%s needs a name", node.name)
            return "", false
        }
        s, is_string := node.args[0].value.variant.(string)
        if !is_string || s == "" {
            loader__error_at(ld, node, node.args[0].location, 1, "", "%s needs a name", node.name)
            return "", false
        }
        return s, true
    }

    @(private)
    loader__int_value :: proc(ld: ^Loader, node: ^Load_Node, v: kdl.Value, loc: kdl.Location, what: string) -> (i64, bool) {
        if n, is_number := v.variant.(kdl.Number); is_number {
            if i, is_int := n.(i64); is_int do return i, true
        }
        loader__error_at(ld, node, loc, len(what), "", "%s must be an integer", what)
        return 0, false
    }

    @(private)
    loader__qualify :: proc(ld: ^Loader, ns: string, name: string) -> string {
        if ns == "" do return name
        return strings.concatenate({ ns, ".", name }, ld.allocator)
    }

    // An unregistered node with only children groups other values.
    @(private)
    loader__is_group :: proc(node: ^Load_Node) -> bool {
        return len(node.args) == 0 && len(node.props) == 0 && len(node.children) > 0
    }

    // Tries ns.name first, then name as written.
    @(private)
    loader__find_config :: proc(ld: ^Loader, ns: string, name: string) -> (Ref, Config_Kind, bool) {
        candidates := [2]string{ loader__qualify(ld, ns, name), name }
        for c in candidates {
            if i, in_load := ld.decl_by_name[c]; in_load do return Ref{ decl = i, eid = ld.decls[i].eid }, ld.decls[i].kind, true
            if eid, kind, found := world__find_config(ld.world, c); found do return Ref{ decl = -1, eid = eid }, kind, true
        }
        return {}, .None, false
    }

    @(private)
    loader__find_object :: proc(ld: ^Loader, ns: string, name: string) -> (Obj_Ref, bool) {
        candidates := [2]string{ loader__qualify(ld, ns, name), name }
        for c in candidates {
            if i, in_load := ld.object_by_name[c]; in_load do return Obj_Ref{ decl = i }, true
            if obj, found := world__find(ld.world, c); found do return Obj_Ref{ decl = -1, obj = obj }, true
        }
        return {}, false
    }

    @(private)
    loader__parent_allowed :: proc(ld: ^Loader, ref: Ref) -> bool {
        if ref.decl >= 0 do return true
        ps := ld.world.config_set_of[ref.eid.ix]
        return ps == ld.set || ps == CORE
    }

    @(private)
    loader__meta_priority :: proc(ld: ^Loader, ref: Ref) -> i32 {
        if ref.decl >= 0 do return ld.decls[ref.decl].priority
        return ld.world.meta_priority[ref.eid.ix]
    }

    @(private)
    loader__ref_eid :: proc(ld: ^Loader, ref: Ref) -> ecs.entity_id {
        return ref.decl >= 0 ? ld.decls[ref.decl].eid : ref.eid
    }

    @(private)
    loader__obj :: proc(ld: ^Loader, ref: Obj_Ref) -> object_id {
        return ref.decl >= 0 ? ld.objects[ref.decl].obj : ref.obj
    }

    // Reads node into a fresh value of the binding's type.
    @(private)
    loader__decode :: proc(ld: ^Loader, b: ^Binding, node: ^Load_Node) -> (rawptr, bool) {
        data, err := rt.mem_alloc(b.type_info.size, b.type_info.align, ld.allocator)
        if err != nil {
            loader__error_node(ld, node, "", "out of memory")
            return nil, false
        }
        out := raw_data(data)

        ctx := Decode_Context{ world = ld.world, loader = ld, file = node.file }
        before := len(ld.world.load_errors)
        ok := b.decode != nil ? b.decode(&ctx, node, out) : binder__bind_node(&ctx, node, b.type_info, out)
        if !ok && len(ld.world.load_errors) == before do loader__error_node(ld, node, "", "cannot read %q", node.name)
        return out, ok
    }

    // Written relative to ns when that is how the name would be referenced.
    @(private)
    loader__shorten :: proc(ns: string, name: string) -> string {
        if ns != "" && len(name) > len(ns) + 1 && strings.has_prefix(name, ns) && name[len(ns)] == '.' do return name[len(ns) + 1:]
        return name
    }

    @(private)
    loader__suggest_config :: proc(ld: ^Loader, ns: string, name: string, kind: Config_Kind) -> string {
        candidates := make([dynamic]string, 0, 64, context.temp_allocator)
        for d in ld.decls {
            if d.kind == kind do append(&candidates, loader__shorten(ns, d.name))
        }
        for k, ix in ld.world.config_kind {
            if k != kind do continue
            if n := world__config_name(ld.world, ld.world.config_eid[ix]); n != "" do append(&candidates, loader__shorten(ns, n))
        }
        return suggest(name, candidates[:])
    }

    @(private)
    loader__suggest_object :: proc(ld: ^Loader, ns: string, name: string) -> string {
        candidates := make([dynamic]string, 0, 64, context.temp_allocator)
        for o in ld.objects do append(&candidates, loader__shorten(ns, o.name))
        return suggest(name, candidates[:])
    }

    @(private)
    loader__suggest_binding :: proc(ld: ^Loader, name: string, kinds: bit_set[Binding_Kind]) -> string {
        candidates := make([dynamic]string, 0, 32, context.temp_allocator)
        for b in ld.world.bindings {
            if b.kind in kinds do append(&candidates, b.name)
        }
        return suggest(name, candidates[:])
    }
