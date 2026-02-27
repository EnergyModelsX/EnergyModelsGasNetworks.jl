# EnergyModelsGasNetworks

[![DOI](https://joss.theoj.org/papers/10.21105/joss.06619/status.svg)](https://doi.org/10.21105/joss.06619)
[![Build Status](https://github.com/EnergyModelsX/EnergyModelsGasNetworks.jl/workflows/CI/badge.svg)](https://github.com/EnergyModelsX/EnergyModelsGasNetworks.jl/actions?query=workflow%3ACI)
[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://energymodelsx.github.io/EnergyModelsGasNetworks.jl/stable/)
[![In Development](https://img.shields.io/badge/docs-dev-blue.svg)](https://energymodelsx.github.io/EnergyModelsGasNetworks.jl/dev/)

`EnergyModelsGasNetworks` extends the [`EnergyModelsX`](https://github.com/EnergyModelsX) ecosystem with pressure-feasible gas transport and pooling of blended gases (e.g. hydrogen–methane). It adds pressure potentials, Weymouth-based link constraints, and quality tracking to [`EnergyModelsBase`](https://energymodelsx.github.io/EnergyModelsBase.jl/).

## Features

- Pressure variables and bounds for nodes and links via `ResourcePressure` and `AbstractPressureData`.
- Weymouth flow–pressure constraints: Taylor cuts for single-component gases, piecewise-affine planes for blended gases.
- Pooling formulation with component tracking and quality bounds (Alfaki & Haugland, 2013).
- Helper controls for PWA generation (`set_optimizer_pwa!`, `set_step_pressure!`) and data structures for blend/pressure metadata.

## Installation

```julia
] add EnergyModelsGasNetworks
```

Choose a solver stack appropriate to your use case:
- Single-component pressure: any MIP solver (e.g. `HiGHS`).
- Pooling or blended-gas pressure: nonconvex MINLP stack (e.g. `Alpine` + `Ipopt` + a MIP solver).

See the [Quick Start](docs/src/manual/quick-start.md) for step-by-step instructions.

## Examples

Run the bundled examples from a REPL:

```julia
julia> using EnergyModelsGasNetworks
julia> exdir = joinpath(pkgdir(EnergyModelsGasNetworks), "examples")
julia> include(joinpath(exdir, "single_pressure.jl"))   # pressure drop with Taylor cuts
julia> include(joinpath(exdir, "pooling.jl"))           # hydrogen–methane blending
```

Each script builds a case, sets an optimiser, solves, and prints key flows/pressures or proportions using `PrettyTables`.

## Documentation

Full docs live under `docs/` and cover installation, examples, background, and the public API.

## Funding

Developed with support from the European Union’s Clean Hydrogen Partnership project [SHIMMER](https://shimmerproject.eu/) (grant [101111888](https://doi.org/10.3030/101111888)).
