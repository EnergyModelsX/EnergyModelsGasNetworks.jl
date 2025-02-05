curve_cache = @get_scratch!("curve_cache")
get_input_fn(x,y) = joinpath(@get_scratch!("curve_cache"),string(hash((x,y)),".json"))
read_from_json(fn) = JSON3.read(fn, PiecewiseAffineApprox.PWAFunc)
write_to_json(fn, pwa) = JSON3.write(fn, pwa)
function delete_cache() 
	for f in readdir(curve_cache)
		rm(joinpath(curve_cache, f))
	end
end

function _calculate_input(pin, pout)
    p1 = [i for i ∈ pout:5:pin]
    p2 = [j for j ∈ pout:5:pin]
    prop_H2 = [j for j ∈ 0:0.1:0.2]

    X = hcat(
        repeat(p1, inner = [length(p2) * length(prop_H2)]),
        repeat(p2, inner = [length(prop_H2)], outer = [length(p1)]),
        repeat(prop_H2, outer = [length(p1) * length(p2)])
    )
    valid_indices = X[:, 1].^2 .>= X[:, 2].^2
    X = X[valid_indices, :]

    return X
end