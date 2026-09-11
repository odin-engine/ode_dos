/*
    2026 (c) Oleh, https://github.com/zm69

    World: the runtime database, the config Overbase with its config sets, and the name
    indexes. A World must not be moved after world__init; its databases are referenced
    by address.
*/
package ode_dos

// Base
    import rt "base:runtime"

// Core
    import "core:mem/virtual"
    import "core:strings"

// ODE
    import ecs "../../ode_ecs/src"
    import oc "../../ode_ecs/src/ode_core"
    import oc_maps "../../ode_ecs/src/ode_core/maps"

///////////////////////////////////////////////////////////////////////////////
// World_Config

    World_Config :: struct {
        max_archetypes:  int,          // archetypes + metas + surfaces across all sets; default 2_048
        max_config_sets: int,          // default 4: CORE plus three of your own.
        max_objects:     int,          // live instances; default 100_000
        max_links:       int,          // per link flavor unless overridden; default 32_768
        max_attachments: int,          // meta attachments across all archetypes and surfaces; default 4 * max_archetypes
        max_named_objects: int,        // objects that can have a name; default 4_096, at most max_objects
        keep_names:      Maybe(bool),  // default: true in debug builds
        user_data:       rawptr,       // how spawn hooks and effects reach your tables
        allocator:       rt.Allocator, // default: context.allocator
    }

