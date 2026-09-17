/*
    2026 (c) Oleh, https://github.com/zm69

    Config: everything designers author - archetypes, metas, surfaces and the objects declared in
    KDL - as plain records in one arena, with the values they carry kept as the parsed KDL nodes
    they came from. A Config must not be moved after config__init.

    Configs chain: one created with base = another can inherit its archetypes and read its values.
    The root of a chain owns the entity and link arrays for all of them, so ids are unique across
    the chain.
*/
package ode_dos

// Base
    import rt "base:runtime"

// Core
    import "core:mem/virtual"

///////////////////////////////////////////////////////////////////////////////
// Config

    Config_Options :: struct {
        base:      ^Config,      // inherit from this Config; nil for a root
        user_data: rawptr,       // how tools and build code reach your data
        allocator: rt.Allocator, // default: context.allocator
    }

    Config_Kind :: enum u8 {
        None = 0,
        Archetype,
        Meta,
        Surface,
        Object,
    }

    // A meta attached to an archetype or surface.
    Attachment :: struct {
        meta:     meta_id,
        priority: i32,
    }

    // A value as the files authored it, and whether anything has read it.
    Authored :: struct {
        node: ^Load_Node,
        read: bool,
    }

    // A value after inheritance, and the entity it came from.
    Baked :: struct {
        node: ^Load_Node,
        from: u32,
    }

    @(private)
    Entity :: struct {
        kind:      Config_Kind,
        config:    ^Config,
        name:      string,
        name_hash: u64,

        parent:    u32, // archetypes: the archetype above; NO_ID when none
        archetype: u32, // objects
        priority:  i32, // metas: default attach priority

        metas:     [dynamic]Attachment,
        authored:  map[u64]Authored,
        baked:     map[u64]Baked, // archetypes and surfaces
        out_links: [dynamic]int,
        in_links:  [dynamic]int,
    }

    @(private)
    Link_Record :: struct {
        flavor:      string,
        flavor_hash: u64,
        from:        u32,
        to:          u32,
        data:        ^Load_Node,
        read:        bool,
    }

    Config :: struct {
        initialized: bool,
        opts:        Config_Options,
        allocator:   rt.Allocator,

        base:    ^Config,
        root:    ^Config,
        derived: int,

        arena:     virtual.Arena, // parsed nodes, names and file paths
        persist:   rt.Allocator,  // the arena's allocator

        // the root holds these for its whole chain
        entities: [dynamic]Entity,
        links:    [dynamic]Link_Record,

        mine:         [dynamic]u32, // entities this Config declared
        mine_links:   [dynamic]int, // links this Config authored
        config_names: map[u64]u32,  // archetypes, metas and surfaces
        object_names: map[u64]u32,

        files:       [dynamic]string, // paths, for diagnostics after the load
        changed:     [dynamic]u32,
        load_errors: [dynamic]Load_Error,
        error_arena: virtual.Arena,
    }

    config__is_valid :: proc(self: ^Config) -> bool {
        return self != nil && self.initialized && self.root != nil
    }

    config__init :: proc(self: ^Config, opts := Config_Options{}, loc := #caller_location) -> (err: Error) {
        when VALIDATIONS {
            assert(self != nil, loc = loc)
            assert(!self.initialized, "Config is already initialized", loc = loc)
            assert(opts.base == nil || config__is_valid(opts.base), "base Config is not initialized", loc = loc)
        }
        defer if err != nil do config__terminate(self)

        self.opts = opts
        self.allocator = opts.allocator
        if self.allocator.procedure == nil do self.allocator = context.allocator

        self.base = opts.base
        self.root = opts.base != nil ? opts.base.root : self
        if self.base != nil do self.base.derived += 1

        virtual.arena_init_growing(&self.arena) or_return
        self.persist = virtual.arena_allocator(&self.arena)
        virtual.arena_init_growing(&self.error_arena) or_return

        if self.root == self {
            self.entities = make([dynamic]Entity, 0, 64, self.allocator) or_return
            self.links = make([dynamic]Link_Record, 0, 32, self.allocator) or_return
        }

        self.mine         = make([dynamic]u32, 0, 32, self.allocator) or_return
        self.mine_links   = make([dynamic]int, 0, 16, self.allocator) or_return
        self.config_names = make(map[u64]u32, allocator = self.allocator)
        self.object_names = make(map[u64]u32, allocator = self.allocator)
        self.files        = make([dynamic]string, 0, 8, self.allocator) or_return
        self.changed      = make([dynamic]u32, 0, 32, self.allocator) or_return
        self.load_errors  = make([dynamic]Load_Error, 0, 16, self.allocator) or_return

        self.initialized = true
        return nil
    }

    // Safe on a partially initialized Config. Terminate derived Configs first.
    config__terminate :: proc(self: ^Config) {
        if self == nil do return
        when VALIDATIONS do assert(self.derived == 0, "terminate the Configs based on this one first")

        for ix in self.mine {
            e := &self.root.entities[ix]
            delete(e.metas)
            delete(e.authored)
            delete(e.baked)
            delete(e.out_links)
            delete(e.in_links)
            e^ = {}
        }
        if self.base != nil do self.base.derived -= 1

        if self.root == self {
            delete(self.entities)
            delete(self.links)
        }

        delete(self.mine)
        delete(self.mine_links)
        delete(self.config_names)
        delete(self.object_names)
        delete(self.files)
        delete(self.changed)
        delete(self.load_errors)

        virtual.arena_destroy(&self.error_arena)
        virtual.arena_destroy(&self.arena)

        self^ = {}
    }

    config__user_data :: proc(self: ^Config) -> rawptr {
        return self.opts.user_data
    }

///////////////////////////////////////////////////////////////////////////////
// Private

    @(private)
    config__entity :: #force_inline proc(self: ^Config, ix: u32) -> ^Entity {
        if int(ix) >= len(self.root.entities) do return nil
        e := &self.root.entities[ix]
        return e.kind == .None ? nil : e
    }

    @(private)
    config__kind_of :: proc(self: ^Config, ix: u32) -> Config_Kind {
        e := config__entity(self, ix)
        return e == nil ? .None : e.kind
    }

    @(private)
    config__is :: proc(self: ^Config, ix: u32, kind: Config_Kind) -> bool {
        return config__kind_of(self, ix) == kind
    }

    // A fresh entity, declared by this Config.
    @(private)
    config__new_entity :: proc(self: ^Config, kind: Config_Kind, name: string) -> (ix: u32, err: Error) {
        e := Entity{
            kind      = kind,
            config    = self,
            parent    = NO_ID,
            archetype = NO_ID,
            metas     = make([dynamic]Attachment, 0, 2, self.allocator) or_return,
            authored  = make(map[u64]Authored, allocator = self.allocator),
            out_links = make([dynamic]int, 0, 2, self.allocator) or_return,
            in_links  = make([dynamic]int, 0, 2, self.allocator) or_return,
        }
        if kind == .Archetype || kind == .Surface do e.baked = make(map[u64]Baked, allocator = self.allocator)

        if name != "" {
            e.name = config__intern(self, name)
            e.name_hash = name_hash(name)
        }

        ix = u32(len(self.root.entities))
        append(&self.root.entities, e) or_return
        append(&self.mine, ix) or_return

        if name != "" {
            index := kind == .Object ? &self.object_names : &self.config_names
            index^[e.name_hash] = ix
        }
        return ix, nil
    }
