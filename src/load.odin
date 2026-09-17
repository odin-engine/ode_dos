/*
    2026 (c) Oleh, https://github.com/zm69

    Loading KDL: parse every file, collect declarations, resolve names, validate, and only then
    write to the Config, so a failed load changes nothing. A child node is simply a value authored
    under its own name - nothing is declared in code, so nothing is looked up in a registry.

    Loading names that already exist in the same Config updates them, which is the hot-reload path.
*/
package ode_dos

// Base
    import rt "base:runtime"

// Core
    import "core:mem/virtual"
    import "core:os"
    import "core:slice"
    import "core:strings"

// ODE
    import kdl "../../ode_kdl/src"

///////////////////////////////////////////////////////////////////////////////
// Load

    // Loads a .kdl file, or every .kdl file below a directory, then bakes. On failure nothing
    // changes and errors() lists the problems.
    config__load :: proc(self: ^Config, path: string) -> Error {
        when VALIDATIONS do assert(config__is_valid(self))

        clear(&self.load_errors)
        clear(&self.changed)
        virtual.arena_free_all(&self.error_arena)

        ld: Loader
        ld.config = self
        ld.persist = self.persist
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
        config:    ^Config,
        arena:     virtual.Arena,
        allocator: rt.Allocator, // scratch, dies with the load
        persist:   rt.Allocator, // the Config's arena: nodes, names, file paths
        failed:    bool,

        files: [dynamic]int, // indexes into config.files
        roots: [dynamic][]^Load_Node,

        decls:        [dynamic]Decl,
        decl_by_name: map[string]int,
        decl_by_ix:   map[u32]int,

        links: [dynamic]Link_Decl,
    }

    // A config entity declared in this load (decl >= 0) or already in the Config.
    @(private)
    Ref :: struct {
        decl: int,
        ix:   u32,
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
        ix:          u32,

        has_parent:  bool,        // archetypes
        parent_name: string,
        parent_loc:  kdl.Location,
        parent:      Ref,

        archetype_name: string,   // objects
        archetype_loc:  kdl.Location,
        archetype:      Ref,

        priority: i32,            // metas
        metas:    [dynamic]Meta_Use,
        values:   [dynamic]^Load_Node,
    }

    @(private)
    Link_Decl :: struct {
        node:      ^Load_Node,
        namespace: string,
        flavor:    string,
        from, to:  Ref,
        data:      ^Load_Node,
    }

    @(private)
    TOP_LEVEL_NODES := []string{ "namespace", "archetype", "meta", "surface", "object", "link" }

    @(private)
    loader__init :: proc(ld: ^Loader) {
        a := ld.allocator
        ld.files        = make([dynamic]int, 0, 16, a)
        ld.roots        = make([dynamic][]^Load_Node, 0, 16, a)
        ld.decls        = make([dynamic]Decl, 0, 64, a)
        ld.decl_by_name = make(map[string]int, allocator = a)
        ld.decl_by_ix   = make(map[u32]int, allocator = a)
        ld.links        = make([dynamic]Link_Decl, 0, 64, a)
    }

