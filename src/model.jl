function EMB.constraints_opex_var(m, n::SimpleCompressor, 𝒯ᴵⁿᵛ, modeltype::EMB.EnergyModel)
    @constraint(m, [t_inv ∈ 𝒯ᴵⁿᵛ],
        m[:opex_var][n, t_inv] == 0)
end

function EMB.constraints_flow_in(
    m,
    n::PoolingNode,
    𝒯::TimeStructure,
    modeltype::EMB.EnergyModel,
)
    # Declaration of the required subsets
    𝒫ⁱⁿ = EMB.inputs(n)

    # Constraint for the individual input stream connections
    @constraint(m, [t ∈ 𝒯],
        sum(m[:flow_in][n, t, p] for p ∈ 𝒫ⁱⁿ) == m[:cap_use][n, t]
    )
end

"""
    create_link(m, l::CapDirect, 𝒯, 𝒫::Vector{<:CompoundResource}) 

New create_link function for `CapDirect` to ensure capacity limits
"""
function EMB.create_link(m, l::CapDirect, 𝒯, 𝒫, modeltype::EMB.EnergyModel)
    # Generic link in which each output corresponds to the input
    @constraint(m, [t ∈ 𝒯, p ∈ EMB.link_res(l)],
        m[:link_out][l, t, p] == m[:link_in][l, t, p]
    )

    @constraint(
        m, [t ∈ 𝒯, p ∈ EMB.link_res(l)],
        m[:link_in][l, t, p] <= capacity(l, t)
    )
end

function create_model(
    case::EMB.Case,
    modeltype::EMB.EnergyModel,
    m::JuMP.Model,
    optimizer;
    check_timeprofiles::Bool = true,
)
    m = EMB.create_model(case, modeltype, m; check_timeprofiles)

    # Data structure
    𝒯 = get_time_struct(case)
    𝒫 = get_products(case)
    𝒫ᶜʳ = CompoundResource[x for x ∈ 𝒫 if isa(x, ResourcePressure)] # TODO: Eliminate when the SimpleCompressor use of Power is defined
    𝒳ᵛᵉᶜ = get_elements_vec(case) # nodes and links
    𝒳_𝒳 = get_couplings(case)

    # Declaration of element variables and constraints of the problem
    for 𝒳 ∈ 𝒳ᵛᵉᶜ
        variables_pressure(m, 𝒳, 𝒳ᵛᵉᶜ, 𝒯, 𝒫)
        variables_blending(m, 𝒳, 𝒳ᵛᵉᶜ, 𝒯, 𝒫)

        constraints_pressure(m, 𝒳, 𝒳ᵛᵉᶜ, 𝒯, 𝒫, optimizer)
        constraints_blending(m, 𝒳, 𝒳ᵛᵉᶜ, 𝒯, 𝒫)

        if !isempty(𝒫ᶜʳ)
            set_opex_var(m, 𝒳, 𝒳ᵛᵉᶜ, 𝒯, modeltype) # TODO: Eliminate when the SimpleCompressor use of Power is defined. For the moment, just assumed a cost of pressure increase.
        end
    end

    for couple ∈ 𝒳_𝒳
        elements_vec = [cpl(case) for cpl ∈ couple]
        constraints_pressure(m, elements_vec..., 𝒯, 𝒫)
        constraints_blending(m, elements_vec..., 𝒯, 𝒫)
    end

    if !isempty(𝒫ᶜʳ)
        # Define new objective_function that includes pressure related costs
        𝒩 = get_nodes(case)
        ℒ = get_links(case)
        #TODO: Eliminate when the Compressor use of Power is defined. For the moment, just assumed a cost of pressure increase.
        set_objective_function(m, 𝒩, ℒ, 𝒯)
    end
    return m
end
function create_model(
    case,
    modeltype::EMB.EnergyModel,
    optimizer;
    check_timeprofiles::Bool = true,
)
    m = JuMP.Model()
    create_model(case, modeltype, m, optimizer; check_timeprofiles)
end

# function variables_energy_content(m, 𝒜, 𝒯)
#     @variable(m, energy_content[𝒜, 𝒯] >= 0)
# end

function variables_blending(m, 𝒩::Vector{<:EMB.Node}, 𝒳ᵛᵉᶜ, 𝒯, 𝒫)
    # Get the blended resources from 𝒫
    𝒫ᶜʳ = ResourcePooling[x for x ∈ 𝒫 if isa(x, ResourcePooling)]

    # If the system includes a blended resource, initialise the variables
    if !isempty(𝒫ᶜʳ)
        # Get the subresources included in the blends (ResourceCarrier or ResourcePressure)
        𝒫ˢᵘᵇ = [r for res_blend ∈ 𝒫ᶜʳ for r ∈ subresources(res_blend)]

        # Get the sources that can provide the subresources
        𝒮 = filter(n -> EMB.is_source(n) && all(res -> res in 𝒫ˢᵘᵇ, EMB.outputs(n)), 𝒩)

        # Create all combinations (node, source) for tracking the proportion of source in each node
        @variable(m, 0 <= proportion_source[𝒩, s ∈ 𝒮, 𝒯] <= 1.0)

        # Create a proportion_track variable for each node and subresource
        @variable(m, 0 <= proportion_track[n ∈ 𝒩, 𝒯, p ∈ 𝒫ˢᵘᵇ] <= 1.0)
    end
