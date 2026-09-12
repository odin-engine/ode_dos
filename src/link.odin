/*
    2026 (c) Oleh, https://github.com/zm69

    Links: typed (source, flavor, destination, data) relations between designed objects. Each
    flavor is one ecs.Pair_Table(T) in the Config's Database. They are metadata: a game reads them
    at load time and builds whatever it needs, which need not be links at all.
*/
package ode_dos

// ODE
    import ecs "../../ode_ecs/src"

///////////////////////////////////////////////////////////////////////////////
// Link

    Link :: struct($T: typeid) {
        config: ^Config,
        table:  ecs.Pair_Table(T),
    }

    Link_Row :: ecs.pair_row_id

    Link_Iterator :: struct($T: typeid) {
        link:     ^Link(T),
        row:      Link_Row,
        ok:       bool,
        incoming: bool,
    }

    // cap (links of this flavor) defaults to DEFAULT_MAX_LINKS.
    link__init :: proc(cfg: ^Config, self: ^Link($T), name: string, cap := 0, decode: Decode_Proc = nil) -> Error {
        when VALIDATIONS do assert(config__is_valid(cfg) && self != nil)

        if config__binding_exists(cfg, name) do return DOS_Error.Name_Already_Exists

        pairs := cap > 0 ? cap : DEFAULT_MAX_LINKS
        ecs_err(ecs.pair_init(&self.table, &cfg.db, holders_cap = min(cfg.config_cap, pairs), pairs_cap = pairs)) or_return
        self.config = cfg

        grow :: proc(data: rawptr, cap: int) -> Error {
            self := cast(^Link(T))data
            return ecs_err(ecs.grow(&self.table, min(cap, self.table.pairs_cap), self.table.pairs_cap))
        }
        config__add_storage(cfg, nil, grow, self) or_return

        apply :: proc(data: rawptr, op: Binding_Op, a: ecs.entity_id, b: ecs.entity_id, value: rawptr) -> Error {
            if op != .Link do return nil
            return link__link(cast(^Link(T))data, object_id(a), object_id(b), (cast(^T)value)^)
        }
        read :: proc(data: rawptr, holder: ecs.entity_id, index: int) -> (value: rawptr, other: ecs.entity_id, source: Value_Source, ok: bool) {
            it := link__outgoing(cast(^Link(T))data, object_id(holder))
            i := 0
            for target, d in link__next(&it) {
                if i == index do return d, ecs.entity_id(target), {}, true
                i += 1
            }
            return nil, {}, {}, false
        }
        return config__add_binding(cfg, name, .Link, type_info_of(T), self, 0, apply, decode, read)
    }

    // Updates the data when the link already exists.
    link__link :: proc(self: ^Link($T), from: object_id, to: object_id, data: T) -> Error {
        f, t := ecs.entity_id(from), ecs.entity_id(to)
        if d, ok := ecs.pair_get_data(&self.table, f, t); ok {
            d^ = data
            return nil
        }
        _, err := ecs.pair_add(&self.table, f, t, data)
        return ecs_err(err)
    }

    link__unlink :: proc(self: ^Link($T), from: object_id, to: object_id) -> Error {
        return ecs_err(ecs.pair_remove(&self.table, ecs.entity_id(from), ecs.entity_id(to)))
    }

    link__linked :: proc(self: ^Link($T), from: object_id, to: object_id) -> bool {
        return ecs.pair_has_pair(&self.table, ecs.entity_id(from), ecs.entity_id(to))
    }

    link__link_data :: proc(self: ^Link($T), from: object_id, to: object_id) -> (^T, bool) {
        return ecs.pair_get_data(&self.table, ecs.entity_id(from), ecs.entity_id(to))
    }

    // The most recently added target.
    link__first_target :: proc(self: ^Link($T), from: object_id) -> (object_id, ^T, bool) {
        row, ok := ecs.pair_first_row_of(&self.table, ecs.entity_id(from))
        if !ok do return {}, nil, false
        return object_id(ecs.pair_row_target(&self.table, row)), ecs.pair_row_data(&self.table, row), true
    }

    link__count_out :: proc(self: ^Link($T), from: object_id) -> int {
        return ecs.pair_count_of(&self.table, ecs.entity_id(from))
    }

    link__count_in :: proc(self: ^Link($T), to: object_id) -> int {
        return ecs.pair_count_to(&self.table, ecs.entity_id(to))
    }

    link__table :: proc(self: ^Link($T)) -> ^ecs.Pair_Table(T) {
        return &self.table
    }

///////////////////////////////////////////////////////////////////////////////
// Iteration

    link__outgoing :: proc(self: ^Link($T), from: object_id) -> Link_Iterator(T) {
        row, ok := ecs.pair_first_row_of(&self.table, ecs.entity_id(from))
        return Link_Iterator(T){ link = self, row = row, ok = ok }
    }

    link__incoming :: proc(self: ^Link($T), to: object_id) -> Link_Iterator(T) {
        row, ok := ecs.pair_first_row_to(&self.table, ecs.entity_id(to))
        return Link_Iterator(T){ link = self, row = row, ok = ok, incoming = true }
    }

    // The other end and the data.
    link__next :: proc(it: ^Link_Iterator($T)) -> (other: object_id, data: ^T, ok: bool) {
        if !it.ok do return {}, nil, false

        row := it.row
        if it.incoming {
            other = object_id(ecs.pair_row_holder(&it.link.table, row))
            it.row, it.ok = ecs.pair_next_row_to(&it.link.table, row)
        } else {
            other = object_id(ecs.pair_row_target(&it.link.table, row))
            it.row, it.ok = ecs.pair_next_row_of(&it.link.table, row)
        }
        return other, ecs.pair_row_data(&it.link.table, row), true
    }
