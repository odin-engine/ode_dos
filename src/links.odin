/*
    2026 (c) Oleh, https://github.com/zm69

    Links: typed relations a designer wires between objects - (from, flavor, to, data). They are
    metadata: a game reads them when it builds its world and turns them into whatever it needs,
    which need not be links at all.
*/
package ode_dos

///////////////////////////////////////////////////////////////////////////////
// Link

    Link :: struct {
        flavor: string,
        from:   object_id,
        to:     object_id,
        data:   ^Load_Node, // the link node's own values; read it with read_node
    }

    // Links out of an object, in the order they were authored.
    links__of :: proc(cfg: ^Config, obj: object_id, allocator := context.temp_allocator) -> []Link {
        return links__collect(cfg, u32(obj), outgoing = true, allocator = allocator)
    }

    // Links into an object.
    links__to :: proc(cfg: ^Config, obj: object_id, allocator := context.temp_allocator) -> []Link {
        return links__collect(cfg, u32(obj), outgoing = false, allocator = allocator)
    }

    // The link of this flavor between two objects, if a designer wired one.
    links__data :: proc(cfg: ^Config, from: object_id, to: object_id, flavor: string) -> (^Load_Node, bool) {
        e := config__entity(cfg, u32(from))
        if e == nil do return nil, false

        h := name_hash(flavor)
        for i in e.out_links {
            l := &cfg.root.links[i]
            if l.to == u32(to) && l.flavor_hash == h {
                l.read = true
                return l.data, true
            }
        }
        return nil, false
    }

///////////////////////////////////////////////////////////////////////////////
// Private

    @(private)
    links__collect :: proc(cfg: ^Config, ix: u32, outgoing: bool, allocator := context.temp_allocator) -> []Link {
        res := make([dynamic]Link, 0, 8, allocator)

        e := config__entity(cfg, ix)
        if e == nil do return res[:]

        list := outgoing ? e.out_links : e.in_links
        for i in list {
            l := &cfg.root.links[i]
            l.read = true
            append(&res, Link{ flavor = l.flavor, from = object_id(l.from), to = object_id(l.to), data = l.data })
        }
        return res[:]
    }

///////////////////////////////////////////////////////////////////////////////
// Writing

    @(private)
    config__add_link :: proc(self: ^Config, flavor: string, from: u32, to: u32, data: ^Load_Node) -> Error {
        root := self.root
        i := len(root.links)

        append(&root.links, Link_Record{
            flavor      = config__intern(self, flavor),
            flavor_hash = name_hash(flavor),
            from        = from,
            to          = to,
            data        = data,
        }) or_return
        append(&self.mine_links, i) or_return

        if e := config__entity(self, from); e != nil do append(&e.out_links, i) or_return
        if e := config__entity(self, to); e != nil do append(&e.in_links, i) or_return
        return nil
    }

    // A reload replaces every link this Config authored.
    @(private)
    config__clear_links :: proc(self: ^Config) {
        root := self.root
        for i in self.mine_links {
            l := &root.links[i]

            if e := config__entity(self, l.from); e != nil {
                for v, k in e.out_links {
                    if v == i {
                        ordered_remove(&e.out_links, k)
                        break
                    }
                }
            }
            if e := config__entity(self, l.to); e != nil {
                for v, k in e.in_links {
                    if v == i {
                        ordered_remove(&e.in_links, k)
                        break
                    }
                }
            }
            l^ = {}
        }
        clear(&self.mine_links)
    }
