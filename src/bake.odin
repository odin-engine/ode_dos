/*
    2026 (c) Oleh, https://github.com/zm69

    Bake: flattens inheritance and metas into one value per name per archetype and surface, so
    reading never walks a chain. Objects are not baked: what they author wins, and everything else
    comes from their archetype.
*/
package ode_dos

///////////////////////////////////////////////////////////////////////////////
// Bake

    // Recomputes every baked value in the whole Config chain; idempotent, and the step after a load.
    config__bake :: proc(self: ^Config) -> Error {
        when VALIDATIONS do assert(config__is_valid(self))

        root := self.root
        for ix in 0..<len(root.entities) {
            e := &root.entities[ix]
            if e.kind != .Archetype && e.kind != .Surface do continue

            clear(&e.baked)
            config__bake_entity(self, u32(ix)) or_return
        }
        return nil
    }

///////////////////////////////////////////////////////////////////////////////
// Private

    // Precedence: a holder's metas (highest priority first), the holder itself, then the same for
    // each parent up to the root. The first source with a name wins. Surfaces have no parents.
    @(private)
    config__bake_entity :: proc(self: ^Config, ix: u32) -> Error {
        target := config__entity(self, ix)
        if target == nil do return nil

        cur := ix
        for {
            e := config__entity(self, cur)
            if e == nil do break

            for a in config__metas(self, cur) {
                config__bake_from(self, target, u32(a.meta)) or_return
            }
            config__bake_from(self, target, cur) or_return

            if e.kind == .Surface || e.parent == NO_ID do break
            cur = e.parent
        }
        return nil
    }

    @(private)
    config__bake_from :: proc(self: ^Config, target: ^Entity, source_ix: u32) -> Error {
        src := config__entity(self, source_ix)
        if src == nil do return nil

        for hash, a in src.authored {
            if _, taken := target.baked[hash]; taken {
                values__mark(self, source_ix, hash) // something more specific shadows it
                continue
            }
            target.baked[hash] = Baked{ node = a.node, from = source_ix }
        }
        return nil
    }
