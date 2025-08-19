curve_cache = @get_scratch!("curve_cache")
get_input_fn(x,y) = joinpath(@get_scratch!("curve_cache"),string(hash((x,y)),".json"))
read_from_json(fn) = JSON3.read(fn, PiecewiseAffineApprox.PWAFunc)
write_to_json(fn, pwa) = JSON3.write(fn, pwa)
function delete_cache() 
	for f in readdir(curve_cache)
		rm(joinpath(curve_cache, f))
	end
end