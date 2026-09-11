/*
    2026 (c) Oleh, https://github.com/zm69

    ODE_DOS - a Dark Object System over ODE_ECS: prototype inheritance, mixins, links and
    KDL authoring. This file is the public API surface: short aliases and proc groups over
    the typename__action procedures defined in the other files.
*/
package ode_dos

// Base
    import rt "base:runtime"

// ODE
    import ecs "../../ode_ecs/src"
    import oc "../../ode_ecs/src/ode_core"

///////////////////////////////////////////////////////////////////////////////
// Defines

    VALIDATIONS :: #config(DOS_VALIDATIONS, true)

    DEFAULT_MAX_ARCHETYPES  :: 2_048
    DEFAULT_MAX_CONFIG_SETS :: 4
    DEFAULT_MAX_OBJECTS     :: 100_000
    DEFAULT_MAX_LINKS       :: 32_768
    DEFAULT_MAX_NAMED_OBJECTS :: 4_096

    MAX_SPAWN_HOOKS :: 32

///////////////////////////////////////////////////////////////////////////////
// Ids

    object_id     :: distinct ecs.entity_id // runtime universe: instances
    archetype_id  :: distinct ecs.entity_id // config universe: templates
    meta_id       :: distinct ecs.entity_id // config universe: mixins
    surface_id    :: distinct ecs.entity_id // config universe: material flyweights
    config_set_id :: distinct int

    CORE          :: config_set_id(0)
    NO_CONFIG_SET :: config_set_id(-1)

///////////////////////////////////////////////////////////////////////////////
// Errors

    DOS_Error :: enum {
        None = 0,
        Invalid_Name,
        Name_Already_Exists,
        Name_Not_Found,
        Wrong_Kind,
        Parent_Not_Allowed,
        Config_Set_Not_Found,
        Cannot_Unload_Core,
        Load_Failed,
        Type_Not_POD,    // runtime-side values must be plain data so the game can be saved
        Not_Overridable, // the property was declared without overridable = true
    }

    Error :: union #shared_nil {
        DOS_Error,
        ecs.API_Error,
        oc.Core_Error,
        oc.Error,
        rt.Allocator_Error,
    }

    // ODE_ECS errors as ODE_DOS errors.
    @(private)
    ecs_err :: #force_inline proc "contextless" (e: ecs.Error) -> Error {
        switch v in e {
        case ecs.API_Error:       return v
        case oc.Core_Error:       return v
        case oc.Error:            return v
        case rt.Allocator_Error:  return v
        }
        return nil
    }

///////////////////////////////////////////////////////////////////////////////
// Aliases

    //
    // World
    //
        world_init      :: world__init
        world_terminate :: world__terminate
        runtime         :: world__runtime
        user_data       :: world__user_data

    //
    // Config sets
    //
        create_config_set :: world__create_config_set
        find_config_set   :: world__find_config_set
        config_db         :: world__config_db
        unload_config_set :: world__unload_config_set

    //
    // Archetypes, metas, surfaces
    //
        archetype      :: world__archetype
        meta           :: world__meta
        surface        :: world__surface
        find_archetype :: world__find_archetype
        find_meta      :: world__find_meta
        find_surface   :: world__find_surface

        parent_of  :: world__parent_of
        chain_of   :: world__chain_of
        is_kind_of :: world__is_kind_of

        attach :: proc {
            world__attach_to_archetype,
            world__attach_to_surface,
        }
        detach :: proc {
            world__detach_from_archetype,
            world__detach_from_surface,
        }
        metas_of :: proc {
            world__metas_of_archetype,
            world__metas_of_surface,
        }

        name_of :: proc {
            world__archetype_name,
            world__meta_name,
            world__surface_name,
            world__object_name,
        }

    //
    // Objects
    //
        spawn :: proc {
            world__spawn_by_name,
            world__spawn_by_id,
        }
        destroy      :: world__destroy
        alive        :: world__alive
        archetype_of :: world__archetype_of
        find         :: world__find
        set_name     :: world__set_object_name
        on_spawn     :: world__on_spawn

    //
    // Runtime state
    //
        state_init       :: state__init
        state_flags_init :: state_flags__init

        get    :: state__get
        add    :: state__add
        remove :: state__remove
        has    :: state__has

        set      :: state_flags__set
        unset    :: state_flags__unset
        is_set   :: state_flags__is_set
        flags_of :: state_flags__flags_of

        table :: proc {
            state__table,
            state_flags__table,
        }

    //
    // Properties
    //
        property_init :: property__init
        set_property :: proc {
            property__set_archetype,
            property__set_meta,
            property__set_surface,
        }
        get_property :: proc {
            property__get_archetype,
            property__get_meta,
            property__get_surface,
        }
        unset_property :: proc {
            property__unset_archetype,
            property__unset_meta,
            property__unset_surface,
        }
        resolve :: proc {
            property__resolve_object,
            property__resolve_archetype,
            property__resolve_surface,
        }
        resolve_with_source :: property__resolve_with_source
        local               :: property__local
        override            :: property__override
        clear_override      :: property__clear_override

    //
    // Config flags
    //
        flag_init :: flag__init
        set_flag :: proc {
            flag__set_archetype,
            flag__set_meta,
            flag__set_surface,
        }
        resolve_flag :: proc {
            flag__resolve_object,
            flag__resolve_archetype,
        }
        surface_flag :: flag__surface_flag

    //
    // Bake
    //
        bake :: world__bake

    //
    // Links
    //
        link_init       :: link__init
        link            :: link__link
        unlink          :: link__unlink
        linked          :: link__linked
        link_data       :: link__link_data
        first_target    :: link__first_target
        count_out       :: link__count_out
        count_in        :: link__count_in
        unlink_all_from :: link__unlink_all_from
        unlink_all_to   :: link__unlink_all_to
        outgoing        :: link__outgoing
        incoming        :: link__incoming
        next            :: link__next
        link_table      :: link__table

    //
    // Effects
    //
        effect_register :: world__effect_register
        apply           :: world__apply
        unapply         :: world__unapply
        affected        :: world__affected
        effect_term     :: world__effect_term

    //
    // Save and load
    //
        save_game :: world__save_game
        load_game :: world__load_game

    //
    // Loading
    //
        load         :: world__load
        errors       :: world__errors
        format_error :: load_error__format
        bind_node    :: binder__bind_node
        bind_value   :: binder__bind_value
        decode_error :: decode_context__error

    //
    // Inspect and tooling
    //
        dump        :: world__dump
        explain     :: world__explain
        source_name :: world__source_name
        cli_run     :: cli__run
