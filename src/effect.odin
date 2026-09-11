/*
    2026 (c) Oleh, https://github.com/zm69

    Runtime effects: named changes applied to objects (KnockedOut, Burning), with Odin hooks for
    what they do. An applied effect is one bit in a runtime ecs.Flags_Table, so it is saved with
    the game and usable in views.
*/
package ode_dos

// ODE
    import ecs "../../ode_ecs/src"

///////////////////////////////////////////////////////////////////////////////
// Effect

    Effect :: struct {
        on_attach: proc(w: ^World, obj: object_id),
        on_detach: proc(w: ^World, obj: object_id),
    }

    @(private)
    EFFECTS_PER_TABLE :: 128

    @(private)
    Effect_Entry :: struct {
        hash:   u64,
        effect: Effect,
        table:  ^ecs.Flags_Table,
        bit:    int,
    }

    world__effect_register :: proc(self: ^World, name: string, effect: Effect) -> Error {
        when VALIDATIONS do assert(world__is_valid(self))

        if world__binding_exists(self, name) do return DOS_Error.Name_Already_Exists

        n := len(self.effects)
        if n % EFFECTS_PER_TABLE == 0 {
            table := new(ecs.Flags_Table, self.allocator) or_return
            ecs_err(ecs.flags_table_init(table, &self.runtime_db, self.cfg.max_objects)) or_return
            _, err := append(&self.effect_tables, table)
            if err != nil do return err
        }

        entry := Effect_Entry{
            hash   = name_hash(name),
            effect = effect,
            table  = self.effect_tables[len(self.effect_tables) - 1],
            bit    = n % EFFECTS_PER_TABLE,
        }
        _, err := append(&self.effects, entry)
        if err != nil do return err

        return world__add_binding(self, name, .Effect)
    }

    // Runs on_attach; applying an effect the object already has does nothing.
    world__apply :: proc(self: ^World, obj: object_id, name: string) -> Error {
        e := world__effect_entry(self, name)
        if e == nil do return DOS_Error.Name_Not_Found

        eid := ecs.entity_id(obj)
        if ecs.has_flag(e.table, eid, e.bit) do return nil
        ecs_err(ecs.flag(e.table, eid, e.bit)) or_return
        if e.effect.on_attach != nil do e.effect.on_attach(self, obj)
        return nil
    }

    // Runs on_detach; unapplying an effect the object does not have does nothing.
    world__unapply :: proc(self: ^World, obj: object_id, name: string) -> Error {
        e := world__effect_entry(self, name)
        if e == nil do return DOS_Error.Name_Not_Found

        eid := ecs.entity_id(obj)
        if !ecs.has_flag(e.table, eid, e.bit) do return nil
        ecs_err(ecs.unflag(e.table, eid, e.bit)) or_return
        if e.effect.on_detach != nil do e.effect.on_detach(self, obj)
        return nil
    }

    world__affected :: proc(self: ^World, obj: object_id, name: string) -> bool {
        e := world__effect_entry(self, name)
        return e != nil && ecs.has_flag(e.table, ecs.entity_id(obj), e.bit)
    }

    // A view term matching objects with the effect applied.
    world__effect_term :: proc(self: ^World, name: string) -> (term: ecs.Flags, ok: bool) {
        e := world__effect_entry(self, name)
        if e == nil do return {}, false
        return ecs.flags_term(e.table, ecs.Bits{e.bit}), true
    }

///////////////////////////////////////////////////////////////////////////////
// Private

    @(private)
    world__effect_entry :: proc(self: ^World, name: string) -> ^Effect_Entry {
        h := name_hash(name)
        for &e in self.effects {
            if e.hash == h do return &e
        }
        return nil
    }
