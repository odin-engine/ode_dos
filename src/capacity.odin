/*
    2026 (c) Oleh, https://github.com/zm69

    Config capacity: a Config starts minimal and grows in place, to exactly what a load declares,
    or doubling when entities are created in code. Capacities never shrink, and ids never change.
    A whole Config chain shares one id space, so it grows together.
*/
package ode_dos

// Base
    import rt "base:runtime"

// ODE
    import ecs "../../ode_ecs/src"

///////////////////////////////////////////////////////////////////////////////
// Capacity

    // Config entities (archetypes, metas, surfaces and objects) and meta attachments held now.
    config__capacity :: proc(self: ^Config) -> (entities: int, attachments: int) {
        return self.config_cap, self.root.attachments_cap
    }

///////////////////////////////////////////////////////////////////////////////
// Private

    @(private)
    MIN_CODE_GROWTH :: 16

    // Grows only what is short, across the whole chain.
    @(private)
    config__grow :: proc(self: ^Config, entities: int, attachments: int) -> Error {
        root := self.root

        if entities > root.config_cap {
            n := entities
            ecs_err(ecs.overbase_grow(&root.overbase, u32(n))) or_return

            for c in root.chain {
                for s in c.storages do s.grow(s.data, n) or_return
                for g in c.flag_groups {
                    ecs_err(ecs.grow(&g.authored, n)) or_return
                    ecs_err(ecs.grow(&g.baked, n)) or_return
                }

                grow_array(&c.config_eid, n, c.allocator) or_return
                grow_array(&c.config_kind, n, c.allocator) or_return
                grow_array(&c.config_hash, n, c.allocator) or_return
                grow_array(&c.meta_priority, n, c.allocator) or_return
                config__rebuild_names(c, n) or_return

                c.config_cap = n
            }

            ecs_err(ecs.grow(&root.relations, n)) or_return
            ecs_err(ecs.grow(&root.attachments, n, root.attachments_cap)) or_return
            ecs_err(ecs.grow(&root.archetype_table, n)) or_return
        }

        if attachments > root.attachments_cap {
            ecs_err(ecs.grow(&root.attachments, root.config_cap, attachments)) or_return
            grow_array(&root.meta_scratch, attachments, root.allocator) or_return
            root.attachments_cap = attachments
        }

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
