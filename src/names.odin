/*
    2026 (c) Oleh, https://github.com/zm69

    Name indexes: 64-bit FNV-1a hashes of full dotted names map to entity indexes. Archetypes,
    metas and surfaces share one index per Config, objects have their own. Lookups walk the base
    chain, so a derived Config can name what its base declared. Strings are kept only when the
    Config keeps names.
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
    config__keep_name :: proc(self: ^Config, names: ^map[u64]string, h: u64, name: string) -> Error {
        if !self.keep_names do return nil
        if _, exists := names^[h]; exists do return nil

        copy := strings.clone(name, self.allocator) or_return
        names^[h] = copy
        return nil
    }

    @(private)
    config__drop_name :: proc(self: ^Config, names: ^map[u64]string, h: u64) {
        if !self.keep_names do return
        if s, ok := names^[h]; ok {
            delete(s, self.allocator)
            delete_key(names, h)
        }
    }

    @(private)
    config__register :: proc(self: ^Config, eid: ecs.entity_id, kind: Config_Kind, name: string) -> Error {
        h := name_hash(name)
        index := kind == .Object ? &self.object_names : &self.config_names
        strs  := kind == .Object ? &self.object_strings : &self.config_strings

        if _, _, exists := config__find_named(self, name, kind == .Object); exists do return DOS_Error.Name_Already_Exists

        oc_maps.rh_map64__add(index, h, u32(eid.ix)) or_return
        self.config_eid[eid.ix]  = eid
        self.config_kind[eid.ix] = kind
        self.config_hash[eid.ix] = h

        return config__keep_name(self, strs, h, name)
    }

    @(private)
    config__unregister :: proc(self: ^Config, ix: int) {
        h := self.config_hash[ix]
        kind := self.config_kind[ix]
        index := kind == .Object ? &self.object_names : &self.config_names
        strs  := kind == .Object ? &self.object_strings : &self.config_strings

        if h != 0 {
            _ = oc_maps.rh_map64__remove(index, h)
            config__drop_name(self, strs, h)
        }

        self.config_kind[ix] = .None
        self.config_hash[ix] = 0
    }

    // This Config first, then the ones it is based on.
    @(private)
    config__find_named :: proc(self: ^Config, name: string, objects: bool) -> (eid: ecs.entity_id, kind: Config_Kind, ok: bool) {
        h := name_hash(name)
        for c := self; c != nil; c = c.base {
            index := objects ? &c.object_names : &c.config_names
            ix := oc_maps.rh_map64__get(index, h)
            if ix != oc_maps.RH_MAP64_NOT_FOUND do return c.config_eid[ix], c.config_kind[ix], true
        }
        return {}, .None, false
    }

    @(private)
    config__find_config :: proc(self: ^Config, name: string) -> (ecs.entity_id, Config_Kind, bool) {
        return config__find_named(self, name, false)
    }

    // "" when names are not kept or nothing owns eid.
    @(private)
    config__name_of :: proc(self: ^Config, eid: ecs.entity_id) -> string {
        c := config__owner(self, eid)
        if c == nil || !c.keep_names do return ""

        h := c.config_hash[eid.ix]
        if c.config_kind[eid.ix] == .Object do return c.object_strings[h]
        return c.config_strings[h]
    }

    // Rebuilds a name index at a new capacity, keeping every live name.
    @(private)
    config__rebuild_names :: proc(self: ^Config, n: int) -> Error {
        cfg_names, obj_names: oc_maps.Rh_Map64
        oc_maps.rh_map64__init(&cfg_names, oc_maps.rh_map64__capacity_for(n), self.allocator) or_return
        oc_maps.rh_map64__init(&obj_names, oc_maps.rh_map64__capacity_for(n), self.allocator) or_return

        for kind, ix in self.config_kind {
            if kind == .None do continue
            index := kind == .Object ? &obj_names : &cfg_names
            oc_maps.rh_map64__add(index, self.config_hash[ix], u32(ix)) or_return
        }

        _ = oc_maps.rh_map64__terminate(&self.config_names, self.allocator)
        _ = oc_maps.rh_map64__terminate(&self.object_names, self.allocator)
        self.config_names = cfg_names
        self.object_names = obj_names
        return nil
    }
