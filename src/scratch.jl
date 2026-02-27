curve_cache = @get_scratch!("curve_cache")

"""
    get_input_fn(x, y)

Generate a unique filename in the cache directory for the given input parameters `x` and `y`.
"""
get_input_fn(x, y) = joinpath(@get_scratch!("curve_cache"), string(hash((x, y)), ".json"))

"""
    read_from_json(fn)

Reads the `PiecewiseAffineApprox.PWAFunc` objects from a JSON file `fn`.
"""
read_from_json(fn) = JSON3.read(fn, PiecewiseAffineApprox.PWAFunc)

"""
    write_to_json(fn, pwa)

Writes the `PiecewiseAffineApprox.PWAFunc` object `pwa` to a JSON file `fn`.
"""
write_to_json(fn, pwa) = JSON3.write(fn, pwa)

"""
    delete_cache()

Deletes all files in the cache directory. Use with caution, as this will remove all cached PWA approximations.
"""
function delete_cache()
    for f ∈ readdir(curve_cache)
        rm(joinpath(curve_cache, f))
    end
end
