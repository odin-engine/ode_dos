/*
    2026 (c) Oleh, https://github.com/zm69

    Archetypes, metas, surfaces and the designed objects made from them. Archetypes form one
    inheritance forest across a Config chain; metas attach to archetypes and surfaces with a
    priority.
*/
package ode_dos

///////////////////////////////////////////////////////////////////////////////
// Creation

    // A parent must be in this Config or in one it is based on.
    config__archetype :: proc(self: ^Config, name: string, parent := "") -> (id: archetype_id, err: Error) {
        when VALIDATIONS do assert(config__is_valid(self))

        parent_ix := u32(NO_ID)
        if parent != "" {
            p, kind, found := config__find_config(self, parent)
            if !found do return archetype_id(NO_ID), DOS_Error.Name_Not_Found
            if kind != .Archetype do return archetype_id(NO_ID), DOS_Error.Wrong_Kind
            parent_ix = p
        }

        ix := config__create(self, name, .Archetype) or_return
        self.root.entities[ix].parent = parent_ix
        return archetype_id(ix), nil
    }

    config__meta :: proc(self: ^Config, name: string) -> (id: meta_id, err: Error) {
        when VALIDATIONS do assert(config__is_valid(self))
        ix := config__create(self, name, .Meta) or_return
        return meta_id(ix), nil
    }

    config__surface :: proc(self: ^Config, name: string) -> (id: surface_id, err: Error) {
        when VALIDATIONS do assert(config__is_valid(self))
        ix := config__create(self, name, .Surface) or_return
        return surface_id(ix), nil
    }

    // A designed object of an archetype; an empty name leaves it unnamed.
    config__object :: proc(self: ^Config, archetype: archetype_id, name := "") -> (obj: object_id, err: Error) {
        when VALIDATIONS do assert(config__is_valid(self))

        if !config__is(self, u32(archetype), .Archetype) do return object_id(NO_ID), DOS_Error.Wrong_Kind

        ix: u32
        if name == "" {
            ix = config__new_entity(self, .Object, "") or_return
        } else {
            ix = config__create(self, name, .Object) or_return
        }
        self.root.entities[ix].archetype = u32(archetype)
        return object_id(ix), nil
    }

///////////////////////////////////////////////////////////////////////////////
// Lookup

    config__find_archetype :: proc(self: ^Config, name: string) -> (archetype_id, bool) {
        ix, kind, ok := config__find_config(self, name)
        if !ok || kind != .Archetype do return archetype_id(NO_ID), false
        return archetype_id(ix), true
    }

    config__find_meta :: proc(self: ^Config, name: string) -> (meta_id, bool) {
        ix, kind, ok := config__find_config(self, name)
        if !ok || kind != .Meta do return meta_id(NO_ID), false
        return meta_id(ix), true
    }

    config__find_surface :: proc(self: ^Config, name: string) -> (surface_id, bool) {
        ix, kind, ok := config__find_config(self, name)
        if !ok || kind != .Surface do return surface_id(NO_ID), false
        return surface_id(ix), true
    }

    config__find_object :: proc(self: ^Config, name: string) -> (object_id, bool) {
        ix, ok := config__find_named(self, name, true)
        if !ok do return object_id(NO_ID), false
        return object_id(ix), true
    }

    config__archetype_name :: proc(self: ^Config, id: archetype_id) -> string { return config__name_of(self, u32(id)) }
    config__meta_name      :: proc(self: ^Config, id: meta_id) -> string      { return config__name_of(self, u32(id)) }
    config__surface_name   :: proc(self: ^Config, id: surface_id) -> string   { return config__name_of(self, u32(id)) }
    config__object_name    :: proc(self: ^Config, id: object_id) -> string    { return config__name_of(self, u32(id)) }

    config__archetype_of :: proc(self: ^Config, obj: object_id) -> archetype_id {
        e := config__entity(self, u32(obj))
        return e == nil ? archetype_id(NO_ID) : archetype_id(e.archetype)
    }

    config__set_object_name :: proc(self: ^Config, obj: object_id, name: string) -> Error {
        if name == "" do return DOS_Error.Invalid_Name

        e := config__entity(self, u32(obj))
        if e == nil || e.kind != .Object do return DOS_Error.Wrong_Kind
        if _, exists := config__find_named(self, name, true); exists do return DOS_Error.Name_Already_Exists

        owner := e.config
        if e.name_hash != 0 do delete_key(&owner.object_names, e.name_hash)

        e.name = config__intern(owner, name)
        e.name_hash = name_hash(name)
        owner.object_names[e.name_hash] = u32(obj)
        return nil
    }

///////////////////////////////////////////////////////////////////////////////
// Inheritance

    config__parent_of :: proc(self: ^Config, id: archetype_id) -> (archetype_id, bool) {
        e := config__entity(self, u32(id))
        if e == nil || e.parent == NO_ID do return archetype_id(NO_ID), false
        return archetype_id(e.parent), true
    }

    // Ancestors nearest first, without id itself.
    config__chain_of :: proc(self: ^Config, id: archetype_id, allocator := context.temp_allocator) -> []archetype_id {
        res := make([dynamic]archetype_id, 0, 8, allocator)
        ix := u32(id)
        for {
            e := config__entity(self, ix)
            if e == nil || e.parent == NO_ID do break
            append(&res, archetype_id(e.parent))
            ix = e.parent
        }
        return res[:]
    }

    // True for id itself and for any archetype up its chain.
    config__is_kind_of :: proc(self: ^Config, id: archetype_id, kind: archetype_id) -> bool {
        ix := u32(id)
        for {
            if ix == u32(kind) do return true
            e := config__entity(self, ix)
            if e == nil || e.parent == NO_ID do return false
            ix = e.parent
        }
    }

