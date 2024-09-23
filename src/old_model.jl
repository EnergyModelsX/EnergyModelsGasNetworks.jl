"""
    create_model(case, modeltype::EnergyModel; check_timeprofiles::Bool=true)
"""

function create_model(case, modeltype::EnergyModel, m::JuMP.Model; check_timeprofiles::Bool=true)
    @debug "Construct model"

    # Call of the basic model through EMG
    m = EMG.create_model(case, modeltype, m; check_timeprofiles)

    # Data structure
    𝒜 = case[:areas]
    links = case[:links]
    ℒᵗʳᵃⁿˢ = case[:transmission]
    𝒫 = case[:products]
    𝒦 = case[:components]
    𝒯 = case[:T]
    e = case[:e]
    
    # Declaration of variables for blend structs
    variables_proportion(m, ℒᵗʳᵃⁿˢ, 𝒜, links, 𝒯)

    # Construction of constraints for the problem
    constraints_blending(m, 𝒜, links, ℒᵗʳᵃⁿˢ, 𝒯)
    constraints_proportionbound(m, 𝒜, links, ℒᵗʳᵃⁿˢ, 𝒯)
    constraints_qualitybound(m, 𝒜, links, ℒᵗʳᵃⁿˢ, 𝒯)
    if !isnothing(e)
        constraints_energycontent(m, 𝒜, links, ℒᵗʳᵃⁿˢ, 𝒯, e)
    end

    return m

end
function create_model(case, modeltype::EnergyModel; check_timeprofiles::Bool=true)
    m = JuMP.Model()
    create_model(case, modeltype, m; check_timeprofiles)
end

function variables_proportion(m, ℒᵗʳᵃⁿˢ, 𝒜, links, 𝒯)
    𝒮 = [n for area in 𝒜 for n in EMG.getnodesinarea(area, links) if EMB.is_source(n)]
    TM = vcat([modes(l) for l in ℒᵗʳᵃⁿˢ]...)
    # Call all potential prop_source 
    @variable(m, 0 <= prop_source[tm ∈ TM, s ∈ 𝒮, t ∈ 𝒯] <= 1)

    for l in ℒᵗʳᵃⁿˢ
        𝒮ᵗᵐ = track_source(l, links, 𝒜, ℒᵗʳᵃⁿˢ)
        for tm in collect(keys(𝒮ᵗᵐ)), s in 𝒮
            if ~(s in 𝒮ᵗᵐ[tm])
                @constraint(m, [t ∈ 𝒯], m[:prop_source][tm, s, t] == 0)
            end
        end
    end

end

function EMB.constraints_flow_in(m, n::RefBlending, 𝒯::TimeStructure, modeltype::EnergyModel)
    # Declaration of the required subsystems
    𝒫ⁱⁿ  = inputs(n)
    𝒫ᵒᵘᵗ  = outputs(n) # In RefBlending this should be a singleton

    if length(𝒫ᵒᵘᵗ) > 1
        @error("The type `RefBlending` should have only one output resource")
    else
        # Constraint for the total input stream and the total flow
        @constraint(m, [t ∈ 𝒯, p ∈ 𝒫ᵒᵘᵗ],
            sum(m[:flow_in][n, t, p_in] for p_in ∈ 𝒫ⁱⁿ) == m[:flow_out][n, t, p])
    end

end

function constraints_blending(m, 𝒜, links, ℒᵗʳᵃⁿˢ, 𝒯)
    for l in ℒᵗʳᵃⁿˢ
        a_from, _ = l.from, l.to
        𝒮ᵗᵐ = track_source(l, links, 𝒜, ℒᵗʳᵃⁿˢ) # Dict{TransmissionMode, Vector{RefSource}}
        
        for tm in keys(𝒮ᵗᵐ)
            # Get resources in tm
            tm_p = tm.inlet
            
            # Get the TransmissionModes connected to a_from that share the same resource as tm
            TM = [tm for l in corr_to(a_from, ℒᵗʳᵃⁿˢ) for tm in modes(l) if tm.outlet == tm_p]
            
            # Get sources in a_from. Intersection between all sources associated with tm (𝒮ᵗᵐ) and the nodes in a_from
            sources_a_from = intersect([n for n in EMG.getnodesinarea(a_from, links)], 𝒮ᵗᵐ) 
            
            # Get the links going out of sources in a_from
            links_from_sources = Dict()
            for s in sources_a_from
                link_from, _ = EMB.link_sub(links, s) 
                links_from_sources[s] = link_from 
            end       
            
            @constraint(m, [t ∈ 𝒯, s ∈ 𝒮ᵗᵐ[tm]],
            m[:prop_source][tm, s, t] * m[:trans_in][tm, t] == 
            sum(m[:prop_source][tm_, s, t] * m[:trans_out][tm_, t] for tm_ in TM) + sum(m[:link_in][link, t, c] for key in keys(links_from_sources) if s == key for link in links_from_sources[s] for c in outputs(s)))
        end
    end
