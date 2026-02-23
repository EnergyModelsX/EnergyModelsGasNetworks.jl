# [Examples](@id man-examples)

Three examples are included within the repository (see the [examples](https://github.com/EnergyModelsX/EnergyModelsPooling.jl/tree/main/examples) folder):

- **`single_pressure.jl`** – single-component gas transport with pressure bounds, compressors, and Weymouth approximations using Taylor approximations.
- **`pooling.jl`** – hydrogen–methane blending with pooling constraints, component tracking, and quality limits at sinks.
- **`pooling_pressure.jl`** - hydrogen-metahne blending with pooling constraints, component tracking, quality limits, pressure bounds, compressors and flow-pressure Weymouth relationships using PWA.

Run them from a REPL after adding the package:

```julia
julia> using EnergyModelsPooling
julia> exdir = joinpath(pkgdir(EnergyModelsPooling), "examples")
julia> include(joinpath(exdir, "single_pressure.jl"))
julia> include(joinpath(exdir, "pooling.jl"))
julia> include(joinpath(exdir, "pooling_pressure.jl"))
```

Or from the terminal inside the `examples` folder:

```shell
$ julia single_pressure.jl
$ julia pooling.jl
$ julia pooling_pressure.jl
```

Each script builds a `Case`, defines a solver, optimises, and prints key flows/pressures or blend proportions using `PrettyTables`. These can serve as templates for your own systems.