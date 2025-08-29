function EMB.constraints_opex_var(m, n::Compressor, 𝒯ᴵⁿᵛ, modeltype::EMB.EnergyModel) end 

function EMB.constraints_flow_in(m, n::RefBlend, 𝒯::TimeStructure, modeltype::EMB.EnergyModel)
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
function EMB.create_link(m, 𝒯, 𝒫, l::CapDirect, modeltype::EMB.EnergyModel, formulation::EMB.Formulation)
    # Generic link in which each output corresponds to the input
    @constraint(m, [t ∈ 𝒯, p ∈ EMB.link_res(l)],
        m[:link_out][l, t, p] == m[:link_in][l, t, p]
    )

    @constraint(
        m, [t ∈ 𝒯, p ∈ EMB.link_res(l)],
        m[:link_in][l, t, p] <= capacity(l, t)
    )
end

function create_model(case::EMB.Case, modeltype::EMB.EnergyModel, m::JuMP.Model; check_timeprofiles::Bool=true)

    m = EMB.create_model(case, modeltype, m; check_timeprofiles)

    # Data structure
    𝒯 = get_time_struct(case)
    𝒫 = get_products(case)
    𝒫ᶜʳ = CompoundResource[x for x in 𝒫 if isa(x, ResourceComponentPotential) || isa(x, ResourcePotential)] # TODO: Eliminate when the Compressor use of Power is defined
    𝒳ᵛᵉᶜ = get_elements_vec(case) # nodes and links
    𝒳_𝒳 = get_couplings(case)
    
    # Declaration of element variables and constraints of the problem
    for 𝒳 ∈ 𝒳ᵛᵉᶜ
        variables_pressure(m, 𝒳, 𝒳ᵛᵉᶜ, 𝒯, 𝒫)
        variables_blending(m, 𝒳, 𝒳ᵛᵉᶜ, 𝒯, 𝒫)

        constraints_pressure(m, 𝒳, 𝒳ᵛᵉᶜ, 𝒯, 𝒫)
        constraints_blending(m, 𝒳, 𝒳ᵛᵉᶜ, 𝒯, 𝒫)

        if !isempty(𝒫ᶜʳ)
            set_opex_var(m, 𝒳, 𝒳ᵛᵉᶜ, 𝒯, modeltype) # TODO: Eliminate when the Compressor use of Power is defined. For the moment, just assumed a cost of pressure increase.
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

        #TODO: Eliminate when the Compressor use of Power is defined. For the moment, just assumed a cost of pressure increase.
        set_objective_function(m, 𝒩, 𝒯) 
    end
    return m

end
function create_model(case, modeltype::EMB.EnergyModel; check_timeprofiles::Bool=true)
    m = JuMP.Model()
    create_model(case, modeltype, m; check_timeprofiles)
end

# function variables_energy_content(m, 𝒜, 𝒯)
#     @variable(m, energy_content[𝒜, 𝒯] >= 0)
# end

function variables_blending(m, 𝒩::Vector{<:EMB.Node}, 𝒳ᵛᵉᶜ, 𝒯, 𝒫)
    𝒫ᶜʳ = ResourceBlend[x for x in 𝒫 if isa(x, ResourceBlend)]

    # If the system includes a blended resource, initialise the variables
    if !isempty(𝒫ᶜʳ)
        𝒮 = filter(n -> EMB.is_source(n) && 
                    all(res -> (isa(res, ResourceComponent) || isa(res, ResourceComponentPotential)), EMB.outputs(n)), 𝒩)

        # Create all combinations (node, source) for tracking the proportion of source in each node
        @variable(m, 0 <= proportion_source[𝒩, s ∈ 𝒮, 𝒯] <= 1.0)
        @variable(m, 0 <= proportion_track[𝒩, 𝒯, 𝒫ᶜʳ] <= 1.0)
    end
end
function variables_blending(m, ℒ::Vector{<:EMB.Link}, 𝒳ᵛᵉᶜ, 𝒯, 𝒫) end

function variables_pressure(m, 𝒩::Vector{<:EMB.Node}, 𝒳ᵛᵉᶜ, 𝒯, 𝒫)
    𝒫ᶜʳ = CompoundResource[x for x in 𝒫 if isa(x, ResourceComponentPotential) || isa(x, ResourcePotential)]

    if !isempty(𝒫ᶜʳ)
        # Create the node potential variables
        @variable(m, potential_in[n ∈ 𝒩, 𝒯, 𝒫ᶜʳ] >= 0)
        @variable(m, potential_out[n ∈ 𝒩, 𝒯, 𝒫ᶜʳ] >= 0)

        𝒩ᶜ = filter(n -> n isa Compressor, 𝒩)
        @variable(m, potential_Δ[n ∈ 𝒩ᶜ, 𝒯] >= 0)
    end

