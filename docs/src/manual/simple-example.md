# [Examples](@id man-exampl)

For the content of the example, see the *[examples](https://github.com/EnergyModelsX/EnergyModelsPooling.jl/tree/main/examples)* directory in the project repository.

From the Julia REPL (assuming you have the package installed in your environment), run
```julia
julia> using EnergyModelsPooling
# Get the path of the examples directory
julia> exdir = joinpath(pkgdir(EnergyModelsPooling), "examples")
# Include the code into the Julia REPL to run the selected example
julia> include(joinpath(exdir, "single_pressure.jl"))
julia> include(joinpath(exdir, "blend_pressure.jl"))
julia> include(joinpath(exdir, "blend_pressure_pooling.jl"))
```

The examples can be run from the terminal with

```shell script
/path/to/EnergyModelsPooling.jl/examples $ julia single_pressure.jl
/path/to/EnergyModelsPooling.jl/examples $ julia blend_pressure.jl
/path/to/EnergyModelsPooling.jl/examples $ julia blend_pressure_pooling.jl
```