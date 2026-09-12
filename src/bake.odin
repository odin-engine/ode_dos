/*
    2026 (c) Oleh, https://github.com/zm69

    Bake: flattens inheritance and metas into per-archetype and per-surface values, so resolving
    never walks a chain. Objects are not baked: what they author wins, and everything else comes
    from their archetype's baked value.
*/
package ode_dos

// ODE
    import ecs "../../ode_ecs/src"

///////////////////////////////////////////////////////////////////////////////
// Bake

    // Recomputes every baked value in the whole Config chain; idempotent, and the step after a load.
    config__bake :: proc(self: ^Config) -> Error {
        when VALIDATIONS do assert(config__is_valid(self))

        for c in self.root.chain {
            for s in c.storages {
                if s.bake != nil do s.bake(c, s.data) or_return
            }
            for g in c.flag_groups do flag_group__bake(g) or_return
        }
        return nil
    }

///////////////////////////////////////////////////////////////////////////////
// Private

    // Everything a Config owns that grows with its Database, and bakes when it holds values.
    @(private)
    Storage :: struct {
        bake: proc(cfg: ^Config, data: rawptr) -> Error,
        grow: proc(data: rawptr, cap: int) -> Error,
        data: rawptr,
    }

    @(private)
    config__add_storage :: proc(self: ^Config, bake: proc(cfg: ^Config, data: rawptr) -> Error, grow: proc(data: rawptr, cap: int) -> Error, data: rawptr) -> Error {
        _, err := append(&self.storages, Storage{ bake = bake, grow = grow, data = data })
        return err
    }

    // Precedence order: a holder's metas (highest priority first), the holder itself, then the
    // same for each parent up to the root. Surfaces have no parents.
    @(private)
    Source_Iter :: struct {
        config:    ^Config,
        cur:       ecs.entity_id,
        kind:      Config_Kind,
        metas:     []Attachment,
        next_meta: int,
        done:      bool,
    }

    @(private)
    source_iter :: proc(cfg: ^Config, holder: ecs.entity_id, kind: Config_Kind) -> Source_Iter {
        return Source_Iter{ config = cfg, cur = holder, kind = kind, metas = config__metas_into(cfg, holder, cfg.root.meta_scratch) }
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

        p, err := ecs.parent_of(&it.config.root.db, it.cur)
        if err != nil || ecs.is_not_set(p) {
            it.done = true
        } else {
            it.cur = p
            it.metas = config__metas_into(it.config, p, it.config.root.meta_scratch)
            it.next_meta = 0
        }
        return src, true
    }
