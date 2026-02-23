# EnergyModelsPooling

`EnergyModelsPooling` extends [EnergyModelsX](https://github.com/EnergyModelsX) with pressure-aware gas transport and pool-quality tracking. It adds two tightly coupled capabilities on top of [`EnergyModelsBase`](https://energymodelsx.github.io/EnergyModelsBase.jl/):

- **Flow–pressure coupling.** Nodes and links carry pressure potentials, enforce bounds via [`AbstractPressureData`](@ref), and approximate the Weymouth relation. Single-component gases use first-order Taylor cuts; blended gases use piecewise-affine planes from [PiecewiseAffineApprox](https://github.com/sintefore/PiecewiseAffineApprox.jl).
- **Pooling and quality tracking.** Based on the multi-commodity formulation of [@alfaki_multi-commodity_2013], compositions are tracked through [`PoolingNode`](@ref) and sinks. Maximum/minimum component shares are set through [`BlendData`](@ref) subtypes.

Use this package when you need pressure-feasible gas transport, hydrogen–methane blending, or compositional quality constraints within an `EnergyModelsX` optimisation.

## Manual outline

```@contents
Pages = [
    "manual/quick-start.md",
    "manual/simple-example.md",
    "manual/NEWS.md",
    "background/background.md",
    "library/public.md",
]
Depth = 2
```

- **Getting started.** Jump to the [Quick Start](@ref man-quick_start) for installation, solvers, and running the bundled examples.
- **Examples.** See the [examples overview](@ref man-examples) for what each script demonstrates.
- **Background.** The [background note](@ref background-overview) summarises the pressure and pooling formulations.
- **Library.** The [library page](@ref lib-public) lists the main types, controls, and data structures.

## Description of elements
```@contents
Pages = [
    "elements/resources.md",
    "elements/nodes.md",
    "elements/links.md",
    "elements/data.md"
]
```

## Auxiliary functions #TODO: Add weymouth calculation functions
```@contents
Pages = [    
    "aux-fun/scratch.md",
]
```

## Project funding

The development of `EnergyModelsPooling` was funded by the the European Union’s Clean Hydrogen Partnership in the project [SHIMMER](https://shimmerproject.eu/) under grant agreement [101111888](https://doi.org/10.3030/101111888).
