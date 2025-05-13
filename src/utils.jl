
function track_source(a::Area, links, 𝒜, ℒᵗʳᵃⁿˢ)
    all_sources = Vector{}()

    𝒜ᵃ = getadjareas(a, ℒᵗʳᵃⁿˢ)                             # it includes a
    for area in 𝒜ᵃ
        sources = getsource(area, links)                       # get sources of adjacent Areas whose outputs in products
        append!(all_sources, sources)
    end

    return unique!(all_sources)
end
function getarea(A::Vector{<:Area}, n::Availability)
    for area in A
        if n == EMG.availability_node(area)
            return area
        end
    end
end
function gettransmission(L::Vector{Transmission}, n::Area)
    transto_n = []
    transfrom_n = []
    for trans in L
        if n == trans.from
            push!(transfrom_n, trans)
        elseif n == trans.to
            push!(transto_n, trans)
        end
    end
    return transto_n, transfrom_n
end
function getadjareas(a::Area, ℒᵗʳᵃⁿˢ)
    visited = Vector()
    stack = Vector{Area}()
    append!(stack, [a])

    while !isempty(stack)
        current_area = pop!(stack)
        push!(visited, current_area)
        transto_area, _ = gettransmission(ℒᵗʳᵃⁿˢ, current_area)                     # transmissions to area of n
        for l in transto_area
            n1 = l.from
            if ~(n1 in visited)
                push!(stack, n1)
            end
        end
    end
    
    return visited
end

function getsource(a::Area, links)
    source_nodes   = [i for i in EMG.getnodesinarea(a, links) if EMB.is_source(i)]
    return source_nodes
end


"""
    weymouth_constant(FLOW, PIN, POUT)

Calculate the normalised flow constant with respect to the specific gravity using specific operating points.
Assumed to use operational points from flows from CH4.
"""
function weymouth_constant(FLOW, PIN, POUT)

    W = FLOW^2/(PIN^2 - POUT^2)

    Mᶜʰ⁴ = 16.042 # g/mol
    Mᵃⁱʳ = 28.96 # g/mol
    g = Mᶜʰ⁴/Mᵃⁱʳ   # specific gravity of CH4

    weymouth_ct = W * g

    return weymouth_ct
end
function weymouth_constant(W)

    #W = FLOW^2/(PIN^2 - POUT^2)

    Mᶜʰ⁴ = 16.042 # g/mol
    Mᵃⁱʳ = 28.96 # g/mol
    g = Mᶜʰ⁴/Mᵃⁱʳ   # specific gravity of CH4

    weymouth_ct = W * g

    return weymouth_ct
end

"""
    weymouth_specgrav(weymouth, pin, pout, fractionC2, M1, M2)

Calculates the flow of gas using the Weymouth equation. 

Typically, the flow constant in the Weymouth equation depends on the specific gravity of the gas. Here, we need instead a normalised constant with respect to the specific gravity (or independent of specific gravity).
This allows to recalculate the flows considering the different proportions of the components.

# Variables
- **weymouth**: flow constant **independent on the specific gravity of the mixture**.
- **pin**: Inlet pressure.
- **pout**: Outlet pressure.
- **fractionC2**: Fraction of the second component.
- **M1**: Molecular mass of the first component.
- **M2**: Molecular mass of the second component.
"""
function weymouth_specgrav(weymouth_ct, pin, pout, fractionC2, M1, M2) 
    Mᵃⁱʳ = 28.96 # g/mol
    return sqrt(weymouth_ct * (pin^2 - pout^2) * (Mᵃⁱʳ/ (M1 * (1 - fractionC2) + M2 * fractionC2)))
end