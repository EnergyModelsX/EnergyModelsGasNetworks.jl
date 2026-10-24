```@meta
CurrentModule = EnergyModelsGasNetworks
```

# [Public Interface](@id lib-public)

This page lists the main user-facing types and controls added by `EnergyModelsGasNetworks`.

## Controls

```@docs
set_step_pressure!
set_optimizer_pwa!
set_clamp_pwa_intercepts!
get_clamp_pwa_intercepts
delete_cache
```

## Resources and blends

```@docs
ResourcePressure
ResourcePooling
```

## Nodes

```@docs
SimpleCompressor
FlowPressureCompressor
PoolingNode
DiscretizedPoolingNode
BlendingNode
TransitNode
DeblendNode
RefConversion
```

## Links

```@docs
CapDirect
ZeroDrop
```

## Data structures

```@docs
PressureLinkData
FixPressureData
MaxPressureData
MinPressureData
RefBlendData
BlendLinkData
DiscretizationData
BlendStorageData
DeblendData
FlowToEnergyData
EmissionsConversionData
```

## Data accessors

```@docs
get_n_points
get_method
get_max_proportion
get_tracked_resource
get_storage_mode
discharge_composition
get_blendstoragedata
psa_efficiency
max_extract_fraction
get_co2_intensity
```
