/*
    2026 (c) Oleh, https://github.com/zm69

    Bake: flattens inheritance and metas into per-archetype and per-surface values, so runtime
    lookups never walk a chain.
*/
package ode_dos

// ODE
    import ecs "../../ode_ecs/src"

///////////////////////////////////////////////////////////////////////////////
// Bake

    // Recomputes every baked value; idempotent, and the hot-reload step after a re-load.
    world__bake :: proc(self: ^World) -> Error {
        when VALIDATIONS do assert(world__is_valid(self))

        for b in self.bakers do b.bake(self, b.data) or_return
        for g in self.flag_groups do flag_group__bake(self, g) or_return
        return nil
    }

///////////////////////////////////////////////////////////////////////////////
// Private

    @(private)
    Baker :: struct {
        bake: proc(w: ^World, data: rawptr) -> Error,
        data: rawptr,
        set:  config_set_id,
    }

    @(private)
    world__add_baker :: proc(self: ^World, bake: proc(w: ^World, data: rawptr) -> Error, data: rawptr, set: config_set_id) -> Error {
        _, err := append(&self.bakers, Baker{ bake = bake, data = data, set = set })
        return err
    }

    // Precedence order: a holder's metas (highest priority first), the holder itself, then the
    // same for each parent up to the root. Surfaces have no parents.
    @(private)
    Source_Iter :: struct {
        world:     ^World,
        cur:       ecs.entity_id,
        kind:      Config_Kind,
        metas:     []Attachment,
        next_meta: int,
        done:      bool,
    }

    @(private)
    source_iter :: proc(w: ^World, holder: ecs.entity_id, kind: Config_Kind) -> Source_Iter {
        return Source_Iter{ world = w, cur = holder, kind = kind, metas = world__metas_into(w, holder, w.meta_scratch) }
    }

    @(private)
    source_iter__next :: proc(it: ^Source_Iter) -> (src: ecs.entity_id, ok: bool) {
        if it.done do return {}, false

        if it.next_meta < len(it.metas) {
            it.next_meta += 1
            return ecs.entity_id(it.metas[it.next_meta - 1].meta), true
        }

        src = it.cur
        if it.kind == .Surface {
            it.done = true
            return src, true
        }

        p, err := ecs.parent_of(world__core_db(it.world), it.cur)
        if err != nil || ecs.is_not_set(p) {
            it.done = true
        } else {
            it.cur = p
            it.metas = world__metas_into(it.world, p, it.world.meta_scratch)
            it.next_meta = 0
        }
        return src, true
    }
