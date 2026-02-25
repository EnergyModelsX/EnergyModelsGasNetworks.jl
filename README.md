# EnergyModelsGasNetworks

`EnergyModelsPooling` extends the [`EnergyModelsX`](https://github.com/EnergyModelsX) ecosystem with pressure-feasible gas transport and pooling of blended gases (e.g. hydrogen–methane). It adds pressure potentials, Weymouth-based link constraints, and quality tracking to [`EnergyModelsBase`](https://energymodelsx.github.io/EnergyModelsBase.jl/).

## Features

- Pressure variables and bounds for nodes and links via `ResourcePressure` and `AbstractPressureData`.
- Weymouth flow–pressure constraints: Taylor cuts for single-component gases, piecewise-affine planes for blended gases.
- Pooling formulation with component tracking and quality bounds (Alfaki & Haugland, 2013).
- Helper controls for PWA generation (`set_optimizer_pwa!`, `set_step_pressure!`) and data structures for blend/pressure metadata.

## Installation

```julia
] add TimeStruct EnergyModelsBase EnergyModelsPooling
```

Choose a solver stack appropriate to your use case:
- Single-component pressure: any MIP solver (e.g. `HiGHS`).
- Pooling or blended-gas pressure: nonconvex MINLP stack (e.g. `Alpine` + `Ipopt` + a MIP solver).

See the [Quick Start](docs/src/manual/quick-start.md) for step-by-step instructions.

## Examples

Run the bundled examples from a REPL:

```julia
julia> using EnergyModelsPooling
julia> exdir = joinpath(pkgdir(EnergyModelsPooling), "examples")
julia> include(joinpath(exdir, "single_pressure.jl"))   # pressure drop with Taylor cuts
julia> include(joinpath(exdir, "pooling.jl"))           # hydrogen–methane blending
```

Each script builds a case, sets an optimiser, solves, and prints key flows/pressures or proportions using `PrettyTables`.

## Documentation

Full docs live under `docs/` and cover installation, examples, background, and the public API.

## Funding

Developed with support from the European Union’s Clean Hydrogen Partnership project [SHIMMER](https://shimmerproject.eu/) (grant [101111888](https://doi.org/10.3030/101111888)).
