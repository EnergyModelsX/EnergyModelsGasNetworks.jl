function EMB.constraints_opex_var(m, n::Compressor, 𝒯ᴵⁿᵛ, modeltype::EnergyModel) end   

function create_model(case::EMB.Case, modeltype::EMB.EnergyModel, m::JuMP.Model; check_timeprofiles::Bool=true)

    m = EMB.create_model(case, modeltype, m; check_timeprofiles)

    # Data structure
    𝒯 = get_time_struct(case)
    𝒫 = get_products(case)
    𝒳ᵛᵉᶜ = get_elements_vec(case) # nodes and links
    𝒳_𝒳 = get_couplings(case)
    
    # Declaration of element variables and constraints of the problem
    for 𝒳 ∈ 𝒳ᵛᵉᶜ
        variables_pressure(m, 𝒳, 𝒳ᵛᵉᶜ, 𝒯, 𝒫)

        constraints_pressure(m, 𝒳, 𝒳ᵛᵉᶜ, 𝒯, 𝒫)
        # constraints_pressure(m, 𝒜, 𝒞, ℒᵗʳᵃⁿˢ, links, 𝒯, 𝒫)
        set_opex_var(m, 𝒳, 𝒳ᵛᵉᶜ, 𝒯, modeltype)
    end

    for couple ∈ 𝒳_𝒳
        elements_vec = [cpl(case) for cpl ∈ couple]
        constraints_pressure(m, elements_vec..., 𝒯, 𝒫)
    end

    # Construction of constraints for the problem
    # variables_blending(m, 𝒜, 𝒞, ℒᵗʳᵃⁿˢ, links, 𝒯)
    # constraints_blending(m, 𝒜, 𝒞, ℒᵗʳᵃⁿˢ, links, 𝒯)

    # Define new objective_function that includes pressure related costs
    𝒩 = get_nodes(case)
    #TODO: Eliminate when the Compressor use of Power is defined. For the moment, just assumed a cost of pressure increase.
    set_objective_function(m, 𝒩, 𝒯) 
    return m

end
function create_model(case, modeltype::EMB.EnergyModel; check_timeprofiles::Bool=true)
    m = JuMP.Model()
    create_model(case, modeltype, m; check_timeprofiles)
end

# function variables_blending(m, 𝒜, 𝒞, ℒᵗʳᵃⁿˢ, links, 𝒯)
#     𝒜ᵇ = filter(is_blendarea, 𝒜)
#     variables_proportion(m, 𝒜ᵇ, ℒᵗʳᵃⁿˢ, links, 𝒯)
#     variables_tracking_prop(m, 𝒜ᵇ, 𝒞, ℒᵗʳᵃⁿˢ, links, 𝒯)
#     variables_energy_content(m, 𝒜ᵇ, 𝒯)
# end
# function variables_proportion(m, 𝒜, ℒᵗʳᵃⁿˢ, links, 𝒯)
#     𝒮 = [n for area in 𝒜 for n in EMG.getnodesinarea(area, links) if EMB.is_source(n)]
#     #𝒜ⁿᵗ = filter(a -> !is_terminalarea(a), 𝒜)

#     @variable(m, 0 <= prop_source[𝒜, 𝒮, 𝒯] <= 1.0)

#     # Define y = 0 if s not associated to the area and y = 1 if s inside area
#     for a in 𝒜
#         𝒮ᵗᵐ = track_source(a, links, 𝒜, ℒᵗʳᵃⁿˢ) 
#         𝒮ˢ  = getsource(a, links)
        
#         for s ∈ 𝒮
#             if ~(s in 𝒮ᵗᵐ) # sources not directed to a
#                 @constraint(m, [t ∈ 𝒯], m[:prop_source][a, s, t] == 0)
#             end
#             if s ∈ 𝒮ˢ # sources inside area
#                 @constraint(m, [t ∈ 𝒯], m[:prop_source][a, s, t] == 1.0)
#             end
#         end
#     end
# end
# function variables_tracking_prop(m, 𝒜, 𝒞, ℒᵗʳᵃⁿˢ, links, 𝒯)
#     #𝒜ⁿᵗ = filter(!is_terminalarea, 𝒜)
#     𝒞ꜝ = filter(is_component_track,  𝒞)
#     if !isempty(𝒞ꜝ)
#         @variable(m, 0 <= prop_track[𝒞ꜝ, 𝒜, 𝒯] <= 1.0)
#     end
# end
# function variables_energy_content(m, 𝒜, 𝒯)
#     @variable(m, energy_content[𝒜, 𝒯] >= 0)
# end

function variables_pressure(m, 𝒩::Vector{<:EMB.Node}, 𝒳ᵛᵉᶜ, 𝒯, 𝒫)
    𝒫ᶜʳ = CompoundResource[x for x in 𝒫 if isa(x, CompoundResource)]

    # Create the node potential variables
    @variable(m, potential_in[n ∈ 𝒩, 𝒯, 𝒫ᶜʳ] >= 0)
    @variable(m, potential_out[n ∈ 𝒩, 𝒯, 𝒫ᶜʳ] >= 0)

    𝒩ᶜ = filter(n -> n isa Compressor, 𝒩)
    @variable(m, potential_Δ[n ∈ 𝒩ᶜ, 𝒯] >= 0)

end
function variables_pressure(m, ℒ::Vector{<:EMB.Link}, 𝒳ᵛᵉᶜ, 𝒯, 𝒫)
    𝒫ᶜʳ = CompoundResource[x for x in 𝒫 if isa(x, CompoundResource)]

    # Create the link potential variables
    @variable(m, link_potential_in[l ∈ ℒ, 𝒯, 𝒫ᶜʳ] >= 0)
    @variable(m, link_potential_out[l ∈ ℒ, 𝒯, 𝒫ᶜʳ] >= 0)

    # Add link binary variables
    @variable(m, has_flow[l ∈ ℒ, 𝒯], Bin) # auxiliary binary that ensures that all links with flow take value 1, it can take value 1 without flow as well. Careful with this detail, it cannot be used to check actual flows.
    @variable(m, lower_pressure_into_node[l ∈ ℒ, 𝒯], Bin) # binary for tracking lowest pressure going into a node
end

function constraints_pressure(m, 𝒩::Vector{<:EMB.Node}, 𝒳ᵛᵉᶜ, 𝒯, 𝒫) 
    # Retrieve CompoundResources from 𝒫
    𝒫ᶜʳ = CompoundResource[x for x in 𝒫 if isa(x, CompoundResource)]
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
    𝒫ᶜʳ = CompoundResource[x for x in 𝒫 if isa(x, CompoundResource)]
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
    𝒫ᶜʳ = CompoundResource[x for x in 𝒫 if isa(x, CompoundResource)]

    for n ∈ 𝒩
        constraints_pressure_couple(m, n, ℒ, 𝒯, 𝒫ᶜʳ)
    end
end
function constraints_pressure(m, ℒ::Vector{<:EMB.Link}, 𝒩::Vector{<:EMB.Node}, 𝒯, 𝒫)
    constraints_pressure(m, 𝒩, ℒ, 𝒯, 𝒫)
end

# function constraints_blending(m, 𝒜, 𝒞, ℒᵗʳᵃⁿˢ, links, 𝒯)
#     𝒜ᵇ = filter(x -> is_blendarea(x), 𝒜)
#     for a ∈ 𝒜ᵇ
#         create_blending_node(m, a, 𝒜, 𝒞, ℒᵗʳᵃⁿˢ, links, 𝒯)
#     end
# end

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
