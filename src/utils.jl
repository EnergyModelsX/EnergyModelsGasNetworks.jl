
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
c2_fraction: fraction of component 2 in the gas
M²: molecular weight of component 2
"""
function weymouth_specgrav(weymouth, pin, pout, c2_fraction, M1, M2) 
    return sqrt(weymouth) * sqrt(pin^2 - pout^2) / sqrt(M1 * (1 - c2_fraction) + M2 * c2_fraction)
end