end
function variables_blending(m, ℒ::Vector{<:EMB.Link}, 𝒳ᵛᵉᶜ, 𝒯, 𝒫) end

function variables_pressure(m, 𝒩::Vector{<:EMB.Node}, 𝒳ᵛᵉᶜ, 𝒯, 𝒫)
    𝒫ᶜʳ = CompoundResource[
        x for
        x ∈ 𝒫 if isa(x, ResourcePressure) || x isa ResourcePooling{<:ResourcePressure}
    ]

    if !isempty(𝒫ᶜʳ)
        # Create the node potential variables
        @variable(m, potential_in[n ∈ 𝒩, 𝒯, inputs(n)] >= 0)
        @variable(m, potential_out[n ∈ 𝒩, 𝒯, outputs(n)] >= 0)

        𝒩ᶜ = filter(n -> n isa SimpleCompressor, 𝒩)
        @variable(m, potential_Δ[n ∈ 𝒩ᶜ, 𝒯] >= 0)
    end
end
function variables_pressure(m, ℒ::Vector{<:EMB.Link}, 𝒳ᵛᵉᶜ, 𝒯, 𝒫)
    𝒫ᶜʳ = CompoundResource[
        x for
        x ∈ 𝒫 if isa(x, ResourcePressure) || x isa ResourcePooling{<:ResourcePressure}
    ]

    if !isempty(𝒫ᶜʳ)
        # Create the link potential variables
        @variable(m, link_potential_in[l ∈ ℒ, 𝒯, inputs(l)] >= 0)
        @variable(m, link_potential_out[l ∈ ℒ, 𝒯, inputs(l)] >= 0)

        # Add link binary variables
        @variable(m, has_flow[l ∈ ℒ, 𝒯], Bin) # auxiliary binary that ensures that all links with flow take value 1, it can take value 1 without flow as well. Careful with this detail, it cannot be used to check actual flows.
        @variable(m, lower_pressure_into_node[l ∈ ℒ, 𝒯], Bin) # binary for tracking lowest pressure going into a node
    end
end

function constraints_pressure(m, 𝒩::Vector{<:EMB.Node}, 𝒳ᵛᵉᶜ, 𝒯, 𝒫, optimizer)
    # Retrieve CompoundResources from 𝒫
    𝒫ᶜʳ = CompoundResource[
        x for x ∈ 𝒫 if x isa ResourcePressure || x isa ResourcePooling{<:ResourcePressure}
    ]

    for n ∈ 𝒩
        # Define internal pressure balance constraints
        constraints_pressure(m, n, 𝒯, 𝒫ᶜʳ)

        # Get AbstractPressureData and generate limit constraints if any
        pressure_data = filter(d -> d isa AbstractPressureData, get_pressuredata(n))
        if !isempty(pressure_data)
            for d ∈ pressure_data
                constraints_pressure_limit(m, n, d, 𝒯, 𝒫ᶜʳ)
            end
        end
    end
end
function constraints_pressure(m, ℒ::Vector{<:EMB.Link}, 𝒳ᵛᵉᶜ, 𝒯, 𝒫, optimizer)
    # Retrieve CompoundResources from 𝒫
    𝒫ᶜʳ = CompoundResource[
        x for
        x ∈ 𝒫 if isa(x, ResourcePressure) || x isa ResourcePooling{<:ResourcePressure}
    ]
    for l ∈ ℒ
        # Define internal pressure balance constraints
        constraints_pressure(m, l, 𝒯, 𝒫ᶜʳ)

        # Get AbstractPressureData and generate limit constraints if any
        pressure_data = filter(d -> d isa AbstractPressureData, get_pressuredata(l))
        if !isempty(pressure_data)
            for d ∈ pressure_data
                constraints_pressure_limit(m, l, d, 𝒯, 𝒫ᶜʳ)
            end
        end
        constraints_flow_limit(m, l, 𝒯, 𝒫ᶜʳ)

        𝒫_sub = res_types_seg(𝒫ᶜʳ)
        for p_sub ∈ 𝒫_sub
            constraints_flow_pressure(m, l, 𝒯, p_sub, optimizer)
        end
    end
end
function constraints_pressure(m, 𝒩::Vector{<:EMB.Node}, ℒ::Vector{<:EMB.Link}, 𝒯, 𝒫)
    𝒫ᶜʳ = CompoundResource[
        x for
        x ∈ 𝒫 if isa(x, ResourcePressure) || isa(x, ResourcePooling{<:ResourcePressure})
    ]

    for n ∈ 𝒩
        if !isempty(𝒫ᶜʳ)
            constraints_pressure_couple(m, n, ℒ, 𝒯, 𝒫ᶜʳ)
        end
    end
