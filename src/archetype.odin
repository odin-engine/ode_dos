/*
    2026 (c) Oleh, https://github.com/zm69

    Archetypes, metas and surfaces: named config entities. Archetypes form one inheritance forest
    across a Config chain (a Relations_Table on the root); metas attach to archetypes and surfaces
    with a priority (a Pair_Table on the root).
*/
package ode_dos

// ODE
    import ecs "../../ode_ecs/src"

///////////////////////////////////////////////////////////////////////////////
// Attachment

    // A meta attached to an archetype or surface.
    Attachment :: struct {
        meta:     meta_id,
        priority: i32,
    }

    @(private)
    Attachment_Data :: struct {
        priority: i32,
    }

///////////////////////////////////////////////////////////////////////////////
// Creation

    // A parent must be in this Config or in one it is based on.
    config__archetype :: proc(self: ^Config, name: string, parent := "") -> (id: archetype_id, err: Error) {
        when VALIDATIONS do assert(config__is_valid(self))

        parent_eid: ecs.entity_id
        has_parent := parent != ""
        if has_parent {
            p, kind, found := config__find_config(self, parent)
            if !found do return {}, DOS_Error.Name_Not_Found
            if kind != .Archetype do return {}, DOS_Error.Wrong_Kind
            parent_eid = p
        }

        eid := config__create(self, name, .Archetype) or_return

        if has_parent {
            if perr := ecs.set_parent(&self.root.db, eid, parent_eid); perr != nil {
                config__destroy(self, eid)
                return {}, ecs_err(perr)
            }
        }

        return archetype_id(eid), nil
    }

    config__meta :: proc(self: ^Config, name: string) -> (id: meta_id, err: Error) {
        when VALIDATIONS do assert(config__is_valid(self))
        eid := config__create(self, name, .Meta) or_return
        return meta_id(eid), nil
    }

    config__surface :: proc(self: ^Config, name: string) -> (id: surface_id, err: Error) {
        when VALIDATIONS do assert(config__is_valid(self))
        eid := config__create(self, name, .Surface) or_return
        return surface_id(eid), nil
    }

///////////////////////////////////////////////////////////////////////////////
// Lookup

    config__find_archetype :: proc(self: ^Config, name: string) -> (archetype_id, bool) {
        eid, kind, ok := config__find_config(self, name)
        if !ok || kind != .Archetype do return {}, false
        return archetype_id(eid), true
    }

    config__find_meta :: proc(self: ^Config, name: string) -> (meta_id, bool) {
        eid, kind, ok := config__find_config(self, name)
        if !ok || kind != .Meta do return {}, false
        return meta_id(eid), true
    }

    config__find_surface :: proc(self: ^Config, name: string) -> (surface_id, bool) {
        eid, kind, ok := config__find_config(self, name)
        if !ok || kind != .Surface do return {}, false
        return surface_id(eid), true
    }

    config__archetype_name :: proc(self: ^Config, id: archetype_id) -> string { return config__name_of(self, ecs.entity_id(id)) }
    config__meta_name      :: proc(self: ^Config, id: meta_id) -> string      { return config__name_of(self, ecs.entity_id(id)) }
    config__surface_name   :: proc(self: ^Config, id: surface_id) -> string   { return config__name_of(self, ecs.entity_id(id)) }

///////////////////////////////////////////////////////////////////////////////
// Inheritance

    config__parent_of :: proc(self: ^Config, id: archetype_id) -> (archetype_id, bool) {
        p, err := ecs.parent_of(&self.root.db, ecs.entity_id(id))
        if err != nil || ecs.is_not_set(p) do return {}, false
        return archetype_id(p), true
    }

    // Ancestors nearest first, without id itself; valid until the next chain query.
    config__chain_of :: proc(self: ^Config, id: archetype_id) -> []archetype_id {
        res, err := ecs.ancestors_of(&self.root.db, ecs.entity_id(id))
        if err != nil do return nil
        return transmute([]archetype_id)res
    }

    // True for id itself and for any archetype up its chain.
    config__is_kind_of :: proc(self: ^Config, id: archetype_id, kind: archetype_id) -> bool {
        if id == kind do return true
        ok, err := ecs.is_ancestor_of(&self.root.db, ecs.entity_id(kind), ecs.entity_id(id))
        return err == nil && ok
    }

