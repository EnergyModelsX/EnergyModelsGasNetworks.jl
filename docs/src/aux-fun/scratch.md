# [Scratch](@id aux-scratch)

`EnergyModelsPooling` integrates the package [Scratch.jl](https://github.com/JuliaPackaging/Scratch.jl), which enables storing mutable containers of data. Specifically, it is applied to managing temporary storage of the piecewise-affine approximation data. In this way, the optimization used for finding the corresponding planes does not need to be performed again if the same conditions (i.e., Weymouth constants, maximum inlet pressure, minimum outlet pressure, pressure steps) are inputs for a link.

## [Main Functions](@id aux-scratch-mainfun)

The file `src/scratch.jl` contains the following:

- [`get_input_fn`](@ref): Finds the unique filename stored in the cache for a given input `x` and `y`. Used to store and retrieve the piecewise-affine results data.
- [`read_from_json`](@ref): Retrieves the `PiecewiseAffineApprox.PWAFunc` objects contained in the cached JSON files.
- [`write_to_json`](@ref): Writes the `PiecewiseAffineApprox.PWAFunc` objects in a particular cached filename.
- [`delete_cache`](@ref): Deletes all files in the cache directory. 

All the functions are internally used by `EnergyModelsPooling`, except [`delete_cache`](@ref) which can be called directly by the user if necessary.

