/*
    2026 (c) Oleh, https://github.com/zm69

    Config: one ODE_ECS Database holding everything designers author - archetypes, metas, surfaces
    and the objects declared in KDL - together with the property, flag and link storage that
    describes them. A Config must not be moved after config__init; its tables point into it.

    Configs chain: one created with base = another shares that Config's entity id space, so its
    archetypes can inherit from the base's. The root of a chain owns the archetype hierarchy, the
    meta attachments and the object-to-archetype table for every Config in it.
*/
package ode_dos

// Base
    import rt "base:runtime"

// Core
    import "core:mem/virtual"

// ODE
    import ecs "../../ode_ecs/src"
    import oc_maps "../../ode_ecs/src/ode_core/maps"

///////////////////////////////////////////////////////////////////////////////
// Config

    Config_Options :: struct {
        base:        ^Config,      // inherit from this Config; nil for a root
        max_derived: int,          // Configs that may chain onto this root; default 4
        keep_names:  Maybe(bool),  // default: true in debug builds
        user_data:   rawptr,       // how decoders and tools reach your data
        allocator:   rt.Allocator, // default: context.allocator
    }

    Config_Kind :: enum u8 {
        None = 0,
        Archetype,
        Meta,
        Surface,
        Object,
    }

    Config :: struct {
        state:      ecs.Object_State,
        opts:       Config_Options,
        allocator:  rt.Allocator,
        keep_names: bool,

        base:    ^Config, // nil for a root
        root:    ^Config, // self for a root
        derived: int,     // Configs based on this one

        overbase: ecs.Overbase,  // the root's id space; every Config in the chain attaches to it
        db:       ecs.Database,

        // the root holds these for its whole chain
        chain:           [dynamic]^Config,
        relations:       ecs.Relations_Table,
        attachments:     ecs.Pair_Table(Attachment_Data),
        archetype_table: ecs.Table(archetype_id), // object -> archetype

        // indexed by eid.ix, for this Config's own entities
        config_eid:    []ecs.entity_id,
        config_kind:   []Config_Kind,
        config_hash:   []u64,
        meta_priority: []i32,

        config_names:   oc_maps.Rh_Map64, // name hash -> eid.ix, archetypes/metas/surfaces
        object_names:   oc_maps.Rh_Map64, // name hash -> eid.ix, objects
        config_strings: map[u64]string,
        object_strings: map[u64]string,

        bindings:    [dynamic]Binding,
        storages:    [dynamic]Storage, // what grows with the Database
        flag_groups:  [dynamic]^Flag_Group,
        effect_slots: [dynamic]^Effect_Bit,

        meta_scratch:  []Attachment,
        value_strings: [dynamic]string,

        changed:     [dynamic]ecs.entity_id, // what the last load touched
        load_errors: [dynamic]Load_Error,
        error_arena: virtual.Arena,

        config_cap:      int,
        attachments_cap: int,
    }

    config__is_valid :: proc(self: ^Config) -> bool {
        if self == nil do return false
        if self.state != .Normal do return false
        if self.root == nil do return false
        return true
    }

    config__init :: proc(self: ^Config, opts := Config_Options{}, loc := #caller_location) -> (err: Error) {
        when VALIDATIONS {
            assert(self != nil, loc = loc)
            assert(self.state == .Not_Initialized, "Config is already initialized", loc = loc)
            assert(opts.base == nil || config__is_valid(opts.base), "base Config is not initialized", loc = loc)
        }
        defer if err != nil do config__terminate(self)

        self.opts = opts
        self.allocator = opts.allocator
        if self.allocator.procedure == nil do self.allocator = context.allocator
        self.keep_names = opts.keep_names.? or_else ODIN_DEBUG
        self.base = opts.base
        self.root = opts.base != nil ? opts.base.root : self

        self.config_cap = self.base != nil ? self.root.config_cap : 1
        self.attachments_cap = 1

        if self.base == nil {
            derived := opts.max_derived > 0 ? opts.max_derived : DEFAULT_MAX_DERIVED
            ecs_err(ecs.overbase_init(&self.overbase, u32(self.config_cap), derived + 1, self.allocator)) or_return
            self.chain = make([dynamic]^Config, 0, derived + 1, self.allocator) or_return
        }
        ecs_err(ecs.init_from_overbase(&self.db, &self.root.overbase, self.allocator)) or_return

        n := self.config_cap
        self.config_eid    = make([]ecs.entity_id, n, self.allocator) or_return
        self.config_kind   = make([]Config_Kind, n, self.allocator) or_return
        self.config_hash   = make([]u64, n, self.allocator) or_return
        self.meta_priority = make([]i32, n, self.allocator) or_return

        oc_maps.rh_map64__init(&self.config_names, oc_maps.rh_map64__capacity_for(n), self.allocator) or_return
        oc_maps.rh_map64__init(&self.object_names, oc_maps.rh_map64__capacity_for(n), self.allocator) or_return
        if self.keep_names {
            self.config_strings = make(map[u64]string, allocator = self.allocator)
            self.object_strings = make(map[u64]string, allocator = self.allocator)
        }

        self.bindings      = make([dynamic]Binding, 0, 32, self.allocator) or_return
        self.storages      = make([dynamic]Storage, 0, 32, self.allocator) or_return
        self.flag_groups   = make([dynamic]^Flag_Group, 0, 4, self.allocator) or_return
        self.effect_slots  = make([dynamic]^Effect_Bit, 0, 8, self.allocator) or_return
        self.meta_scratch  = make([]Attachment, self.attachments_cap, self.allocator) or_return
        self.value_strings = make([dynamic]string, 0, 64, self.allocator) or_return
        self.changed       = make([dynamic]ecs.entity_id, 0, 32, self.allocator) or_return
        self.load_errors   = make([dynamic]Load_Error, 0, 16, self.allocator) or_return
        virtual.arena_init_growing(&self.error_arena) or_return

        self.state = .Normal

        if self.base == nil {
            ecs_err(ecs.relations_init(&self.relations, &self.db, n)) or_return
            ecs_err(ecs.pair_init(&self.attachments, &self.db, holders_cap = n, pairs_cap = self.attachments_cap)) or_return
            ecs_err(ecs.table_init(&self.archetype_table, &self.db, n)) or_return
        } else {
            self.base.derived += 1
        }

        _, aerr := append(&self.root.chain, self)
        if aerr != nil do return aerr

        return nil
    }

    // Safe on a partially initialized Config. Terminate derived Configs first.
    config__terminate :: proc(self: ^Config) {
        if self == nil do return
        when VALIDATIONS do assert(self.derived == 0, "terminate the Configs based on this one first")

        if self.root != nil && self.root.chain != nil {
            for c, i in self.root.chain {
                if c == self {
                    ordered_remove(&self.root.chain, i)
                    break
                }
            }
        }
        if self.base != nil do self.base.derived -= 1

        if self.root == self {
            if self.archetype_table.state == .Normal do _ = ecs.table_terminate(&self.archetype_table)
            if self.attachments.state == .Normal do _ = ecs.pair_terminate(&self.attachments)
            if self.relations.state == .Normal do _ = ecs.relations_terminate(&self.relations)
        }

        if self.db.state == .Normal do _ = ecs.terminate(&self.db)
        if self.root == self && self.overbase.state == .Normal do _ = ecs.overbase_terminate(&self.overbase)
        if self.chain != nil do delete(self.chain)

        if self.config_names.items != nil do _ = oc_maps.rh_map64__terminate(&self.config_names, self.allocator)
        if self.object_names.items != nil do _ = oc_maps.rh_map64__terminate(&self.object_names, self.allocator)

        delete(self.config_eid, self.allocator)
        delete(self.config_kind, self.allocator)
        delete(self.config_hash, self.allocator)
        delete(self.meta_priority, self.allocator)

        for _, s in self.config_strings do delete(s, self.allocator)
        delete(self.config_strings)
        for _, s in self.object_strings do delete(s, self.allocator)
        delete(self.object_strings)

        for b in self.bindings do delete(b.name, self.allocator)
        delete(self.bindings)
        delete(self.storages)

        for g in self.flag_groups do free(g, self.allocator)
        delete(self.flag_groups)

        for e in self.effect_slots do free(e, self.allocator)
        delete(self.effect_slots)

        delete(self.meta_scratch, self.allocator)
        for s in self.value_strings do delete(s, self.allocator)
        delete(self.value_strings)
        delete(self.changed)
        delete(self.load_errors)
        virtual.arena_destroy(&self.error_arena)

        self^ = {}
    }

    config__db :: proc(self: ^Config) -> ^ecs.Database {
        when VALIDATIONS do assert(config__is_valid(self))
        return &self.db
    }

    config__user_data :: proc(self: ^Config) -> rawptr {
        return self.opts.user_data
    }

///////////////////////////////////////////////////////////////////////////////
// Private

    // The Config in the chain that owns eid, or nil.
    @(private)
    config__owner :: proc(self: ^Config, eid: ecs.entity_id) -> ^Config {
        for c := self; c != nil; c = c.base {
            if int(eid.ix) < len(c.config_eid) && c.config_eid[eid.ix] == eid && c.config_kind[eid.ix] != .None do return c
        }
        return nil
    }

    @(private)
    config__kind_of :: proc(self: ^Config, eid: ecs.entity_id) -> Config_Kind {
        c := config__owner(self, eid)
        return c == nil ? .None : c.config_kind[eid.ix]
    }

    @(private)
    config__config_is :: proc(self: ^Config, eid: ecs.entity_id, kind: Config_Kind) -> bool {
        return config__kind_of(self, eid) == kind
    }

    @(private)
    config__meta_priority_of :: proc(self: ^Config, eid: ecs.entity_id) -> i32 {
        c := config__owner(self, eid)
        return c == nil ? 0 : c.meta_priority[eid.ix]
    }
