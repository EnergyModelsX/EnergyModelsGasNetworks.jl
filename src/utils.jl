
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

function pwa(optimizer, K)
    Mᶜᴴ⁴ = 16.042 # molecular weight
    Mᴴ² = 2.016

    f(X) = sqrt(K) .* sqrt.(X[:, 1].^2 - X[:, 2].^2) ./ sqrt.(Mᶜᴴ⁴ .* (1 .- X[:, 3]) .+ Mᴴ² .* X[:, 3])

    p1 = [i for i ∈ 30:5:70]
    p2 = [j for j ∈ 30:5:70]
    prop_H2 = [j for j ∈ 0:0.1:0.2]

    X = hcat(
        repeat(p1, inner = [length(p2) * length(prop_H2)]),
        repeat(p2, inner = [length(prop_H2)], outer = [length(p1)]),
        repeat(prop_H2, outer = [length(p1) * length(p2)])
    )
    valid_indices = X[:, 1].^2 .>= X[:, 2].^2
    X = X[valid_indices, :]

    z = f(X) 

    pwa = approx(
    FunctionEvaluations(tuple.(eachcol(X)...), z),
    Concave(),
    # MILP(
    Cluster(
        ;optimizer,
        planes = 10,
        strict = :none,
        metric = :l1,
    )
    )

    return pwa
end