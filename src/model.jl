function create_model(case, modeltype::EnergyModel, m::JuMP.Model; check_timeprofiles::Bool=true)
    @debug "Construct model"

    # Call of the basic model through EMG
    m = EMG.create_model(case, modeltype, m; check_timeprofiles)

    # Data structure
    𝒜 = case[:areas]
    links = case[:links]
    ℒᵗʳᵃⁿˢ = case[:transmission]
    𝒫 = case[:products]
    𝒞 = case[:components]
    𝒯 = case[:T]
    pwa = case[:pwa]
    
    # Declaration of variables for blend structs
    variables_blending(m, 𝒜, 𝒞, ℒᵗʳᵃⁿˢ, links, 𝒯)
    variables_pressure(m, 𝒜, ℒᵗʳᵃⁿˢ, links, 𝒯)

    # Construction of constraints for the problem
    constraints_blending(m, 𝒜, 𝒞, ℒᵗʳᵃⁿˢ, links, 𝒯)
    constraints_pressure(m, 𝒜, 𝒞, ℒᵗʳᵃⁿˢ, links, 𝒯, 𝒫, pwa)
    
    return m

end
function create_model(case, modeltype::EnergyModel; check_timeprofiles::Bool=true)
    m = JuMP.Model()
    create_model(case, modeltype, m; check_timeprofiles)
end

function variables_blending(m, 𝒜, 𝒞, ℒᵗʳᵃⁿˢ, links, 𝒯)
    𝒜ᵇ = filter(is_blendarea, 𝒜)
    variables_proportion(m, 𝒜ᵇ, ℒᵗʳᵃⁿˢ, links, 𝒯)
    variables_tracking_prop(m, 𝒜ᵇ, 𝒞, ℒᵗʳᵃⁿˢ, links, 𝒯)
end
function variables_proportion(m, 𝒜, ℒᵗʳᵃⁿˢ, links, 𝒯)
    𝒮 = [n for area in 𝒜 for n in EMG.getnodesinarea(area, links) if EMB.is_source(n)]
    𝒜ⁿᵗ = filter(a -> !is_terminalarea(a), 𝒜)

    @variable(m, 0 <= prop_source[𝒜ⁿᵗ, 𝒮, 𝒯] <= 1.0)

    # Define y = 0 if s not associated to the area and y = 1 if s inside area
    for a in 𝒜ⁿᵗ
        𝒮ᵗᵐ = track_source(a, links, 𝒜, ℒᵗʳᵃⁿˢ) 
        𝒮ˢ  = getsource(a, links)
        
        for s ∈ 𝒮
            if ~(s in 𝒮ᵗᵐ) # sources not directed to a
                @constraint(m, [t ∈ 𝒯], m[:prop_source][a, s, t] == 0)
            end
            if s ∈ 𝒮ˢ # sources inside area
                @constraint(m, [t ∈ 𝒯], m[:prop_source][a, s, t] == 1.0)
            end
        end
    end
end
function variables_tracking_prop(m, 𝒜, 𝒞, ℒᵗʳᵃⁿˢ, links, 𝒯)
    𝒜ⁿᵗ = filter(!is_terminalarea, 𝒜)
    𝒞ꜝ = filter(is_component_track,  𝒞)
    if !isempty(𝒞ꜝ)
        @variable(m, 0 <= prop_track[𝒞ꜝ, 𝒜ⁿᵗ, 𝒯] <= 1.0)
    end
end

function variables_pressure(m, 𝒜, ℒᵗʳᵃⁿˢ, links, 𝒯)
    𝒜ᵖ = filter(x -> is_pressurearea(x), 𝒜)
    
    if !isempty(𝒜ᵖ)
        TM = [tm for l ∈ ℒᵗʳᵃⁿˢ for tm ∈ EMG.modes(l)]

        @variable(m, p_in[TM, 𝒯] >= 0)
        @variable(m, p_out[TM, 𝒯] >= 0)
        @variable(m, has_flow[TM, 𝒯], Bin) # auxiliary binary that ensures that all transmissionmodes with flow take value 1, it can take value 1 without flow as well. Careful with this detail, it cannot be used to check actual flows.
        @variable(m, lower_pressure_into_node[TM, 𝒯], Bin) # binary for tracking lowest pressure going into a node
        
        constraints_flow(m, ℒᵗʳᵃⁿˢ, 𝒯)
    end
end

function constraints_pressure(m, 𝒜, 𝒞, ℒᵗʳᵃⁿˢ, links, 𝒯, 𝒫, pwa)
    𝒜ᵖ = filter(x -> is_pressurearea(x), 𝒜)

    for a ∈ 𝒜ᵖ
        pressure_balance(m, a, ℒᵗʳᵃⁿˢ, links, 𝒯, 𝒫)
        constraints_weymouth(m, a, pwa, 𝒫, 𝒞, ℒᵗʳᵃⁿˢ, links, 𝒯)
    end
end

function constraints_blending(m, 𝒜, 𝒞, ℒᵗʳᵃⁿˢ, links, 𝒯)
    𝒜ᵇ = filter(x -> is_blendarea(x), 𝒜)
    for a ∈ 𝒜ᵇ
        create_blending_node(m, a, 𝒜, 𝒞, ℒᵗʳᵃⁿˢ, links, 𝒯)
    end
end

