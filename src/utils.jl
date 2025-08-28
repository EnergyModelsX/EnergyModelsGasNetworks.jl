"""
    track_associated_nodes(n::Node, ℒ::Vector{<:Link})

Tracks all nodes associated with a given node `n` through the links in `ℒ`. We refer to associated
to all the nodes that lead to `n` following the direction of the links.
"""
function track_associated_nodes(n::EMB.Node, ℒ::Vector{<:EMB.Link})
    visited = Vector{EMB.Node}()
    stack = Vector{EMB.Node}()
    append!(stack, [n])

    while !isempty(stack)
        # Get current area from stack
        current_area = pop!(stack)

        # Add it as visited
        push!(visited, current_area)

        # Extract links into `n`
        _, ℒᵗᵒ = EMB.link_sub(ℒ, current_area)
        
        for l in ℒᵗᵒ
            # Get node at the other end of the link
            n1 = l.from
            if ~(n1 in visited)
                push!(stack, n1)
            end
        end
    end
    
    return visited
end

"""
    track_source(n::Node, ℒ::Vector{<:Link})

Tracks all nodes associated to `n` and filter by source nodes.
"""
function track_source(n::EMB.Node, ℒ::Vector{<:EMB.Link})
    𝒩ᵃ = track_associated_nodes(n, ℒ)                            
    𝒩ˢ = filter(EMB.is_source, 𝒩ᵃ)
    return unique!(𝒩ˢ)
end

# """
#     weymouth_constant(FLOW, PIN, POUT)

# Calculate the normalised flow constant with respect to the specific gravity using specific operating points.
# Assumed to use operational points from flows from CH4.
# # """
# function weymouth_constant(FLOW, PIN, POUT)

#     W = FLOW^2/(PIN^2 - POUT^2)

#     Mᶜʰ⁴ = 16.042 # g/mol
#     Mᵃⁱʳ = 28.96 # g/mol
#     g = Mᶜʰ⁴/Mᵃⁱʳ   # specific gravity of CH4

#     weymouth_ct = W * g

#     return weymouth_ct
# end
# function weymouth_constant(W)

#     Mᶜʰ⁴ = 16.042 # g/mol
#     Mᵃⁱʳ = 28.96 # g/mol
#     g = Mᶜʰ⁴/Mᵃⁱʳ   # specific gravity of CH4

#     weymouth_ct = W * g

#     return weymouth_ct
# end

"""
    calculate_flow(constant, x1, x2, x3)

Calculates the flow of gas with the Weymouth equation using the normalised weymouth constant. 

Typically, the constant in the Weymouth equation depends on the specific gravity of the gas. Here, we need instead a normalised it 
with respect to the specific gravity. This allows to calculate the flows considering the different proportions of the components.

# Variables
- constant::Float64 -> Normalised Weymouth constant
- x1::Float64 -> Inlet pressures
- x2::Float64 -> Outlet pressures
- x3::Float64 -> Proportion of hydrogen
"""
function calculate_flow(constant, x1, x2, x3)
	M1 = 16.042
	M2 = 2.016
	M3 = 28.96

	return sqrt(constant * (x1^2 - x2^2) * (M3/ (M1 * (1 - x3) + M2 * x3)))
end

"""
    calculate_X(x1, x2, x3)

Defines the points (inlet and outlet pressures and proportion) for the surface for the PWA.
"""
function calculate_X(x1, x2, x3)
	X = hcat(
        repeat(x1, inner = [length(x2) * length(x3)]),
        repeat(x2, inner = [length(x3)], outer = [length(x1)]),
        repeat(x3, outer = [length(x1) * length(x2)])
    )
    valid_indices = X[:, 1].^2 .> X[:, 2].^2
    X = X[valid_indices, :]
	return X
end

"""
    test_approx(pwa, constant, pin, pout, prop)

Compares the approximation results with the value applying the Weymouth equation
"""
function test_approx(pwa, constant, pin, pout, prop)
    for p_out in pout:pin
        println(PiecewiseAffineApprox.evaluate(pwa, (pin, p_out, prop)), "\t", 
                calculate_flow(constant, pin, p_out, prop), "\t", 
                PiecewiseAffineApprox.evaluate(pwa, (pin, p_out, prop))>=calculate_flow(constant, pin, p_out, prop))
    end
end