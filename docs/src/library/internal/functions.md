# [Internal functions](@id lib-int-fun)

## [Index](@id lib-int-fun-idx)

```@index
Pages = ["functions.md"]
```

```@meta
CurrentModule = EnergyModelsGasNetworks
```

## [Variable creation functions](@id lib-int-fun-var)

Most of the variable creation functions in `EnergyModelsGasNetworks` is built on the existing methods in `EnergyModelsBase`.

```@docs
EnergyModelsBase.variables_node
EnergyModelsBase.variables_flow_resource
EnergyModelsBase.variables_ext_data
```

## [Constraint functions](@id lib-int-fun-con)

The functions used to dispatch on the type of `Resource` and element (i.e., `Link` and `Node`) are defined by extending the `EnergyModelsBase` package.

```@docs
EnergyModelsBase.constraints_resource
EnergyModelsBase.constraints_couple_resource
EnergyModelsBase.create_link
EnergyModelsBase.constraints_capacity
EnergyModelsBase.constraints_opex_var
EnergyModelsBase.constraints_opex_fixed
EnergyModelsBase.constraints_flow_in
EnergyModelsBase.constraints_flow_out
```

Then, specific functions in `EnergyModelsGasNetworks` are defined for the generation of the flow-pressure and pooling constraints.

Those for flow-pressure relationships are:

```@docs
constraints_balance_pressure
constraints_pressure_bounds_element
constraints_pressure_bounds
constraints_pressure_couple
constraints_flow_capacity
_maximum_link_capacity
constraints_flow_pressure
constraints_pwa
constraints_energy_potential
constraints_bidirectional_pressure
```

For pooling constraints:

```@docs
blend_share_plan
validate_blend_topology
constraints_blend_proportion
constraints_quality_blend
constraints_node_component_balance
constraints_link_component_balance
constraints_component_blend
```

For unit conversion and blend storage:

```@docs
constraints_ext_data
```

## [Checks](@id lib-int-fun-checks)

```@docs
EnergyModelsBase.check_node_data
```

## [Utils](@id lib-int-fun-utils)

General utils are: 

```@docs
nodes_upstream_of
sources_upstream_of
get_links_to_node_blend
define_points_curve
res_types
res_types_seg
_get_optimizer
link_data
```

Specific utils to perform calculations on input data:

```@docs
normalised_weymouth
calculate_flow_to_approximate
get_step_pressure
get_pwa
get_specific_energy_content
resource_lhv
```

## [Scratch](@id lib-int-fun-scr)

`EnergyModelsGasNetworks` integrates the package [Scratch.jl](https://github.com/JuliaPackaging/Scratch.jl), which enables storing mutable containers of data. Specifically, it is applied to managing temporary storage of the piecewise-affine approximation data. In this way, the optimization used for finding the corresponding planes does not need to be performed again if the same conditions (i.e., Weymouth constants, maximum inlet pressure, minimum outlet pressure, pressure steps) are inputs for a link.

```@docs
get_input_fn
read_from_json
write_to_json
```

All the functions are internally used by `EnergyModelsGasNetworks`, except [`delete_cache`](@ref) which can be called directly by the user if necessary.

## [Private internals](@id lib-int-fun-private)

The following private functions (prefixed `_`) are documented here for completeness. They are
called internally by the public constraint and data functions and are not part of the public API.

```@docs
_constraints_flow_pressure_taylor
_clamp_pwa_intercepts
_constraints_blend_passthrough
_blend_provenance
_downstream_share_anchor
_constraints_dpn_bigm
_constraints_dpn_pwl
_constraints_deblend_extraction
_constraints_unit_conversion_blend_lhv
_constraints_unit_conversion_co2_output
_blend_links_in
_is_blend_passthrough
_is_composition_source
_blend_storage_mode
_constraints_proportion_normalisation
_switched_links
_constraints_passthrough_single_outflow
_dpn_flow_bound
_maximum_node_capacity
_pwa_flow_bound
_pwa_fit_ok
_pwa_underestimate
_with_seed
```