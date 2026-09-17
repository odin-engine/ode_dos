/*
    2026 (c) Oleh, https://github.com/zm69

    Names: 64-bit FNV-1a hashes of full dotted names index the entities of a Config. Archetypes,
    metas and surfaces share one index, objects have their own, and lookups walk the base chain so
    a derived Config can name what its base declared.
*/
package ode_dos

// Core
    import "core:strings"

///////////////////////////////////////////////////////////////////////////////
// Private

    // FNV-1a 64.
    @(private)
    name_hash :: proc "contextless" (name: string) -> u64 {
        h: u64 = 0xcbf29ce484222325
        for i in 0..<len(name) {
            h ~= u64(name[i])
            h *= 0x100000001b3
        }
        return h == 0 ? 1 : h
    }

    // A copy that lives as long as the Config.
    @(private)
    config__intern :: proc(self: ^Config, s: string) -> string {
        copy, err := strings.clone(s, self.persist)
        return err == nil ? copy : ""
    }

    // This Config first, then the ones it is based on.
    @(private)
    config__find_named :: proc(self: ^Config, name: string, objects: bool) -> (ix: u32, ok: bool) {
        h := name_hash(name)
        for c := self; c != nil; c = c.base {
            index := objects ? &c.object_names : &c.config_names
            if found, has := index^[h]; has do return found, true
        }
        return NO_ID, false
    }

    @(private)
    config__find_config :: proc(self: ^Config, name: string) -> (ix: u32, kind: Config_Kind, ok: bool) {
        found, has := config__find_named(self, name, false)
        if !has do return NO_ID, .None, false
        return found, config__kind_of(self, found), true
    }

    @(private)
    config__name_of :: proc(self: ^Config, ix: u32) -> string {
        e := config__entity(self, ix)
        return e == nil ? "" : e.name
    }
