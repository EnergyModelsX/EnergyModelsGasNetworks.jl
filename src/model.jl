function create_model(case, modeltype::EnergyModel, m::JuMP.Model; check_timeprofiles::Bool=true)
    @debug "Construct model"

    # Call of the basic model through EMG
    m = EMG.create_model(case, modeltype, m; check_timeprofiles)

    # Data structure
    𝒜 = case[:areas]
    links = case[:links]
    ℒᵗʳᵃⁿˢ = case[:transmission]
    𝒫 = case[:products]
    𝒯 = case[:T]
    e = case[:e]
    
    # Declaration of variables for blend structs
    variables_proportion(m, 𝒜, ℒᵗʳᵃⁿˢ, links, 𝒯)

    # Construction of constraints for the problem
    constraints_blending(m, 𝒜, ℒᵗʳᵃⁿˢ, links, 𝒯)
    constraints_quality(m, 𝒜, ℒᵗʳᵃⁿˢ, links, 𝒯, 𝒫)
    
    return m

end
function create_model(case, modeltype::EnergyModel; check_timeprofiles::Bool=true)
    m = JuMP.Model()
    create_model(case, modeltype, m; check_timeprofiles)
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
            if ~(s in 𝒮ᵗᵐ)
                @constraint(m, [t ∈ 𝒯], m[:prop_source][a, s, t] == 0)
            end
            if s ∈ 𝒮ˢ
                @constraint(m, [t ∈ 𝒯], m[:prop_source][a, s, t] == 1.0)
            end
        end
    end
end

function constraints_blending(m, 𝒜, ℒᵗʳᵃⁿˢ, links, 𝒯)
    # Filter only Blending areas
    𝒜ᵇ = filter(a -> is_blendarea(a), 𝒜)

    for a ∈ 𝒜ᵇ
        𝒮ᵗᵐ = track_source(a, links, 𝒜, ℒᵗʳᵃⁿˢ)
        𝒜ᵃ = setdiff(getadjareas(a, ℒᵗʳᵃⁿˢ), [a])
        ℒ = Dict(ad => EMG.modes(l) for ad ∈ 𝒜ᵃ for l ∈ [EMG.corr_from_to(ad.name, a.name, ℒᵗʳᵃⁿˢ)])
        ℒᶠ = [first(modes(l)) for l ∈ EMG.corr_from(a, ℒᵗʳᵃⁿˢ)] # ASSUMING ONLY ONE MODE PER TRANSMISSION.

        @constraint(m, [t ∈ 𝒯, s ∈ 𝒮ᵗᵐ],
            sum(m[:prop_source][ad, s, t] * m[:trans_out][tm, t] for ad ∈ 𝒜ᵃ for tm ∈ ℒ[ad])
            - sum(m[:prop_source][a, s, t] * m[:trans_in][tm, t] for tm ∈ ℒᶠ) == 0)

        @constraint(m, [t ∈ 𝒯],
            sum(m[:prop_source][a, s, t] for s ∈ 𝒮ᵗᵐ) == 1.0)

        # @constraint(m, [t ∈ 𝒯, tm ∈ ℒᶠ],
        #     sum(m[:prop_source][a, s, t] * m[:trans_in][tm, t] for s ∈ 𝒮ᵗᵐ) - m[:trans_in][tm, t] == 0)
    end    
end

function constraints_quality(m, 𝒜, ℒᵗʳᵃⁿˢ, links, 𝒯, 𝒫)
    𝒜ᵗ = filter(a -> is_terminalarea(a), 𝒜)

    for a ∈ 𝒜ᵗ
        d = first([n for n in EMG.getnodesinarea(a, links) if EnergyModelsPooling.is_blending_sink(n)])   # get terminals, one terminal per terinalarea

        av = availability_node(a)
        𝒫ᵃ = res_quality(d)
        ℒᵗᵒ = EMG.corr_to(a, ℒᵗʳᵃⁿˢ)
        𝒜ᵃ = setdiff(getadjareas(a, ℒᵗᵒ), [a])
        𝒮ᵃ = Dict(ad => track_source(ad, links, 𝒜, ℒᵗʳᵃⁿˢ) for ad ∈ 𝒜ᵃ)
        TM = Dict(ad => modes(EMG.corr_from_to(ad.name, a.name, ℒᵗᵒ)) for ad ∈ 𝒜ᵃ)
        
        for p ∈ 𝒫ᵃ
            @constraint(m, [t ∈ 𝒯],
             sum((get_quality(s, p) - get_quality(d, p)) * m[:prop_source][ad, s, t] * m[:trans_out][tm, t] for ad ∈ 𝒜ᵃ for s ∈ 𝒮ᵃ[ad] for tm ∈ TM[ad]) <= 0)
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