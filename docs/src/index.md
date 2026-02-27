```@meta
CurrentModule = EnergyModelsGasNetworks
```

# EnergyModelsGasNetworks

`EnergyModelsGasNetworks` extends [EnergyModelsX](https://github.com/EnergyModelsX) with pressure-aware gas transport and pool-quality tracking for solving admixing problems. It adds two tightly coupled capabilities on top of [`EnergyModelsBase`](https://energymodelsx.github.io/EnergyModelsBase.jl/):

- **Flow–pressure coupling.** Nodes and links carry pressure potentials, enforce bounds via [`AbstractPressureData`](@ref) subtypes, namely [`FixPressureData`](@ref), [`MaxPressureData`](@ref) and [`MinPressureData`](@ref), and approximate the Weymouth relation. It is required adding the data type [`PressureLinkData`](@ref) to the links for adequate approximation, and combine it with the data type [`RefBlendData`](@ref) in case of transporting [`ResourcePooling`](@ref) resources (blended gases). Single-component gases use first-order Taylor cuts; blended gases use piecewise-affine planes from [PiecewiseAffineApprox](https://github.com/sintefore/PiecewiseAffineApprox.jl).
- **Pooling and quality tracking.** Based on the multi-commodity formulation of [alfaki_multi-commodity_2013](@cite), compositions are tracked through [`PoolingNode`](@ref) and `EnergyModelBase.Sinks`. Maximum/minimum component shares in nodes are set through [`RefBlendData`](@ref).


## Manual outline

- **Getting started.** Jump to the [Quick Start](@ref man-quick_start) for installation, solvers, and running the bundled examples.
- **Examples.** See the [examples overview](@ref man-examples) to guide you through examples for single-gas transport and admixing problems.
- **Overview and Theory.** The [overview](@ref overview) and [theory](@ref method) sections explain briefly the philosophy on `EnergyModelsGasNetworks` as well as the theory behind the flow-pressure and pooling problems and how they are addressed to solve the admixing problem.
- **Library.** The [library page](@ref lib-public) lists the main types, controls, and data structures.

```@contents
Pages = [
    "manual/quick-start.md",
    "manual/simple-example.md",
    "manual/NEWS.md",
    "background/overview.md",
    "background/method.md",
    "library/public.md",
    "library/internal/elements.md",
    "library/internal/functions.md"
]
Depth = 1
```

## Additional Info
`EnergyModelsGasNetworks` integrates the package [Scratch.jl](https://github.com/JuliaPackaging/Scratch.jl), which enables storing mutable containers of data. Specifically, it is applied to managing temporary storage of the piecewise-affine approximation data. In this way, the optimization used for finding the corresponding planes does not need to be performed again if the same conditions (i.e., Weymouth constants, maximum inlet pressure, minimum outlet pressure, pressure steps) are inputs for a link.

Additionally, the formulation of the method proposed was validated using the open-source simulation model [SHIMMER++](https://github.com/shimmerhydrogen/shimmer.git) in collaboration with Politecnico di Torino.

## Project funding

The development of `EnergyModelsGasNetworks` was funded by the the European Union’s Clean Hydrogen Partnership in the project [SHIMMER](https://shimmerproject.eu/) under grant agreement [101111888](https://doi.org/10.3030/101111888).
