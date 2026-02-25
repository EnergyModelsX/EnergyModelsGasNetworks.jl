```@meta
CurrentModule = EnergyModelsPooling
```

# [Scratch](@id aux-scratch)


## [Main Functions](@id aux-scratch-mainfun)

The file `src/scratch.jl` contains the following:

- [`get_input_fn`](@ref): Finds the unique filename stored in the cache for a given input `x` and `y`. Used to store and retrieve the piecewise-affine results data.
- [`read_from_json`](@ref): Retrieves the `PiecewiseAffineApprox.PWAFunc` objects contained in the cached JSON files.
- [`write_to_json`](@ref): Writes the `PiecewiseAffineApprox.PWAFunc` objects in a particular cached filename.
- [`delete_cache`](@ref): Deletes all files in the cache directory. 

All the functions are internally used by `EnergyModelsPooling`, except [`delete_cache`](@ref) which can be called directly by the user if necessary.

