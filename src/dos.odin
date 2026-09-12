/*
    2026 (c) Oleh, https://github.com/zm69

    ODE_DOS - a Dark Object System over ODE_ECS: prototype inheritance, mixins, links and KDL
    authoring. A Config holds what designers author and describes it back to the game; the game's
    runtime is its own ODE_ECS Database, which ODE_DOS never touches.

    This file is the public API surface: short aliases and proc groups over the typename__action
    procedures defined in the other files.
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

    FLAGS_PER_GROUP     :: 128
    DEFAULT_EFFECTS_CAP :: 32
    DEFAULT_MAX_DERIVED :: 4
    DEFAULT_MAX_LINKS   :: 32_768

///////////////////////////////////////////////////////////////////////////////
// Ids

    object_id    :: distinct ecs.entity_id // a designed object
    archetype_id :: distinct ecs.entity_id // a template
    meta_id      :: distinct ecs.entity_id // a mixin
    surface_id   :: distinct ecs.entity_id // a material flyweight

///////////////////////////////////////////////////////////////////////////////
// Errors

    DOS_Error :: enum {
        None = 0,
        Invalid_Name,
        Name_Already_Exists,
        Name_Not_Found,
        Wrong_Kind,
        Parent_Not_Allowed,
        Load_Failed,
        Out_Of_Flags, // a flag group holds FLAGS_PER_GROUP bits
        Has_Derived,  // a Config other Configs are based on cannot be terminated
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
    // Config
    //
        config_init      :: config__init
        config_terminate :: config__terminate
        config_db        :: config__db
        config_capacity  :: config__capacity
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
    // Properties
    //
        property_init :: property__init
        set_property :: proc {
            property__set_archetype,
            property__set_meta,
            property__set_surface,
            property__set_object,
        }
        get_property :: proc {
            property__get_archetype,
            property__get_meta,
            property__get_surface,
            property__get_object,
        }
        unset_property :: proc {
            property__unset_archetype,
            property__unset_meta,
            property__unset_surface,
            property__unset_object,
        }
        resolve :: proc {
            property__resolve_object,
            property__resolve_archetype,
            property__resolve_surface,
        }
        resolve_with_source :: property__resolve_with_source

    //
    // Flags, state flags and effects: authored bits the game copies into its own Flags_Table
    //
        flag_init :: flag__init
        set_flag :: proc {
            flag__set_archetype,
            flag__set_meta,
            flag__set_surface,
            flag__set_object,
        }
        resolve_flag :: proc {
            flag__resolve_object,
            flag__resolve_archetype,
            flag__resolve_surface,
        }

        state_flags_init :: state_flags__init
        set_state_flag :: proc {
            state_flags__set_archetype,
            state_flags__set_meta,
            state_flags__set_surface,
            state_flags__set_object,
        }
        is_state_flag :: state_flags__is_set
        state_flags_of :: state_flags__flags_of

        effects_init    :: effects__init
        effect_register :: effects__register
        effect_bit      :: effects__bit
        effect_name     :: effects__name
        effect_count    :: effects__count
        set_effect      :: proc {
            effects__set_archetype,
            effects__set_meta,
            effects__set_surface,
            effects__set_object,
        }
        has_effect :: effects__has

        // the authored bits, indexed the way your own Flags_Table is
        bits_of :: proc {
            state_flags__bits_of,
            effects__bits_of,
        }

    //
    // Bake
    //
        bake :: config__bake

    //
    // Links between designed objects
    //
        link_init    :: link__init
        link         :: link__link
        unlink       :: link__unlink
        linked       :: link__linked
        link_data    :: link__link_data
        first_target :: link__first_target
        count_out    :: link__count_out
        count_in     :: link__count_in
        links_of     :: link__outgoing
        links_to     :: link__incoming
        next         :: link__next
        link_table   :: link__table

    //
    // Loading
    //
        load         :: config__load
        errors       :: config__errors
        format_error :: load_error__format
        bind_node    :: binder__bind_node
        bind_value   :: binder__bind_value
        decode_error :: decode_context__error

    //
    // Inspect and tooling
    //
        dump        :: config__dump
        explain     :: config__explain
        source_name :: config__source_name
        cli_run     :: cli__run
