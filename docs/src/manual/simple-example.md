# [Examples](@id man-examples)

Three examples are included within the repository (see the [examples](https://github.com/EnergyModelsX/EnergyModelsGasNetworks.jl/tree/main/examples) folder):

- **`single_pressure.jl`** – single-component gas transport with pressure bounds, compressors, and Weymouth approximations using Taylor approximations.
- **`pooling.jl`** – hydrogen–methane blending with pooling constraints, component tracking, and quality limits at sinks.
- **`haverly.jl`** - hydrogen-metahne blending with pooling constraints, component tracking, quality limits, pressure bounds, compressors and flow-pressure Weymouth relationships using PWA.

Run them from a REPL after adding the package:

```julia
julia> using EnergyModelsGasNetworks
julia> exdir = joinpath(pkgdir(EnergyModelsGasNetworks), "examples")
julia> include(joinpath(exdir, "pressure.jl"))
julia> include(joinpath(exdir, "pooling.jl"))
julia> include(joinpath(exdir, "haverly.jl"))
```

Or from the terminal inside the `examples` folder:

```shell
$ julia --project=. single_pressure.jl
$ julia --project=. pooling.jl
$ julia --project=. haverly.jl
```

Each script builds a `Case`, defines a solver, optimises, and prints key flows/pressures or blend proportions using `PrettyTables`. These can serve as templates for your own systems.