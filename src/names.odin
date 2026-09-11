/*
    2026 (c) Oleh, https://github.com/zm69

    Name indexes: 64-bit FNV-1a hashes of full dotted names map to entity indexes.
    Strings are kept only when the World keeps names.
*/
package ode_dos

// Core
    import "core:strings"

// ODE
    import ecs "../../ode_ecs/src"
    import oc_maps "../../ode_ecs/src/ode_core/maps"

///////////////////////////////////////////////////////////////////////////////
// Private

    // FNV-1a 64; never returns the map's empty-slot key.
    @(private)
    name_hash :: proc "contextless" (name: string) -> u64 {
        h: u64 = 0xcbf29ce484222325
        for i in 0..<len(name) {
            h ~= u64(name[i])
            h *= 0x100000001b3
        }
        if h == oc_maps.RH_MAP64_DELETED do h -= 1
        return h
    }

    @(private)
    world__keep_name :: proc(self: ^World, names: ^map[u64]string, h: u64, name: string) -> Error {
        if !self.keep_names do return nil
        if _, exists := names^[h]; exists do return nil

        copy := strings.clone(name, self.allocator) or_return
        names^[h] = copy
        return nil
    }

    @(private)
    world__drop_name :: proc(self: ^World, names: ^map[u64]string, h: u64) {
        if !self.keep_names do return
        if s, ok := names^[h]; ok {
            delete(s, self.allocator)
            delete_key(names, h)
        }
    }

    @(private)
    world__register_config :: proc(self: ^World, eid: ecs.entity_id, kind: Config_Kind, set: config_set_id, name: string) -> Error {
        h := name_hash(name)
        if oc_maps.rh_map64__get(&self.config_names, h) != oc_maps.RH_MAP64_NOT_FOUND do return DOS_Error.Name_Already_Exists

        oc_maps.rh_map64__add(&self.config_names, h, u32(eid.ix)) or_return
        self.config_eid[eid.ix]    = eid
        self.config_kind[eid.ix]   = kind
        self.config_set_of[eid.ix] = set
        self.config_hash[eid.ix]   = h

        return world__keep_name(self, &self.config_strings, h, name)
    }

    @(private)
    world__unregister_config :: proc(self: ^World, ix: int) {
        h := self.config_hash[ix]
        _ = oc_maps.rh_map64__remove(&self.config_names, h)
        world__drop_name(self, &self.config_strings, h)

        self.config_kind[ix] = .None
        self.config_hash[ix] = 0
    }

    @(private)
    world__find_config :: proc(self: ^World, name: string) -> (eid: ecs.entity_id, kind: Config_Kind, ok: bool) {
        ix := oc_maps.rh_map64__get(&self.config_names, name_hash(name))
        if ix == oc_maps.RH_MAP64_NOT_FOUND do return {}, .None, false
        return self.config_eid[ix], self.config_kind[ix], true
    }

    // "" when names are not kept.
    @(private)
    world__config_name :: proc(self: ^World, eid: ecs.entity_id) -> string {
        if !self.keep_names || int(eid.ix) >= len(self.config_kind) || self.config_kind[eid.ix] == .None do return ""
        return self.config_strings[self.config_hash[eid.ix]]
    }