///////////////////////////////////////////////////////////////////////////////
// Files and parsing

    @(private)
    loader__collect_files :: proc(ld: ^Loader, path: string) {
        paths := make([dynamic]string, 0, 16, ld.allocator)

        if strings.has_suffix(path, ".kdl") {
            append(&paths, path)
        } else {
            walker := os.walker_create_path(path)
            defer os.walker_destroy(&walker)
            for fi in os.walker_walk(&walker) {
                if fi.type == .Regular && strings.has_suffix(fi.name, ".kdl") {
                    append(&paths, strings.clone(fi.fullpath, ld.allocator))
                }
            }
            if p, err := os.walker_error(&walker); err != nil {
                loader__report(ld, path, {}, 0, "", "cannot read %s: %v", p, err)
                return
            }
            if len(paths) == 0 {
                loader__report(ld, path, {}, 0, "", "no .kdl files in %s", path)
                return
            }
            slice.sort(paths[:])
        }

        for p in paths {
            append(&ld.config.files, config__intern(ld.config, p))
            append(&ld.files, len(ld.config.files) - 1)
        }
    }

    @(private)
    loader__parse :: proc(ld: ^Loader) {
        for file in ld.files {
            nodes, _ := load__parse_file(ld, file, ld.config.files[file])
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
                case "archetype", "meta", "surface", "object":
                    loader__declare_entity(ld, node, ns)
                case "link":
                    append(&ld.links, Link_Decl{ node = node, namespace = ns })
                case:
                    loader__error_node(ld, node, suggest(node.name, TOP_LEVEL_NODES), "unknown node %q", node.name)
                }
            }
        }
    }

    @(private)
    loader__declare_entity :: proc(ld: ^Loader, node: ^Load_Node, ns: string) {
        cfg := ld.config
        short, ok := loader__name_arg(ld, node)
        if !ok do return

        name := loader__qualify(ld, ns, short)
        kind: Config_Kind
        switch node.name {
        case "archetype": kind = .Archetype
        case "meta":      kind = .Meta
        case "surface":   kind = .Surface
        case "object":    kind = .Object
        }

        key := loader__key(ld, name, kind == .Object)
        if prev, dup := ld.decl_by_name[key]; dup {
            first := ld.decls[prev].node
            loader__error_node(ld, node, "", "%q is declared twice; first at %s:%d", name, cfg.files[first.file], first.location.line)
            return
        }

        d := Decl{
            kind      = kind,
            name      = name,
            namespace = ns,
            node      = node,
            parent    = Ref{ decl = -1, ix = NO_ID },
            archetype = Ref{ decl = -1, ix = NO_ID },
            ix        = NO_ID,
            metas     = make([dynamic]Meta_Use, 0, 2, ld.allocator),
            values    = make([dynamic]^Load_Node, 0, 4, ld.allocator),
        }

        if ix, found := config__find_named(cfg, name, kind == .Object); found {
            e := config__entity(cfg, ix)
            if e.kind != kind || e.config != cfg {
                loader__error_node(ld, node, "", "%q already exists as a %v", name, e.kind)
                return
            }
            d.existing = true
            d.ix = ix
            ld.decl_by_ix[ix] = len(ld.decls)
        }

        for p in node.props {
            s, is_string := p.value.variant.(string)
            switch {
            case p.name == "parent" && kind == .Archetype:
                if !is_string {
                    loader__error_at(ld, node, p.location, len(p.name), "", "parent must be a name")
                    continue
                }
                d.has_parent = true
                d.parent_name = s
                d.parent_loc = p.location
            case p.name == "archetype" && kind == .Object:
                if !is_string {
                    loader__error_at(ld, node, p.location, len(p.name), "", "archetype must be a name")
                    continue
                }
                d.archetype_name = s
                d.archetype_loc = p.location
            case p.name == "priority" && kind == .Meta:
                if v, is_int := loader__int_value(ld, node, p.value, p.location, "priority"); is_int do d.priority = i32(v)
            case:
                loader__error_at(ld, node, p.location, len(p.name), "", "%s does not take %s=", node.name, p.name)
            }
        }

        if kind == .Object && d.archetype_name == "" {
            loader__error_node(ld, node, "", "object %q needs archetype=\"Name\"", name)
            return
        }

        ld.decl_by_name[key] = len(ld.decls)
        append(&ld.decls, d)
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
                case:
                    d.parent = ref
                    d.has_parent = true
                }
            }

            if d.kind == .Object {
                ref, kind, found := loader__find_config(ld, d.namespace, d.archetype_name)
                switch {
                case !found:
                    loader__error_at(ld, d.node, d.archetype_loc, len("archetype"), loader__suggest_config(ld, d.namespace, d.archetype_name, .Archetype), "unknown archetype %q", d.archetype_name)
                case kind != .Archetype:
                    loader__error_at(ld, d.node, d.archetype_loc, len("archetype"), "", "%q is a %v, not an archetype", d.archetype_name, kind)
                case:
                    d.archetype = ref
                }
            }

            for child in d.node.children do loader__item(ld, i, child)
        }
        if !ld.failed do loader__check_cycles(ld)

        for &l in ld.links do loader__resolve_link(ld, &l)
    }

    // A meta on an archetype or surface; anything else is a value authored under its own name.
    @(private)
    loader__item :: proc(ld: ^Loader, di: int, node: ^Load_Node) {
        d := &ld.decls[di]

        if node.name == "meta" {
            if d.kind == .Meta {
                loader__error_node(ld, node, "", "a meta cannot carry metas")
                return
            }
            if d.kind == .Object {
                loader__error_node(ld, node, "", "an object cannot carry metas; put them on its archetype")
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

        append(&d.values, node)
    }

    @(private)
    loader__resolve_link :: proc(ld: ^Loader, l: ^Link_Decl) {
        node := l.node
        name, ok := loader__name_arg(ld, node)
        if !ok do return
        l.flavor = name

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
        payload := new(Load_Node, ld.persist)
        payload^ = Load_Node{ name = name, location = node.location, file = node.file, children = node.children }
        l.data = payload
    }

    // The parent of ref as it will be after this load.
    @(private)
    loader__parent_step :: proc(ld: ^Loader, ref: Ref) -> (Ref, bool) {
        if ref.decl >= 0 {
            d := &ld.decls[ref.decl]
            return d.parent, d.has_parent
        }
        if i, reloaded := ld.decl_by_ix[ref.ix]; reloaded {
            d := &ld.decls[i]
            return d.parent, d.has_parent
        }
        e := config__entity(ld.config, ref.ix)
        if e == nil || e.parent == NO_ID do return {}, false
        return Ref{ decl = -1, ix = e.parent }, true
    }

    @(private)
    loader__check_cycles :: proc(ld: ^Loader) {
        limit := len(ld.decls) + len(ld.config.root.entities) + 1
        for d, i in ld.decls {
            if !d.has_parent do continue
            cur := d.parent
            for _ in 0..<limit {
                if cur.decl == i || (cur.decl < 0 && d.existing && cur.ix == d.ix) {
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
        cfg := ld.config

        // entities; reloaded ones start over
        for &d in ld.decls {
            if d.existing {
                e := config__entity(cfg, d.ix)
                clear(&e.authored)
                clear(&e.metas)
                e.parent = NO_ID
            } else {
                d.ix = config__create(cfg, d.name, d.kind) or_return
            }
            append(&cfg.changed, d.ix)
        }

        config__clear_links(cfg)

        for d in ld.decls {
            e := config__entity(cfg, d.ix)

            switch d.kind {
            case .Archetype: if d.has_parent do e.parent = loader__ref_ix(ld, d.parent)
            case .Object:    e.archetype = loader__ref_ix(ld, d.archetype)
            case .Meta:      e.priority = d.priority
            case .Surface, .None:
            }

            for m in d.metas {
                config__attach(cfg, d.ix, d.kind, meta_id(loader__ref_ix(ld, m.ref)), m.priority) or_return
            }
            for v in d.values do e.authored[name_hash(v.name)] = Authored{ node = v }
        }

        for l in ld.links {
            config__add_link(cfg, l.flavor, loader__ref_ix(ld, l.from), loader__ref_ix(ld, l.to), l.data) or_return
        }

        return config__bake(cfg)
    }

///////////////////////////////////////////////////////////////////////////////
// Private helpers

    @(private)
    loader__report :: proc(ld: ^Loader, file: string, loc: kdl.Location, span: int, suggestion: string, format: string, args: ..any) {
        ld.failed = true
        config__report(ld.config, file, loc, span, suggestion, format, ..args)
    }

    @(private)
    loader__error_at :: proc(ld: ^Loader, node: ^Load_Node, loc: kdl.Location, span: int, suggestion: string, format: string, args: ..any) {
        loader__report(ld, ld.config.files[node.file], loc, span, suggestion, format, ..args)
    }

    @(private)
    loader__error_node :: proc(ld: ^Loader, node: ^Load_Node, suggestion: string, format: string, args: ..any) {
        loader__report(ld, ld.config.files[node.file], node.location, len(node.name), suggestion, format, ..args)
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

    // Objects and config entities have separate namespaces, so their keys must differ.
    @(private)
    loader__key :: proc(ld: ^Loader, name: string, objects: bool) -> string {
        return objects ? strings.concatenate({ "object ", name }, ld.allocator) : name
    }

    // Tries ns.name first, then name as written.
    @(private)
    loader__find_config :: proc(ld: ^Loader, ns: string, name: string) -> (Ref, Config_Kind, bool) {
        candidates := [2]string{ loader__qualify(ld, ns, name), name }
        for c in candidates {
            if i, in_load := ld.decl_by_name[loader__key(ld, c, false)]; in_load {
                return Ref{ decl = i, ix = ld.decls[i].ix }, ld.decls[i].kind, true
            }
            if ix, kind, found := config__find_config(ld.config, c); found do return Ref{ decl = -1, ix = ix }, kind, true
        }
        return Ref{ decl = -1, ix = NO_ID }, .None, false
    }

    @(private)
    loader__find_object :: proc(ld: ^Loader, ns: string, name: string) -> (Ref, bool) {
        candidates := [2]string{ loader__qualify(ld, ns, name), name }
        for c in candidates {
            if i, in_load := ld.decl_by_name[loader__key(ld, c, true)]; in_load do return Ref{ decl = i, ix = ld.decls[i].ix }, true
            if ix, found := config__find_named(ld.config, c, true); found do return Ref{ decl = -1, ix = ix }, true
        }
        return Ref{ decl = -1, ix = NO_ID }, false
    }

    @(private)
    loader__meta_priority :: proc(ld: ^Loader, ref: Ref) -> i32 {
        if ref.decl >= 0 do return ld.decls[ref.decl].priority
        e := config__entity(ld.config, ref.ix)
        return e == nil ? 0 : e.priority
    }

    @(private)
    loader__ref_ix :: proc(ld: ^Loader, ref: Ref) -> u32 {
        return ref.decl >= 0 ? ld.decls[ref.decl].ix : ref.ix
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
        for c := ld.config; c != nil; c = c.base {
            for ix in c.mine {
                e := config__entity(c, ix)
                if e != nil && e.kind == kind && e.name != "" do append(&candidates, loader__shorten(ns, e.name))
            }
        }
        return suggest(name, candidates[:])
    }

    @(private)
    loader__suggest_object :: proc(ld: ^Loader, ns: string, name: string) -> string {
        candidates := make([dynamic]string, 0, 64, context.temp_allocator)
        for d in ld.decls {
            if d.kind == .Object do append(&candidates, loader__shorten(ns, d.name))
        }
        return suggest(name, candidates[:])
    }
