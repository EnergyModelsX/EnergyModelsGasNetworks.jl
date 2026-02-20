# EnergyModelsPooling

`EnergyModelsPooling` extends [EnergyModelsX](https://github.com/EnergyModelsX) with functionality to model gas networks. The model allows integrating i) flow-pressure constraints and/or 2) quality tracking using a pooling formulation.

The flow-pressure constraints allows setting internal pressures in `Node`s and `Link`s, set pressure bounds (i.e., maximum, minimum and fixed pressures) using the new data type [`AbstractPressureData`](@ref), transmission of pressures between `Node`s and `Link`s and define flow-pressure relationships in each `Link`. For the latter constraints, `EnergyModelsPooling` approximates the non-linear Weymouth formulation either with First Order Taylor Approximations in the case of single gases flowing througth the pipe or tangent planes defined using [PiecewiseAffineApprox](https://github.com/sintefore/PiecewiseAffineApprox.jl) for blended gases of two components.

The quality tracking is based on the multi-commodity model formulated in Alfaki & Haugland (2013), and allows tracking the composition of the components reaching each pooling node ([`PoolingNode`](@ref)) and `Sink`. Minimum and maximum qualities for each component can be defined at each node using the subtypes of the abstract data type [`BlendData`].

## Manual outline

```@contents
Pages = [
    "manual/quick-start.md",
    "manual/simple-example.md",
    "manual/NEWS.md",
]
Depth = 1
```

## Description of the resources

<!-- ```@contents
Pages = [
    "resources/resourceheat.md",
]
Depth = 1
``` -->

## Description of the links

<!-- ```@contents
Pages = [
    "links/dhpipe.md",
]
Depth = 1
``` -->

## Description of the nodes

<!-- ```@contents
Pages = [
    "nodes/heatpump.md",
    "nodes/thermalenergystorage.md",
    "nodes/heatexchanger.md",
]
Depth = 1
``` -->

## How to guides

<!-- ```@contents
Pages = [
    "howto/simple_conversion.md",
    "howto/contribute.md",
]
Depth = 1
``` -->

## Library outline

<!-- ```@contents
Pages = [
    "library/public.md",
    "library/internals/types-EMH.md",
    "library/internals/methods-fields.md",
    "library/internals/methods-EMH.md",
    "library/internals/methods-EMB.md",
]
Depth = 1
``` -->

## Background

```@contents
Pages = [
    "background/background.md",
]
Depth = 1
```

## References
Alfaki, M., & Haugland, D. (2013). A multi-commodity flow formulation for the generalized pooling problem. Journal of Global Optimization, 56(3), 917–937. https://doi.org/10.1007/s10898-012-9890-7

## Project Funding

The development of `EnergyModelsPooling` was funded by the the European Union’s Clean Hydrogen Partnership in the project [SHIMMER](https://shimmerproject.eu/) under grant agreement [101111888](https://doi.org/10.3030/101111888).