end
function constraints_pressure(m, ℒ::Vector{<:EMB.Link}, 𝒩::Vector{<:EMB.Node}, 𝒯, 𝒫)
    constraints_pressure(m, 𝒩, ℒ, 𝒯, 𝒫)
end

function constraints_blending(m, 𝒩::Vector{<:EMB.Node}, 𝒳ᵛᵉᶜ, 𝒯, 𝒫)
    # Retrieve CompoundResources from 𝒫
    𝒫ᶜʳ = ResourcePooling[x for x ∈ 𝒫 if isa(x, ResourcePooling)]

    for n ∈ 𝒩
        constraints_proportion(m, n, 𝒳ᵛᵉᶜ, 𝒯, 𝒫ᶜʳ)
        constraints_quality(m, n, 𝒳ᵛᵉᶜ, 𝒯, 𝒫ᶜʳ)
    end
end
function constraints_blending(m, ℒ::Vector{<:EMB.Link}, 𝒳ᵛᵉᶜ, 𝒯, 𝒫) end
function constraints_blending(m, 𝒩::Vector{<:EMB.Node}, ℒ::Vector{<:EMB.Link}, 𝒯, 𝒫)
    # Retrieve CompoundResources from 𝒫
    𝒫ᶜʳ = ResourcePooling[x for x ∈ 𝒫 if isa(x, ResourcePooling)]

    constraints_proportion_couple(m, 𝒩, ℒ, 𝒯, 𝒫ᶜʳ)

    for n ∈ 𝒩
        constraints_tracking(m, n, ℒ, 𝒯, 𝒫ᶜʳ)
    end
end
function constraints_blending(m, ℒ::Vector{<:EMB.Link}, 𝒩::Vector{<:EMB.Node}, 𝒯, 𝒫)
    constraints_blending(m, 𝒩, ℒ, 𝒯, 𝒫)
end

function set_opex_var(m, 𝒳::Vector{<:EMB.Node}, 𝒳ᵛᵉᶜ, 𝒯, modeltype)
    # Add addiitonal potential_add_cost for nodes
    𝒩ᶜ = filter(n -> n isa SimpleCompressor, 𝒳)

    # Define variables
    𝒯ᴵⁿᵛ = strategic_periods(𝒯)
    @variable(m, potential_add_cost[𝒩ᶜ, 𝒯ᴵⁿᵛ] >= 0)

    # Add potential_add_cost compressors
    for n ∈ 𝒩ᶜ
        @constraint(m, [t_inv ∈ 𝒯ᴵⁿᵛ],
            m[:potential_add_cost][n, t_inv] ==
            sum(
                m[:potential_Δ][n, t] * EMB.opex_var(n, t) * EMB.scale_op_sp(t_inv, t) for
                t ∈ t_inv
            )
        )
    end
end
function set_opex_var(m, 𝒳::Vector{<:EMB.Link}, 𝒳ᵛᵉᶜ, 𝒯, modeltype)
    # Define variables
    𝒯ᴵⁿᵛ = strategic_periods(𝒯)
    @variable(m, potential_add_cost_link[𝒳, 𝒯ᴵⁿᵛ] >= 0)

    # Add small potential_add_cost cost to other nodes to penalise for increasing potential 
    for l ∈ 𝒳
        𝒫ˡ = EMB.link_res(l)
        if !isempty(𝒫ˡ)
            @constraint(m, [t_inv ∈ 𝒯ᴵⁿᵛ],
                m[:potential_add_cost_link][l, t_inv] ==
                0.01 * sum(
                    m[:link_potential_in][l, t, p] + m[:link_potential_out][l, t, p]
                    for p ∈ 𝒫ˡ, t ∈ t_inv
                ))
        end
    end
end
function set_opex_var(m, 𝒳::Vector{<:EMB.AbstractElement}, 𝒳ᵛᵉᶜ, 𝒯, modeltype) end
function set_objective_function(m, 𝒩::Vector{<:EMB.Node}, ℒ::Vector{<:EMB.Link}, 𝒯)
    𝒩ᶜ = filter(n -> n isa SimpleCompressor, 𝒩)
    𝒯ᴵⁿᵛ = strategic_periods(𝒯)

    # Build objective with conditional terms
    obj = objective_function(m)
    
    if !isempty(𝒩ᶜ)
        obj -= sum(m[:potential_add_cost][n, t_inv] for n ∈ 𝒩ᶜ, t_inv ∈ 𝒯ᴵⁿᵛ)
    end
    
    if !isempty(ℒ) && haskey(m, :potential_add_cost_link)
        obj -= sum(m[:potential_add_cost_link][l, t_inv] for l ∈ ℒ, t_inv ∈ 𝒯ᴵⁿᵛ)
    end

    JuMP.set_objective_function(m, obj)
end
