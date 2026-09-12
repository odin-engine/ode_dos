/*
    2026 (c) Oleh, https://github.com/zm69

    Config capacity: config space starts minimal and grows in place, to exactly what a load
    declares, or doubling when archetypes, metas, surfaces and attachments are created in code.
    Capacities never shrink, and ids never change.
*/
package ode_dos

// Base
    import rt "base:runtime"

// ODE
    import ecs "../../ode_ecs/src"
    import oc_maps "../../ode_ecs/src/ode_core/maps"

///////////////////////////////////////////////////////////////////////////////
// Capacity

    // Config entities (archetypes, metas and surfaces) and meta attachments the World holds now.
    world__config_capacity :: proc(self: ^World) -> (archetypes: int, attachments: int) {
        return self.config_cap, self.attachments_cap
    }

///////////////////////////////////////////////////////////////////////////////
// Private

    @(private)
    MIN_CODE_GROWTH :: 16

    // Grows only what is short.
    @(private)
    world__grow_config :: proc(self: ^World, entities: int, attachments: int) -> Error {
        if entities > self.config_cap {
            n := entities
            ecs_err(ecs.overbase_grow(&self.config_overbase, u32(n))) or_return

            for b in self.bakers do b.grow(b.data, n) or_return
            for g in self.flag_groups {
                ecs_err(ecs.grow(&g.authored, n)) or_return
                ecs_err(ecs.grow(&g.baked, n)) or_return
            }
            ecs_err(ecs.grow(&self.relations, n)) or_return
            ecs_err(ecs.grow(&self.attachments, n, self.attachments_cap)) or_return

            grow_array(&self.config_eid, n, self.allocator) or_return
            grow_array(&self.config_kind, n, self.allocator) or_return
            grow_array(&self.config_set_of, n, self.allocator) or_return
            grow_array(&self.config_hash, n, self.allocator) or_return
            grow_array(&self.meta_priority, n, self.allocator) or_return
            world__rebuild_config_names(self, n) or_return

            self.config_cap = n
        }

        if attachments > self.attachments_cap {
            ecs_err(ecs.grow(&self.attachments, self.config_cap, attachments)) or_return
            grow_array(&self.meta_scratch, attachments, self.allocator) or_return
            self.attachments_cap = attachments
        }

        return nil
    }

    @(private)
    world__rebuild_config_names :: proc(self: ^World, n: int) -> Error {
        names: oc_maps.Rh_Map64
        oc_maps.rh_map64__init(&names, oc_maps.rh_map64__capacity_for(n), self.allocator) or_return

        for kind, ix in self.config_kind {
            if kind != .None do oc_maps.rh_map64__add(&names, self.config_hash[ix], u32(ix)) or_return
        }

        _ = oc_maps.rh_map64__terminate(&self.config_names, self.allocator)
        self.config_names = names
        return nil
    }

    // A longer copy of s^; the new tail is zero.
    @(private)
    grow_array :: proc(s: ^[]$E, n: int, allocator: rt.Allocator) -> rt.Allocator_Error {
        if n <= len(s^) do return nil

        grown := make([]E, n, allocator) or_return
        copy(grown, s^)
        delete(s^, allocator)
        s^ = grown
        return nil
    }