///////////////////////////////////////////////////////////////////////////////
// Metas

    config__attach_to_archetype :: proc(self: ^Config, holder: archetype_id, meta: meta_id, priority := 0) -> Error {
        return config__attach(self, ecs.entity_id(holder), .Archetype, meta, priority)
    }

    config__attach_to_surface :: proc(self: ^Config, holder: surface_id, meta: meta_id, priority := 0) -> Error {
        return config__attach(self, ecs.entity_id(holder), .Surface, meta, priority)
    }

    config__detach_from_archetype :: proc(self: ^Config, holder: archetype_id, meta: meta_id) -> Error {
        return ecs_err(ecs.pair_remove(&self.root.attachments, ecs.entity_id(holder), ecs.entity_id(meta)))
    }

    config__detach_from_surface :: proc(self: ^Config, holder: surface_id, meta: meta_id) -> Error {
        return ecs_err(ecs.pair_remove(&self.root.attachments, ecs.entity_id(holder), ecs.entity_id(meta)))
    }

    // Highest priority first, ties by name.
    config__metas_of_archetype :: proc(self: ^Config, holder: archetype_id, allocator := context.temp_allocator) -> []Attachment {
        return config__metas_alloc(self, ecs.entity_id(holder), allocator)
    }

    config__metas_of_surface :: proc(self: ^Config, holder: surface_id, allocator := context.temp_allocator) -> []Attachment {
        return config__metas_alloc(self, ecs.entity_id(holder), allocator)
    }

///////////////////////////////////////////////////////////////////////////////
// Private

    @(private)
    config__create :: proc(self: ^Config, name: string, kind: Config_Kind) -> (eid: ecs.entity_id, err: Error) {
        if name == "" do return {}, DOS_Error.Invalid_Name
        if _, _, exists := config__find_named(self, name, kind == .Object); exists do return {}, DOS_Error.Name_Already_Exists

        e := config__create_unnamed(self, kind) or_return

        if rerr := config__register(self, e, kind, name); rerr != nil {
            config__destroy(self, e)
            return {}, rerr
        }

        return e, nil
    }

    // Objects may go without a name; archetypes, metas and surfaces are always named.
    @(private)
    config__create_unnamed :: proc(self: ^Config, kind: Config_Kind) -> (eid: ecs.entity_id, err: Error) {
        if ecs.entities_len(&self.root.overbase) >= self.config_cap {
            config__grow(self, max(MIN_CODE_GROWTH, 2 * self.config_cap), self.root.attachments_cap) or_return
        }

        e, cerr := ecs.create_entity(&self.db)
        if cerr != nil do return {}, ecs_err(cerr)

        self.config_eid[e.ix]  = e
        self.config_kind[e.ix] = kind
        self.config_hash[e.ix] = 0
        return e, nil
    }

    @(private)
    config__destroy :: proc(self: ^Config, eid: ecs.entity_id) {
        _ = ecs.destroy_entity(&self.root.overbase, eid)
        config__unregister(self, int(eid.ix))
    }

    @(private)
    config__attach :: proc(self: ^Config, holder: ecs.entity_id, kind: Config_Kind, meta: meta_id, priority: int) -> Error {
        target := ecs.entity_id(meta)
        if !config__config_is(self, holder, kind) || !config__config_is(self, target, .Meta) do return DOS_Error.Wrong_Kind

        root := self.root
        if data, ok := ecs.pair_get_data(&root.attachments, holder, target); ok {
            data.priority = i32(priority)
            return nil
        }

        if ecs.pair_len(&root.attachments) >= root.attachments_cap {
            config__grow(self, self.config_cap, max(MIN_CODE_GROWTH, 2 * root.attachments_cap)) or_return
        }

        _, err := ecs.pair_add(&root.attachments, holder, target, Attachment_Data{ priority = i32(priority) })
        return ecs_err(err)
    }

    // Fills buf (sorted) and returns the used part; buf must hold count_of(holder) items.
    @(private)
    config__metas_into :: proc(self: ^Config, holder: ecs.entity_id, buf: []Attachment) -> []Attachment {
        root := self.root
        n := 0
        row, ok := ecs.pair_first_row_of(&root.attachments, holder)
        for ok && n < len(buf) {
            buf[n] = Attachment{
                meta     = meta_id(ecs.pair_row_target(&root.attachments, row)),
                priority = ecs.pair_row_data(&root.attachments, row).priority,
            }
            n += 1
            row, ok = ecs.pair_next_row_of(&root.attachments, row)
        }

        res := buf[:n]
        for i in 1..<n {
            for j := i; j > 0 && config__attachment_less(self, res[j], res[j - 1]); j -= 1 {
                res[j], res[j - 1] = res[j - 1], res[j]
            }
        }
        return res
    }

    @(private)
    config__metas_alloc :: proc(self: ^Config, holder: ecs.entity_id, allocator := context.temp_allocator) -> []Attachment {
        buf := make([]Attachment, ecs.pair_count_of(&self.root.attachments, holder), allocator)
        return config__metas_into(self, holder, buf)
    }

    @(private)
    config__attachment_less :: proc(self: ^Config, a, b: Attachment) -> bool {
        if a.priority != b.priority do return a.priority > b.priority
        if self.keep_names do return config__name_of(self, ecs.entity_id(a.meta)) < config__name_of(self, ecs.entity_id(b.meta))
        return ecs.entity_id(a.meta).ix < ecs.entity_id(b.meta).ix
    }