///////////////////////////////////////////////////////////////////////////////
// Metas

    config__attach_to_archetype :: proc(self: ^Config, holder: archetype_id, meta: meta_id, priority := 0) -> Error {
        return config__attach(self, u32(holder), .Archetype, meta, i32(priority))
    }

    config__attach_to_surface :: proc(self: ^Config, holder: surface_id, meta: meta_id, priority := 0) -> Error {
        return config__attach(self, u32(holder), .Surface, meta, i32(priority))
    }

    config__detach_from_archetype :: proc(self: ^Config, holder: archetype_id, meta: meta_id) -> Error {
        return config__detach(self, u32(holder), meta)
    }

    config__detach_from_surface :: proc(self: ^Config, holder: surface_id, meta: meta_id) -> Error {
        return config__detach(self, u32(holder), meta)
    }

    // Highest priority first, ties by name.
    config__metas_of_archetype :: proc(self: ^Config, holder: archetype_id) -> []Attachment {
        return config__metas(self, u32(holder))
    }

    config__metas_of_surface :: proc(self: ^Config, holder: surface_id) -> []Attachment {
        return config__metas(self, u32(holder))
    }

///////////////////////////////////////////////////////////////////////////////
// Queries

    // Every object this Config declares.
    config__objects :: proc(self: ^Config, allocator := context.temp_allocator) -> []object_id {
        res := make([dynamic]object_id, 0, 64, allocator)
        for ix in self.mine {
            if config__kind_of(self, ix) == .Object do append(&res, object_id(ix))
        }
        return res[:]
    }

    // Objects of this archetype or anything derived from it.
    config__objects_of :: proc(self: ^Config, archetype: archetype_id, allocator := context.temp_allocator) -> []object_id {
        res := make([dynamic]object_id, 0, 64, allocator)
        for ix in self.mine {
            if config__kind_of(self, ix) != .Object do continue
            if config__is_kind_of(self, config__archetype_of(self, object_id(ix)), archetype) do append(&res, object_id(ix))
        }
        return res[:]
    }

    // What the last load touched; valid until the next one.
    config__changed_objects :: proc(self: ^Config, allocator := context.temp_allocator) -> []object_id {
        res := make([dynamic]object_id, 0, 32, allocator)
        for ix in self.changed {
            if config__kind_of(self, ix) == .Object do append(&res, object_id(ix))
        }
        return res[:]
    }

    config__changed_archetypes :: proc(self: ^Config, allocator := context.temp_allocator) -> []archetype_id {
        res := make([dynamic]archetype_id, 0, 32, allocator)
        for ix in self.changed {
            if config__kind_of(self, ix) == .Archetype do append(&res, archetype_id(ix))
        }
        return res[:]
    }

///////////////////////////////////////////////////////////////////////////////
// Private

    @(private)
    config__create :: proc(self: ^Config, name: string, kind: Config_Kind) -> (ix: u32, err: Error) {
        if name == "" do return NO_ID, DOS_Error.Invalid_Name
        if _, exists := config__find_named(self, name, kind == .Object); exists do return NO_ID, DOS_Error.Name_Already_Exists
        return config__new_entity(self, kind, name)
    }

    @(private)
    config__attach :: proc(self: ^Config, holder: u32, kind: Config_Kind, meta: meta_id, priority: i32) -> Error {
        if !config__is(self, holder, kind) || !config__is(self, u32(meta), .Meta) do return DOS_Error.Wrong_Kind

        e := config__entity(self, holder)
        for &a in e.metas {
            if a.meta == meta {
                a.priority = priority
                return nil
            }
        }
        _, err := append(&e.metas, Attachment{ meta = meta, priority = priority })
        return err
    }

    @(private)
    config__detach :: proc(self: ^Config, holder: u32, meta: meta_id) -> Error {
        e := config__entity(self, holder)
        if e == nil do return DOS_Error.Wrong_Kind

        for a, i in e.metas {
            if a.meta == meta {
                ordered_remove(&e.metas, i)
                return nil
            }
        }
        return DOS_Error.Name_Not_Found
    }

    // Sorted highest priority first, ties by name; the slice belongs to the entity.
    @(private)
    config__metas :: proc(self: ^Config, holder: u32) -> []Attachment {
        e := config__entity(self, holder)
        if e == nil do return nil

        for i in 1..<len(e.metas) {
            for j := i; j > 0 && config__attachment_less(self, e.metas[j], e.metas[j - 1]); j -= 1 {
                e.metas[j], e.metas[j - 1] = e.metas[j - 1], e.metas[j]
            }
        }
        return e.metas[:]
    }

    @(private)
    config__attachment_less :: proc(self: ^Config, a, b: Attachment) -> bool {
        if a.priority != b.priority do return a.priority > b.priority
        return config__name_of(self, u32(a.meta)) < config__name_of(self, u32(b.meta))
    }
