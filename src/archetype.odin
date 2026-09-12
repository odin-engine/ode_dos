/*
    2026 (c) Oleh, https://github.com/zm69

    Archetypes, metas and surfaces: named config entities. Archetypes form one inheritance
    forest across all config sets (a Relations_Table on CORE); metas attach to archetypes and
    surfaces with a priority (a Pair_Table on CORE).
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

    // A parent must be in the same config set or in CORE.
    world__archetype :: proc(self: ^World, name: string, parent := "", set := CORE) -> (id: archetype_id, err: Error) {
        when VALIDATIONS do assert(world__is_valid(self))

        parent_eid: ecs.entity_id
        has_parent := parent != ""
        if has_parent {
            p, kind, found := world__find_config(self, parent)
            if !found do return {}, DOS_Error.Name_Not_Found
            if kind != .Archetype do return {}, DOS_Error.Wrong_Kind
            if !world__parent_allowed(self, p, set) do return {}, DOS_Error.Parent_Not_Allowed
            parent_eid = p
        }

        eid := world__create_config(self, name, .Archetype, set) or_return

        if has_parent {
            if perr := ecs.set_parent(world__core_db(self), eid, parent_eid); perr != nil {
                world__destroy_config(self, eid)
                return {}, ecs_err(perr)
            }
        }

        return archetype_id(eid), nil
    }

    world__meta :: proc(self: ^World, name: string, set := CORE) -> (id: meta_id, err: Error) {
        when VALIDATIONS do assert(world__is_valid(self))
        eid := world__create_config(self, name, .Meta, set) or_return
        return meta_id(eid), nil
    }

    world__surface :: proc(self: ^World, name: string, set := CORE) -> (id: surface_id, err: Error) {
        when VALIDATIONS do assert(world__is_valid(self))
        eid := world__create_config(self, name, .Surface, set) or_return
        return surface_id(eid), nil
    }

///////////////////////////////////////////////////////////////////////////////
// Lookup

    world__find_archetype :: proc(self: ^World, name: string) -> (archetype_id, bool) {
        eid, kind, ok := world__find_config(self, name)
        if !ok || kind != .Archetype do return {}, false
        return archetype_id(eid), true
    }

    world__find_meta :: proc(self: ^World, name: string) -> (meta_id, bool) {
        eid, kind, ok := world__find_config(self, name)
        if !ok || kind != .Meta do return {}, false
        return meta_id(eid), true
    }

    world__find_surface :: proc(self: ^World, name: string) -> (surface_id, bool) {
        eid, kind, ok := world__find_config(self, name)
        if !ok || kind != .Surface do return {}, false
        return surface_id(eid), true
    }

    world__archetype_name :: proc(self: ^World, id: archetype_id) -> string { return world__config_name(self, ecs.entity_id(id)) }
    world__meta_name      :: proc(self: ^World, id: meta_id) -> string      { return world__config_name(self, ecs.entity_id(id)) }
    world__surface_name   :: proc(self: ^World, id: surface_id) -> string   { return world__config_name(self, ecs.entity_id(id)) }

///////////////////////////////////////////////////////////////////////////////
// Inheritance

    world__parent_of :: proc(self: ^World, id: archetype_id) -> (archetype_id, bool) {
        p, err := ecs.parent_of(world__core_db(self), ecs.entity_id(id))
        if err != nil || ecs.is_not_set(p) do return {}, false
        return archetype_id(p), true
    }

    // Ancestors nearest first, without id itself; valid until the next chain query.
    world__chain_of :: proc(self: ^World, id: archetype_id) -> []archetype_id {
        res, err := ecs.ancestors_of(world__core_db(self), ecs.entity_id(id))
        if err != nil do return nil
        return transmute([]archetype_id)res
    }

    // True for id itself and for any archetype up its chain.
    world__is_kind_of :: proc(self: ^World, id: archetype_id, kind: archetype_id) -> bool {
        if id == kind do return true
        ok, err := ecs.is_ancestor_of(world__core_db(self), ecs.entity_id(kind), ecs.entity_id(id))
        return err == nil && ok
    }

///////////////////////////////////////////////////////////////////////////////
// Metas

    world__attach_to_archetype :: proc(self: ^World, holder: archetype_id, meta: meta_id, priority := 0) -> Error {
        return world__attach(self, ecs.entity_id(holder), .Archetype, meta, priority)
    }

    world__attach_to_surface :: proc(self: ^World, holder: surface_id, meta: meta_id, priority := 0) -> Error {
        return world__attach(self, ecs.entity_id(holder), .Surface, meta, priority)
    }

    world__detach_from_archetype :: proc(self: ^World, holder: archetype_id, meta: meta_id) -> Error {
        return ecs_err(ecs.pair_remove(&self.attachments, ecs.entity_id(holder), ecs.entity_id(meta)))
    }

    world__detach_from_surface :: proc(self: ^World, holder: surface_id, meta: meta_id) -> Error {
        return ecs_err(ecs.pair_remove(&self.attachments, ecs.entity_id(holder), ecs.entity_id(meta)))
    }

    // Highest priority first, ties by name.
    world__metas_of_archetype :: proc(self: ^World, holder: archetype_id, allocator := context.temp_allocator) -> []Attachment {
        return world__metas_alloc(self, ecs.entity_id(holder), allocator)
    }

    world__metas_of_surface :: proc(self: ^World, holder: surface_id, allocator := context.temp_allocator) -> []Attachment {
        return world__metas_alloc(self, ecs.entity_id(holder), allocator)
    }

///////////////////////////////////////////////////////////////////////////////
// Private

    @(private)
    world__core_db :: #force_inline proc(self: ^World) -> ^ecs.Database {
        return &self.sets[CORE].db
    }

    @(private)
    world__config_is :: proc(self: ^World, eid: ecs.entity_id, kind: Config_Kind) -> bool {
        if int(eid.ix) >= len(self.config_kind) do return false
        return self.config_kind[eid.ix] == kind && self.config_eid[eid.ix] == eid
    }

    @(private)
    world__parent_allowed :: proc(self: ^World, parent: ecs.entity_id, child_set: config_set_id) -> bool {
        ps := self.config_set_of[parent.ix]
        return ps == child_set || ps == CORE
    }

    @(private)
    world__create_config :: proc(self: ^World, name: string, kind: Config_Kind, set: config_set_id) -> (eid: ecs.entity_id, err: Error) {
        if name == "" do return {}, DOS_Error.Invalid_Name
        if !world__set_is_loaded(self, set) do return {}, DOS_Error.Config_Set_Not_Found
        if _, _, exists := world__find_config(self, name); exists do return {}, DOS_Error.Name_Already_Exists

        if ecs.entities_len(&self.config_overbase) >= self.config_cap {
            world__grow_config(self, max(MIN_CODE_GROWTH, 2 * self.config_cap), self.attachments_cap) or_return
        }

        e, cerr := ecs.create_entity(&self.sets[set].db)
        if cerr != nil do return {}, ecs_err(cerr)

        if rerr := world__register_config(self, e, kind, set, name); rerr != nil {
            _ = ecs.destroy_entity(&self.config_overbase, e)
            return {}, rerr
        }

        return e, nil
    }

    @(private)
    world__destroy_config :: proc(self: ^World, eid: ecs.entity_id) {
        _ = ecs.destroy_entity(&self.config_overbase, eid)
        world__unregister_config(self, eid.ix)
    }

    @(private)
    world__attach :: proc(self: ^World, holder: ecs.entity_id, kind: Config_Kind, meta: meta_id, priority: int) -> Error {
        target := ecs.entity_id(meta)
        if !world__config_is(self, holder, kind) || !world__config_is(self, target, .Meta) do return DOS_Error.Wrong_Kind

        if data, ok := ecs.pair_get_data(&self.attachments, holder, target); ok {
            data.priority = i32(priority)
            return nil
        }

        if ecs.pair_len(&self.attachments) >= self.attachments_cap {
            world__grow_config(self, self.config_cap, max(MIN_CODE_GROWTH, 2 * self.attachments_cap)) or_return
        }

        _, err := ecs.pair_add(&self.attachments, holder, target, Attachment_Data{ priority = i32(priority) })
        return ecs_err(err)
    }

    // Fills buf (sorted) and returns the used part; buf must hold count_of(holder) items.
    @(private)
    world__metas_into :: proc(self: ^World, holder: ecs.entity_id, buf: []Attachment) -> []Attachment {
        n := 0
        row, ok := ecs.pair_first_row_of(&self.attachments, holder)
        for ok && n < len(buf) {
            buf[n] = Attachment{
                meta     = meta_id(ecs.pair_row_target(&self.attachments, row)),
                priority = ecs.pair_row_data(&self.attachments, row).priority,
            }
            n += 1
            row, ok = ecs.pair_next_row_of(&self.attachments, row)
        }

        res := buf[:n]
        for i in 1..<n {
            for j := i; j > 0 && world__attachment_less(self, res[j], res[j - 1]); j -= 1 {
                res[j], res[j - 1] = res[j - 1], res[j]
            }
        }
        return res
    }

    @(private)
    world__metas_alloc :: proc(self: ^World, holder: ecs.entity_id, allocator := context.temp_allocator) -> []Attachment {
        buf := make([]Attachment, ecs.pair_count_of(&self.attachments, holder), allocator)
        return world__metas_into(self, holder, buf)
    }

    @(private)
    world__attachment_less :: proc(self: ^World, a, b: Attachment) -> bool {
        if a.priority != b.priority do return a.priority > b.priority
        if self.keep_names do return world__config_name(self, ecs.entity_id(a.meta)) < world__config_name(self, ecs.entity_id(b.meta))
        return self.config_hash[a.meta.ix] < self.config_hash[b.meta.ix]
    }