end

function constraints_proportionbound(m, 𝒜, links, ℒᵗʳᵃⁿˢ, 𝒯) # Bound for products
    𝒟 = [n for area in 𝒜 for n in EMG.getnodesinarea(area, links) if EnergyModelsPooling.is_blending_sink(n)]   # get terminals

    for d in 𝒟
        ℒᵗᵒ = vcat([modes(l) for l in EMG.corr_to(getarea(𝒜, d, links), ℒᵗʳᵃⁿˢ)]...) # transmission modes linked to d
        𝒮ᵗᵐ = track_source(d, links, 𝒜, ℒᵗʳᵃⁿˢ)
        blend = collect(keys(d.input))[1]

        if blend isa ResourceBlend
            for p in blend.res_blend
                @constraint(m, [t ∈ 𝒯],
                    sum((EnergyModelsPooling.get_proportion(s, p) - EnergyModelsPooling.get_proportion(d, p)) * m[:prop_source][tm, s, t] * m[:trans_out][tm, t] 
                    for s ∈ 𝒮ᵗᵐ for tm ∈ ℒᵗᵒ) <= 0) # if source not vinculated to tm, prop_source = 0.
            end
        end
    end
end

function constraints_qualitybound(m, 𝒜, links, ℒᵗʳᵃⁿˢ, 𝒯) # Bound for products
    𝒟 = [n for area in 𝒜 for n in EMG.getnodesinarea(area, links) if EnergyModelsPooling.is_blending_sink(n)]   # get terminals

    for d in 𝒟
        ℒᵗᵒ = vcat([modes(l) for l in EMG.corr_to(getarea(𝒜, d, links), ℒᵗʳᵃⁿˢ)]...) # transmission modes linked to d
        𝒮ᵗᵐ = track_source(d, links, 𝒜, ℒᵗʳᵃⁿˢ)
        𝒦ᵈ = collect(keys(d.quality))

        for k in 𝒦ᵈ
            @constraint(m, [t ∈ 𝒯],
                sum((EnergyModelsPooling.get_quality(s, k) - EnergyModelsPooling.get_quality(d, k)) * m[:prop_source][tm, s, t] * m[:trans_out][tm, t] 
                for s ∈ 𝒮ᵗᵐ for tm ∈ ℒᵗᵒ) <= 0) # if source not vinculated to tm, prop_source = 0.
        end
    end
end


function constraints_energycontent(m, 𝒜, links, ℒᵗʳᵃⁿˢ, 𝒯, e) # TODO: Suggest to add a new network node or keep it as it is
    # Case of sink receiving blending resource
    𝒟 = [n for area in 𝒜 for n in EMG.getnodesinarea(area, links) if EnergyModelsPooling.is_blending_sink(n)]   # get terminals

    for d in 𝒟
        ℒᵗᵒ = vcat([modes(l) for l in EMG.corr_to(getarea(𝒜, d, links), ℒᵗʳᵃⁿˢ)]...) # transmission modes linked to d
        𝒮 = [n for area in 𝒜 for n in EMG.getnodesinarea(area, links) if EMB.is_source(n)] # get all sources
        blend = collect(keys(d.input))[1]
       
        @constraint(m, [t ∈ 𝒯],
        sum(EnergyModelsPooling.output(e, p) * 
            sum(m[:prop_source][tm, s, t] * m[:trans_out][tm, t] for s ∈ 𝒮 for tm ∈ ℒᵗᵒ if p ∈ outputs(s))
        for p in blend.res_blend) >= m[:cap_use][d, t])
    end

    # Case of sink not receiving blending resource
    𝒟 = setdiff([n for area in 𝒜 for n in EMG.getnodesinarea(area, links) if EMB.is_sink(n)], 𝒟)  # get set of sources that are not blending sinks

    for d in 𝒟
        ℒᵗᵒ = vcat([modes(l) for l in EMG.corr_to(getarea(𝒜, d, links), ℒᵗʳᵃⁿˢ)]...) # transmission modes linked to d
        𝒮 = [n for area in 𝒜 for n in EMG.getnodesinarea(area, links) if EMB.is_source(n)] # get all sources
       
        @constraint(m, [t ∈ 𝒯],
        sum(EnergyModelsPooling.output(e, p) * 
            sum(m[:prop_source][tm, s, t] * m[:trans_out][tm, t] for s ∈ 𝒮 for tm ∈ ℒᵗᵒ if p ∈ outputs(s))
        for p in blend.res_blend) >= m[:cap_use][d, t])
    end