end
function variables_pressure(m, ℒ::Vector{<:EMB.Link}, 𝒳ᵛᵉᶜ, 𝒯, 𝒫)
    𝒫ᶜʳ = CompoundResource[x for x in 𝒫 if isa(x, ResourceComponentPotential) || isa(x, ResourcePotential)]

    if !isempty(𝒫ᶜʳ)
        # Create the link potential variables
        @variable(m, link_potential_in[l ∈ ℒ, 𝒯, 𝒫ᶜʳ] >= 0)
        @variable(m, link_potential_out[l ∈ ℒ, 𝒯, 𝒫ᶜʳ] >= 0)

        # Add link binary variables
        if !isempty(𝒫ᶜʳ)
            @variable(m, has_flow[l ∈ ℒ, 𝒯], Bin) # auxiliary binary that ensures that all links with flow take value 1, it can take value 1 without flow as well. Careful with this detail, it cannot be used to check actual flows.
            @variable(m, lower_pressure_into_node[l ∈ ℒ, 𝒯], Bin) # binary for tracking lowest pressure going into a node
        end
    end
end

function constraints_pressure(m, 𝒩::Vector{<:EMB.Node}, 𝒳ᵛᵉᶜ, 𝒯, 𝒫) 
    # Retrieve CompoundResources from 𝒫
    𝒫ᶜʳ = CompoundResource[x for x in 𝒫 if isa(x, ResourceComponentPotential) || isa(x, ResourcePotential)]
    𝒫_sub = res_types_seg(𝒫ᶜʳ)

    for n ∈ 𝒩, comp_res ∈ 𝒫_sub
        limit_data = filter(d -> d isa RefPressureData, get_pressuredata(n))

        constraints_pressure(m, n, 𝒯, comp_res)
        if !isempty(limit_data)
            for d ∈ limit_data
                constraints_pressure_limit(m, n, d, 𝒯, comp_res)
            end
        end
    end
end
function constraints_pressure(m, ℒ::Vector{<:EMB.Link}, 𝒳ᵛᵉᶜ, 𝒯, 𝒫)
    # Retrieve CompoundResources from 𝒫
    𝒫ᶜʳ = CompoundResource[x for x in 𝒫 if isa(x, ResourceComponentPotential) || isa(x, ResourcePotential)]
    𝒫_sub = res_types_seg(𝒫ᶜʳ)

    for l ∈ ℒ, comp_res ∈ 𝒫_sub
        limit_data = filter(d -> d isa RefPressureData, get_pressuredata(l))

        constraints_pressure(m, l, 𝒯, comp_res)
        if !isempty(limit_data)
            for d in limit_data
                constraints_pressure_limit(m, l, d, 𝒯, comp_res)
            end
        end
        constraints_flow_limit(m, l, 𝒯, comp_res)
        constraints_flow_pressure(m, l, 𝒯, comp_res)
    end
end
function constraints_pressure(m, 𝒩::Vector{<:EMB.Node}, ℒ::Vector{<:EMB.Link}, 𝒯, 𝒫)    
    𝒫ᶜʳ = CompoundResource[x for x in 𝒫 if isa(x, ResourceComponentPotential) || isa(x, ResourcePotential)]

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
    𝒫ᶜʳ = ResourceBlend[x for x in 𝒫 if isa(x, ResourceBlend)]

    for n ∈ 𝒩
        constraints_proportion(m, n, 𝒳ᵛᵉᶜ, 𝒯, 𝒫ᶜʳ)
        constraints_quality(m, n, 𝒳ᵛᵉᶜ, 𝒯, 𝒫ᶜʳ)
    end
end
function constraints_blending(m, ℒ::Vector{<:EMB.Link}, 𝒳ᵛᵉᶜ, 𝒯, 𝒫) end
function constraints_blending(m, 𝒩::Vector{<:EMB.Node}, ℒ::Vector{<:EMB.Link}, 𝒯, 𝒫) 
    # Retrieve CompoundResources from 𝒫
    𝒫ᶜʳ = ResourceBlend[x for x in 𝒫 if isa(x, ResourceBlend)]

    constraints_proportion_couple(m, 𝒩, ℒ, 𝒯, 𝒫ᶜʳ)
end
function constraints_blending(m, ℒ::Vector{<:EMB.Link}, 𝒩::Vector{<:EMB.Node}, 𝒯, 𝒫)
    constraints_blending(m, 𝒩, ℒ, 𝒯, 𝒫)
end

function set_opex_var(m, 𝒳::Vector{<:EMB.Node}, 𝒳ᵛᵉᶜ, 𝒯, modeltype)    
    𝒩ᶜ = filter(n -> n isa Compressor, 𝒳)

    𝒯ᴵⁿᵛ = strategic_periods(𝒯)
    for n ∈ 𝒩ᶜ
        @constraint(m, [t_inv ∈ 𝒯ᴵⁿᵛ],
            m[:opex_var][n, t_inv] ==
            sum(m[:potential_Δ][n, t] * EMB.opex_var(n, t) * EMB.scale_op_sp(t_inv, t) for t ∈ t_inv)
        )
    end
end
function set_opex_var(m, 𝒳::Vector{<:EMB.AbstractElement}, 𝒳ᵛᵉᶜ, 𝒯, modeltype) end
function set_objective_function(m, 𝒩::Vector{<:EMB.Node}, 𝒯)
    𝒩ᶜ = filter(n -> n isa Compressor, 𝒩)

    @objective(m, Max,
        objective_function(m) + sum(m[:opex_var][n, t_inv] for n ∈ 𝒩ᶜ, t_inv ∈ strategic_periods(𝒯))
    )
end