///////////////////////////////////////////////////////////////////////////////
// World

    Config_Kind :: enum u8 {
        None = 0,
        Archetype,
        Meta,
        Surface,
    }

    Config_Set :: struct {
        db:     ecs.Database,
        name:   string,
        loaded: bool,
    }

    World :: struct {
        state:      ecs.Object_State,
        cfg:        World_Config,
        allocator:  rt.Allocator,
        keep_names: bool,

        runtime_db:      ecs.Database,
        config_overbase: ecs.Overbase,
        sets:            []Config_Set,
        relations:       ecs.Relations_Table,          // archetype forest, on CORE
        attachments:     ecs.Pair_Table(Attachment_Data), // holder -> meta, on CORE

        // indexed by config eid.ix
        config_eid:    []ecs.entity_id,
        config_kind:   []Config_Kind,
        config_set_of: []config_set_id,
        config_hash:   []u64,

        config_names: oc_maps.Rh_Map64, // name hash -> config eid.ix
        object_names: oc_maps.Rh_Map64, // name hash -> object eid.ix
        config_strings: map[u64]string, // only when keep_names
        object_strings: map[u64]string, // only when keep_names

        archetype_table:   ecs.Table(archetype_id), // object -> archetype, runtime
        object_name_table: ecs.Compact_Table(u64),  // named object -> name hash, runtime
        spawn_hooks:       [MAX_SPAWN_HOOKS]Spawn_Hook,
        spawn_hooks_len:   int,
        bindings:          [dynamic]Binding,
        bakers:            [dynamic]Baker,
        flag_groups:       [dynamic]^Flag_Group,
        meta_scratch:      []Attachment, // bake's buffer for one holder's metas
        effects:           [dynamic]Effect_Entry,
        effect_tables:     [dynamic]^ecs.Flags_Table,
        meta_priority:     []i32,             // default attach priority per meta, by config eid.ix
        load_errors:       [dynamic]Load_Error,
        error_arena:       virtual.Arena,     // strings of load_errors
        value_strings:     [dynamic]string,   // strings read from KDL into values
    }

    world__is_valid :: proc(self: ^World) -> bool {
        if self == nil do return false
        if self.state != .Normal do return false
        if self.sets == nil do return false
        return true
    }

    world__init :: proc(self: ^World, cfg := World_Config{}, loc := #caller_location) -> (err: Error) {
        when VALIDATIONS {
            assert(self != nil, loc = loc)
            assert(self.state == .Not_Initialized, "World is already initialized", loc = loc)
        }
        defer if err != nil do world__terminate(self)

        self.cfg = cfg
        if self.cfg.max_archetypes <= 0 do self.cfg.max_archetypes = DEFAULT_MAX_ARCHETYPES
        if self.cfg.max_config_sets <= 0 do self.cfg.max_config_sets = DEFAULT_MAX_CONFIG_SETS
        if self.cfg.max_objects <= 0 do self.cfg.max_objects = DEFAULT_MAX_OBJECTS
        if self.cfg.max_links <= 0 do self.cfg.max_links = DEFAULT_MAX_LINKS
        if self.cfg.max_attachments <= 0 do self.cfg.max_attachments = 4 * self.cfg.max_archetypes
        if self.cfg.max_named_objects <= 0 do self.cfg.max_named_objects = DEFAULT_MAX_NAMED_OBJECTS
        self.cfg.max_named_objects = min(self.cfg.max_named_objects, self.cfg.max_objects)

        self.allocator = cfg.allocator
        if self.allocator.procedure == nil do self.allocator = context.allocator
        self.cfg.allocator = self.allocator
        self.keep_names = cfg.keep_names.? or_else ODIN_DEBUG

        ecs_err(ecs.init(&self.runtime_db, u32(self.cfg.max_objects), self.allocator)) or_return
        ecs_err(ecs.table_init(&self.archetype_table, &self.runtime_db, self.cfg.max_objects)) or_return
        ecs_err(ecs.compact_table_init(&self.object_name_table, &self.runtime_db, self.cfg.max_named_objects)) or_return
        ecs_err(ecs.overbase_init(&self.config_overbase, u32(self.cfg.max_archetypes), self.cfg.max_config_sets, self.allocator)) or_return

        n := self.cfg.max_archetypes
        self.sets          = make([]Config_Set, self.cfg.max_config_sets, self.allocator) or_return
        self.config_eid    = make([]ecs.entity_id, n, self.allocator) or_return
        self.config_kind   = make([]Config_Kind, n, self.allocator) or_return
        self.config_set_of = make([]config_set_id, n, self.allocator) or_return
        self.config_hash   = make([]u64, n, self.allocator) or_return

        oc_maps.rh_map64__init(&self.config_names, oc_maps.rh_map64__capacity_for(n), self.allocator) or_return
        oc_maps.rh_map64__init(&self.object_names, oc_maps.rh_map64__capacity_for(self.cfg.max_objects), self.allocator) or_return
        if self.keep_names {
            self.config_strings = make(map[u64]string, allocator = self.allocator)
            self.object_strings = make(map[u64]string, allocator = self.allocator)
        }
        self.bindings = make([dynamic]Binding, 0, 32, self.allocator) or_return
        self.bakers = make([dynamic]Baker, 0, 32, self.allocator) or_return
        self.flag_groups = make([dynamic]^Flag_Group, 0, 4, self.allocator) or_return
        self.meta_scratch = make([]Attachment, self.cfg.max_attachments, self.allocator) or_return
        self.effects = make([dynamic]Effect_Entry, 0, 16, self.allocator) or_return
        self.effect_tables = make([dynamic]^ecs.Flags_Table, 0, 1, self.allocator) or_return
        self.meta_priority = make([]i32, n, self.allocator) or_return
        self.load_errors = make([dynamic]Load_Error, 0, 16, self.allocator) or_return
        self.value_strings = make([dynamic]string, 0, 64, self.allocator) or_return
        virtual.arena_init_growing(&self.error_arena) or_return

        self.state = .Normal
        world__open_config_set(self, CORE, "core") or_return

        core := &self.sets[CORE].db
        ecs_err(ecs.relations_init(&self.relations, core, n)) or_return
        ecs_err(ecs.pair_init(&self.attachments, core, holders_cap = n, pairs_cap = self.cfg.max_attachments)) or_return

        return nil
    }

    // Safe on a partially initialized World.
    world__terminate :: proc(self: ^World) {
        if self == nil do return

        for &s in self.sets {
            if !s.loaded do continue
            _ = ecs.terminate(&s.db)
            delete(s.name, self.allocator)
        }
        if self.sets != nil do delete(self.sets, self.allocator)

        if self.config_overbase.state == .Normal do _ = ecs.overbase_terminate(&self.config_overbase)
        if self.runtime_db.state == .Normal do _ = ecs.terminate(&self.runtime_db)

        if self.config_names.items != nil do _ = oc_maps.rh_map64__terminate(&self.config_names, self.allocator)
        if self.object_names.items != nil do _ = oc_maps.rh_map64__terminate(&self.object_names, self.allocator)

        delete(self.config_eid, self.allocator)
        delete(self.config_kind, self.allocator)
        delete(self.config_set_of, self.allocator)
        delete(self.config_hash, self.allocator)

        for _, s in self.config_strings do delete(s, self.allocator)
        delete(self.config_strings)
        for _, s in self.object_strings do delete(s, self.allocator)
        delete(self.object_strings)

        for b in self.bindings do delete(b.name, self.allocator)
        delete(self.bindings)

        for g in self.flag_groups do free(g, self.allocator)
        delete(self.flag_groups)
        delete(self.bakers)
        delete(self.meta_scratch, self.allocator)

        for table in self.effect_tables do free(table, self.allocator)
        delete(self.effect_tables)
        delete(self.effects)

        delete(self.meta_priority, self.allocator)
        delete(self.load_errors)
        for s in self.value_strings do delete(s, self.allocator)
        delete(self.value_strings)
        virtual.arena_destroy(&self.error_arena)

        self^ = {}
    }

    world__runtime :: proc(self: ^World) -> ^ecs.Database {
        when VALIDATIONS do assert(world__is_valid(self))
        return &self.runtime_db
    }

    world__user_data :: proc(self: ^World) -> rawptr {
        return self.cfg.user_data
    }