end


"""
    Function to obtain the set of sources linked to the n element. 
    
    If n is `Transmission`, the output is a dictionary with the sources linked to each transmission model.
    For each transmission mode, the sources are those in the area from which n starts and the sources from adjacent areas.
    A source is considered to be linked if it outflows the same product as tm or it is a product forming the blend in tm.

    The process for this step is as follow:
        1. For loop through all the links to RefBlending node n.
        2. Filter the node ´nodeto_n´ that goes to node n and is GeoAvailability
        3. Get the area containing the GeoAvailability node ´nodeto_n´
        4. From the transmission connected to the area, filter those transmissions directed towards its and whose 
        5. From this adjacent areas, find the sources 
"""
function track_source(n::EnergyModelsPooling.Blending, links, 𝒜, ℒᵗʳᵃⁿˢ)
    all_sources = Vector{RefSource}()
    products_n = collect(keys(n.input))

    # Collect sources directly linked to n
    sources = getsource(n, links)
    sources = [s for s in sources if collect(keys(s.output))[1] ∈ products_n]
    append!(all_sources, sources)

    # Collect sources from adjacent Areas
    _, nlinks_to = EMB.link_sub(links, n)                                           # links to n

    for link in nlinks_to                                                          
        n1 = link.from                                                              # node to n
        if EnergyModelsPooling.is_geoavailability(n1)
            adj_areas = getadjareas(𝒜, n1, ℒᵗʳᵃⁿˢ)                                  # find adjacent Areas within n1's Area
            sources = getsource(adj_areas, links, products_n)                       # get sources of adjacent Areas with same input products to n
            append!(all_sources, sources)
        end
    end

    return unique!(all_sources)
end

function track_source(l::EMG.Transmission, links, 𝒜, ℒᵗʳᵃⁿˢ)
    # Get the area from which l starts.
    a_from, _ = l.from, l.to 

    all_sources = Dict{TransmissionMode, Vector{}}()
    for tm in modes(l)
        # Get the resource in tm
        tm_p = tm.inlet

        # Collect sources contained in a_from that are linked to tm
        𝒮 = getsource(a_from, links, tm_p)

        # Collect sources from adjacent Areas
        n1 = EMG.availability_node(a_from)
        adj_areas = setdiff(getadjareas(𝒜, n1, ℒᵗʳᵃⁿˢ), [a_from])           # find adjacent Areas without including a_from
        for adj_area in adj_areas                           
            sources = getsource(adj_area, links, tm_p)                       # get sources of adjacent Areas with same input products to n
            append!(𝒮, sources)
        end

        all_sources[tm] = 𝒮
    end

    return all_sources
end

function track_source(n::EnergyModelsPooling.RefBlendingSink, links, 𝒜, ℒᵗʳᵃⁿˢ)
    all_sources = Vector{}()
    products_n = collect(keys(n.input))
    
    # Collect sources from same area to n
    _, nlinks_to = EMB.link_sub(links, n)   #links to n

    for l ∈ nlinks_to
        n1 = l.from                         #nodes to n
        if EnergyModelsPooling.is_geoavailability(n1)
            sources = getsource(n1, links)                                        # get sources within n1's Area
            sources = [s for s in sources if collect(keys(s.output))[1] ∈ products_n]   # get sources of input products of n
            append!(all_sources, getsource(n1, links))
        end
    end

    # Collect sources from adjacent Areas
    for l ∈ nlinks_to
        n1 = l.from            #nodes to n1
        if EnergyModelsPooling.is_geoavailability(n1)
            adj_areas = getadjareas(𝒜, n1, ℒᵗʳᵃⁿˢ)
            sources = getsource(adj_areas, links, products_n)
            append!(all_sources, sources)
        end
    end

    return unique!(all_sources)

