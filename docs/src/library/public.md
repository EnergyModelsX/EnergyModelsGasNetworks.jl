```@meta
CurrentModule = EnergyModelsPooling
```

# [Public Interface](@id lib-public)

This page lists the main user-facing types and controls added by `EnergyModelsPooling`.

## Controls

```@docs
set_step_pressure!
set_optimizer_pwa!
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
PoolingNode
RefConversion
```

## Links

```@docs
CapDirect
```

## Data structures

```@docs
PressureLinkData
FixPressureData
MaxPressureData
MinPressureData
RefBlendData
BlendLinkData
FlowToEnergyData
```
