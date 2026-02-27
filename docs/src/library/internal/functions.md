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
constraints_flow_pressure
constraints_pwa
constraints_energy_potential
constraints_bidirectional_pressure
```

For pooling constraints:

```@docs
constraints_proportion
constraints_quality
constraints_proportion_source
constraints_tracking
```

For unit conversion:

```@docs
constraints_ext_data
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