end
function track_source(n::Area, links, 𝒜, ℒᵗʳᵃⁿˢ, products)
    av = EMG.availability_node(n)
    all_sources = Vector{RefSource}()

    # Collect sources directly linked to n
    # not apply as demand is treated in an isolated area

    # Collect sources from adjacent Areas
    adj_areas = getadjareas(𝒜, av, ℒᵗʳᵃⁿˢ)                                  # find adjacent Areas within n1's Area
    sources = getsource(adj_areas, links, products)                       # get sources of adjacent Areas whose outputs in products
    append!(all_sources, sources)

    return unique!(all_sources)
end

function getarea(A::Vector{Area}, n::GeoAvailability)
    for area in A
        if n == EMG.availability_node(area)
            return area
        end
    end
end
function getarea(A::Vector{Area}, n::RefBlending, links)
    nlinks_from, _ = EMB.link_sub(links, n)                                           # links to n

    n1 = nothing
    for link in nlinks_from                                                          
        if EnergyModelsPooling.is_geoavailability(link.to)
            n1 = link.to                                                              # node to n
        end
    end

    for area in A
        if n1 == EMG.availability_node(area)
            return area
        end
    end
end
function getarea(A::Vector{Area}, n::RefBlendingSink, links)
    nlinks_from, nlinks_to = EMB.link_sub(links, n)                                           # links to n

    n1 = nothing
    for link in nlinks_to                                                         
        if EnergyModelsPooling.is_geoavailability(link.from)
            n1 = link.from                                                              # node to n
        end
    end

    for area in A
        if n1 == EMG.availability_node(area)
            return area
        end
    end
end

"""
Function to find all the areas that have a path to node n. Based on depth-first search algorithm
"""
function getadjareas(A::Vector{Area}, n::GeoAvailability, ℒᵗʳᵃⁿˢ)
    area_n = getarea(A, n)
    visited = Vector{Area}()
    stack = [area_n]

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

function getsource(n::EMB.Node, links)
    nodes = []

    for l ∈ links
        n1 = l.from
        n2 = l.to

        if (n2 == n) && !(n1 ∈ nodes) && (EMB.is_source(n1))
            push!(nodes, n1)
        end
    end
    return nodes
end
function getsource(A::Vector{Area}, links, products)
    all_sources = []
    for a in A
        # get sources from adjacent Areas with RefBlending whose output is an input Resource in n
        blend_nodes   = [i for i in EMG.getnodesinarea(a, links) if EnergyModelsPooling.is_blending_node(i) && (collect(keys(i.output))[1] in products)]
        sources_nodes = []
        for b in blend_nodes
            append!(sources_nodes, getsource(b, links))
        end
        # get sources from adjacent Areas without RefBlending whose output is an input Resource in n
        append!(sources_nodes, [i for i in EMG.getnodesinarea(a, links) if EMB.is_source(i) && (collect(keys(i.output))[1] in products)])
        sources_nodes = unique!(sources_nodes)

        append!(all_sources, sources_nodes)
    end
    return all_sources
end
function getsource(area::Area, links::Vector{Link}, resource::ResourceCarrier)
    # Get the GeoAvailability node in the area
    n = availability_node(area)

    # Get the Links to GeoAvailability
    _, links_to  = EMB.link_sub(links, n)
    # Get the Sources to GeoAvailability through the Links to GeoAvailability
    sources_area = [l.from for l ∈ links_to if EMB.is_source(l.from)]
    # Filter the Sources to only those with output product == resource
    𝒮 = [n for n in sources_area if resource ∈ outputs(n)]

    return 𝒮
end

function getsource(area::Area, links::Vector{Link}, resource::ResourceBlend)
    # Find the RefBlendings in Area whose output is ResourceBlend
    blending_nodes = [n for n ∈ EMG.getnodesinarea(area, links) if (is_blending_node(n)) & (resource ∈ outputs(n))]

    # Get the resources forming the ResourceBlend
    resources = resource.res_blend

    # Gather the Sources connected to blending_nodes 
    𝒮 = []
    for b ∈ blending_nodes
        _, links_to = EMB.link_sub(links, b)
        sources_b = [l.from for l ∈ links_to if EMB.is_source(l.from)]
        append!(𝒮, sources_b)
    end

    return 𝒮
end

function getblending(A::Vector{RefArea})
    blending_dict = Dict()
    for na in A
        na_av = EMG.availability_node(na)
        links_from, links_to = EMB.link_sub(links, na_av)
        na_b = [l.from for l in links_to if EnergyModelsPooling.is_blending_node(l.from)][1] # blending node of neighbour area

        blending_dict[na] = na_b
    end

    return blending_dict
end