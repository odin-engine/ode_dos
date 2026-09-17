/*
    2026 (c) Oleh, https://github.com/zm69

    ODE_DOS - a Dark Object System: prototype inheritance, mixins, links and KDL authoring. A
    Config loads what designers author and bakes inheritance over it; the game reads those values
    by name and builds its own runtime out of them. Nothing here is declared in code.

    This file is the public API surface: short aliases and proc groups over the typename__action
    procedures defined in the other files.
*/
package ode_dos

// Base
    import rt "base:runtime"

///////////////////////////////////////////////////////////////////////////////
// Defines

    VALIDATIONS :: #config(DOS_VALIDATIONS, true)

    NO_ID :: max(u32)

///////////////////////////////////////////////////////////////////////////////
// Ids

    // Indexes into the Config chain's entity array; stable across reloads, cheap to keep in a
    // component of your own so a runtime entity remembers what it was built from.
    object_id    :: distinct u32 // a designed object
    archetype_id :: distinct u32 // a template
    meta_id      :: distinct u32 // a mixin
    surface_id   :: distinct u32 // a material flyweight

///////////////////////////////////////////////////////////////////////////////
// Errors

    DOS_Error :: enum {
        None = 0,
        Invalid_Name,
        Name_Already_Exists,
        Name_Not_Found,
        Wrong_Kind,
        Load_Failed,
        Has_Derived, // a Config other Configs are based on cannot be terminated
    }

    Error :: union #shared_nil {
        DOS_Error,
        rt.Allocator_Error,
    }

///////////////////////////////////////////////////////////////////////////////
// Aliases

    //
    // Config
    //
        config_init      :: config__init
        config_terminate :: config__terminate
        user_data        :: config__user_data

    //
    // Archetypes, metas, surfaces
    //
        archetype      :: config__archetype
        meta           :: config__meta
        surface        :: config__surface
        find_archetype :: config__find_archetype
        find_meta      :: config__find_meta
        find_surface   :: config__find_surface

        parent_of  :: config__parent_of
        chain_of   :: config__chain_of
        is_kind_of :: config__is_kind_of

        attach :: proc {
            config__attach_to_archetype,
            config__attach_to_surface,
        }
        detach :: proc {
            config__detach_from_archetype,
            config__detach_from_surface,
        }
        metas_of :: proc {
            config__metas_of_archetype,
            config__metas_of_surface,
        }

        name_of :: proc {
            config__archetype_name,
            config__meta_name,
            config__surface_name,
            config__object_name,
        }

    //
    // Designed objects
    //
        object             :: config__object
        find               :: config__find_object
        set_name           :: config__set_object_name
        archetype_of       :: config__archetype_of
        objects            :: config__objects
        objects_of         :: config__objects_of
        changed_objects    :: config__changed_objects
        changed_archetypes :: config__changed_archetypes

    //
    // Values: whatever the files authored, inherited and baked
    //
        has :: proc {
            values__has_object,
            values__has_archetype,
            values__has_meta,
            values__has_surface,
        }
        node :: proc {
            values__node_object,
            values__node_archetype,
            values__node_meta,
            values__node_surface,
        }
        read :: proc {
            values__read_object,
            values__read_archetype,
            values__read_meta,
            values__read_surface,
        }
        value :: proc {
            values__value_object,
            values__value_archetype,
            values__value_meta,
            values__value_surface,
        }
        args :: proc {
            values__args_object,
            values__args_archetype,
            values__args_meta,
            values__args_surface,
        }
        source_of :: proc {
            values__source_object,
            values__source_archetype,
            values__source_meta,
            values__source_surface,
        }
        names_of :: proc {
            values__names_object,
            values__names_archetype,
            values__names_meta,
            values__names_surface,
        }

        read_node   :: values__read_node
        unread      :: values__unread
        source_name :: config__source_name

        as_int    :: values__as_int
        as_float  :: values__as_float
        as_string :: values__as_string
        as_bool   :: values__as_bool

    //
    // Bake: only needed after changing metas or parents in code; load bakes for you
    //
        bake :: config__bake

    //
    // Links between designed objects
    //
        links_of  :: links__of
        links_to  :: links__to
        link_data :: links__data

    //
    // Loading
    //
        load         :: config__load
        errors       :: config__errors
        format_error :: load_error__format
        bind_node    :: binder__bind_node
        bind_value   :: binder__bind_value

    //
    // Inspect and tooling
    //
        dump    :: config__dump
        explain :: config__explain
        cli_run :: cli__run