///////////////////////////////////////////////////////////////////////////////
// Config sets

    world__create_config_set :: proc(self: ^World, name: string) -> (config_set_id, Error) {
        when VALIDATIONS do assert(world__is_valid(self))

        if _, exists := world__find_config_set(self, name); exists do return NO_CONFIG_SET, DOS_Error.Name_Already_Exists

        for s, i in self.sets {
            if s.loaded do continue
            if err := world__open_config_set(self, config_set_id(i), name); err != nil do return NO_CONFIG_SET, err
            return config_set_id(i), nil
        }

        return NO_CONFIG_SET, oc.Core_Error.Container_Is_Full
    }

    world__find_config_set :: proc(self: ^World, name: string) -> (config_set_id, bool) {
        for s, i in self.sets {
            if s.loaded && s.name == name do return config_set_id(i), true
        }
        return NO_CONFIG_SET, false
    }

    world__config_db :: proc(self: ^World, set := CORE) -> ^ecs.Database {
        when VALIDATIONS do assert(world__set_is_loaded(self, set), "config set is not loaded")
        return &self.sets[set].db
    }

    // Destroys the set's config entities and frees its slot; CORE cannot be unloaded.
    world__unload_config_set :: proc(self: ^World, set: config_set_id) -> Error {
        when VALIDATIONS do assert(world__is_valid(self))

        if set == CORE do return DOS_Error.Cannot_Unload_Core
        if !world__set_is_loaded(self, set) do return DOS_Error.Config_Set_Not_Found

        for kind, ix in self.config_kind {
            if kind == .None || self.config_set_of[ix] != set do continue
            ecs_err(ecs.destroy_entity(&self.config_overbase, self.config_eid[ix])) or_return
            world__unregister_config(self, ix)
        }

        s := &self.sets[set]
        ecs_err(ecs.terminate(&s.db)) or_return
        delete(s.name, self.allocator)
        s^ = {}

        // what was declared in the set lived in its database
        for i := len(self.bakers) - 1; i >= 0; i -= 1 {
            if self.bakers[i].set == set do ordered_remove(&self.bakers, i)
        }
        for i := len(self.flag_groups) - 1; i >= 0; i -= 1 {
            if self.flag_groups[i].set != set do continue
            free(self.flag_groups[i], self.allocator)
            ordered_remove(&self.flag_groups, i)
        }
        for i := len(self.bindings) - 1; i >= 0; i -= 1 {
            if self.bindings[i].set != set do continue
            delete(self.bindings[i].name, self.allocator)
            ordered_remove(&self.bindings, i)
        }

        return nil
    }

    @(private)
    world__set_is_loaded :: proc(self: ^World, set: config_set_id) -> bool {
        return int(set) >= 0 && int(set) < len(self.sets) && self.sets[set].loaded
    }

    @(private)
    world__open_config_set :: proc(self: ^World, set: config_set_id, name: string) -> Error {
        s := &self.sets[set]
        ecs_err(ecs.init_from_overbase(&s.db, &self.config_overbase, self.allocator)) or_return

        copy, err := strings.clone(name, self.allocator)
        if err != nil {
            _ = ecs.terminate(&s.db)
            return err
        }

        s.name = copy
        s.loaded = true
        return nil
    }
