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
    variables_pressure(m, 𝒜, ℒᵗʳᵃⁿˢ, links, 𝒯)

    # Construction of constraints for the problem
    constraints_blending(m, 𝒜, ℒᵗʳᵃⁿˢ, links, 𝒯)
    constraints_quality(m, 𝒜, ℒᵗʳᵃⁿˢ, links, 𝒯, 𝒫)
    constraints_pressure(m, 𝒜, ℒᵗʳᵃⁿˢ, links, 𝒯, 𝒫)
    
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
            if ~(s in 𝒮ᵗᵐ) # sources not directed to a
                @constraint(m, [t ∈ 𝒯], m[:prop_source][a, s, t] == 0)
            end
            if s ∈ 𝒮ˢ # sources inside area
                @constraint(m, [t ∈ 𝒯], m[:prop_source][a, s, t] == 1.0)
            end
        end
    end
end

function variables_pressure(m, 𝒜, ℒᵗʳᵃⁿˢ, links, 𝒯)
    for l ∈ ℒᵗʳᵃⁿˢ
        ℒ = EMG.modes(l)
        @variable(m, p_in[ℒ, 𝒯] >= 0)
        @variable(m, p_out[ℒ, 𝒯] >= 0)
        @variable(m, has_flow[ℒ, 𝒯], Bin)
        @variable(m, lower_pressure_into_node[ℒ, 𝒯], Bin) # binary for tracking lowest pressure going into a node
    end
end

function constraints_pressure(m, 𝒜, ℒᵗʳᵃⁿˢ, links, 𝒯, 𝒫)
    for a ∈ 𝒜
        pressure_balance(m, a, ℒᵗʳᵃⁿˢ, links, 𝒯, 𝒫)
    end
end

function pressure_balance(m, a::SourcePressure, ℒᵗʳᵃⁿˢ, links, 𝒯, 𝒫)
    ℒᵒᵘᵗ = EMG.corr_from(a, ℒᵗʳᵃⁿˢ)
    
    for l ∈ ℒᵒᵘᵗ, tm ∈ EMG.modes(l)
        @constraint(m, [t ∈ 𝒯], 
        m[:p_in][tm, t] <= out_pressure(l) * m[:has_flow][tm, t])
    end

end

function pressure_balance(m, a::BlendPressureArea, ℒᵗʳᵃⁿˢ, links, 𝒯, 𝒫)
    ℒⁱⁿ = EMG.corr_to(a, ℒᵗʳᵃⁿˢ)
    ℒᵒᵘᵗ = EMG.corr_from(a, ℒᵗʳᵃⁿˢ)

    TM_in = [tm for tm in EMG.modes(l_in) for l_in ∈ ℒⁱⁿ]
    TM_out = [tm for tm in EMG.modes(l_out) for l_out ∈ ℒᵒᵘᵗ]

    if length(TM_in) > 1
        @constraint(m, [t ∈ 𝒯],
                sum(m[:lower_pressure_into_node][tm_in, t] for tm_in ∈ TM_in) == 1)

        for tm_in ∈ TM_in, tm_out ∈ TM_out
            max_in = max_pressure(tm_in)

            @constraint(m, [t ∈ 𝒯],
                m[:p_in][tm_out, t] >= m[:p_out][tm_in, t] - max_in * (1 - m[:lower_pressure_into_node][tm_in, t]))
            
            @constraint(m, [t ∈ 𝒯],
                m[:lower_pressure_into_node][tm_in, t] <= m[:has_flow][tm_in, t])
            
            @constraint(m, [t ∈ 𝒯],
                m[:p_in][tm_out, t] <= m[:p_out][tm_in, t] + max_pressure(tm_out) * (1 - m[:has_flow][tm_in, t]))
        end 
    else
        tm_in = first(TM_in)

        for tm_out ∈ TM_out
            @constraint(m, [t ∈ 𝒯],
                m[:p_in][tm_out, t] >= m[:p_out][tm_in, t] - max_pressure(tm_in) * (1 - m[:has_flow][tm_in, t]))
            @constraint(m, [t ∈ 𝒯],
                m[:p_in][tm_out, t] <= m[:p_out][tm_in, t])
        end
    end
end

function pressure_balance(m, a::BlendPressureSink, ℒᵗʳᵃⁿˢ, links, 𝒯, 𝒫)

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

        @constraint(m, [t ∈ 𝒯, tm ∈ ℒᶠ],
            sum(m[:prop_source][a, s, t] * m[:trans_in][tm, t] for s ∈ 𝒮ᵗᵐ) - m[:trans_in][tm, t] == 0)
    end    
end

function constraints_quality(m, 𝒜, ℒᵗʳᵃⁿˢ, links, 𝒯, 𝒫)
    𝒜ᵗ = filter(a -> is_terminalarea(a), 𝒜)

    for a ∈ 𝒜ᵗ
        d = first([n for n in EMG.getnodesinarea(a, links) if EnergyModelsPooling.is_blending_sink(n)])   # get terminals, one terminal per terinalarea

        av = availability_node(a)
        
        ℒᵗᵒ = EMG.corr_to(a, ℒᵗʳᵃⁿˢ)
        𝒜ᵃ = setdiff(getadjareas(a, ℒᵗᵒ), [a])
        𝒮ᵃ = Dict(ad => track_source(ad, links, 𝒜, ℒᵗʳᵃⁿˢ) for ad ∈ 𝒜ᵃ)
        TM = Dict(ad => modes(EMG.corr_from_to(ad.name, a.name, ℒᵗᵒ)) for ad ∈ 𝒜ᵃ)
        
        𝒫ᵘ = res_upper(d)
        @constraint(m, [t ∈ 𝒯, p ∈ 𝒫ᵘ],
             sum((get_quality(s, p) - get_upper(d, p)) * m[:prop_source][ad, s, t] * m[:trans_out][tm, t] for ad ∈ 𝒜ᵃ for s ∈ 𝒮ᵃ[ad] for tm ∈ TM[ad]) <= 0)
        𝒫ˡ = res_lower(d)
        @constraint(m, [t ∈ 𝒯, p ∈ 𝒫ˡ],
             sum((get_quality(s, p) - get_lower(d, p)) * m[:prop_source][ad, s, t] * m[:trans_out][tm, t] for ad ∈ 𝒜ᵃ for s ∈ 𝒮ᵃ[ad] for tm ∈ TM[ad]) >= 0)
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

"""
    variables_node(m, 𝒩ˢⁱⁿᵏ::Vector{<:RefBlendingSink}, 𝒯, modeltype::EnergyModel)

Declaration of deficit (`:sink_deficit`) variables
for `RefBlendingSink` nodes `𝒩ˢⁱⁿᵏ` to quantify when there is too much or too little energy for
satisfying the demand.
"""
function EMB.variables_node(m, 𝒩ˢⁱⁿᵏ::Vector{<:RefBlendingSink}, 𝒯, modeltype::EnergyModel) #TODO: The variables are still generated, although not used.
    # @variable(m, sink_surplus[𝒩ˢⁱⁿᵏ, 𝒯] >= 0)
    # @variable(m, sink_deficit[𝒩ˢⁱⁿᵏ, 𝒯] >= 0)
end

"""
    constraints_capacity(m, n::RefBlendingSink, 𝒯::TimeStructure, modeltype::EnergyModel)

Function for creating the constraint on the maximum capacity of a generic `RefBlendingSink`.
This function serves as fallback option if no other function is specified for a `RefBlendingSink`.
"""
function EMB.constraints_capacity(m, n::RefBlendingSink, 𝒯::TimeStructure, modeltype::EnergyModel)
    @constraint(m, [t ∈ 𝒯],
        m[:cap_use][n, t] >= m[:cap_inst][n, t]
    )

    constraints_capacity_installed(m, n, 𝒯, modeltype)
end

"""
    constraints_opex_var(m, n::Sink, 𝒯ᴵⁿᵛ, modeltype::EnergyModel)

Function for creating the constraint on the variable OPEX of a generic `Sink`.
This function serves as fallback option if no other function is specified for a `Sink`.
"""
function EMB.constraints_opex_var(m, n::RefBlendingSink, 𝒯ᴵⁿᵛ, modeltype::EnergyModel)
    @constraint(m, [t_inv ∈ 𝒯ᴵⁿᵛ],
        m[:opex_var][n, t_inv] ==
        sum(
            (
            m[:cap_use][n, t] * price_penalty(n, t) 
            ) * multiple(t_inv, t) for t ∈ t_inv
        )
    )
end

"""
    check_node(n::Sink, 𝒯, modeltype::EnergyModel)

This method checks that a `Sink` node is valid.

These checks are always performed, if the user is not creating a new method. Hence, it is
important that a new `Sink` type includes at least the same fields as in the `RefSink` node
or that a new `Source` type receives a new method for `check_node`.

## Checks
 - The field `cap` is required to be non-negative.
 - The values of the dictionary `input` are required to be non-negative.
 - The dictionary `penalty` is required to have the keys `:deficit` and `:surplus`.
 - The sum of the values `:deficit` and `:surplus` in the dictionary `penalty` has to be
   non-negative to avoid an infeasible model.
"""
function EMB.check_node(n::RefBlendingSink, 𝒯, modeltype::EnergyModel, check_timeprofiles::Bool)
    @assert_or_log(
        sum(capacity(n, t) ≥ 0 for t ∈ 𝒯) == length(𝒯),
        "The capacity must be non-negative."
    )
    @assert_or_log(
        sum(inputs(n, p) ≥ 0 for p ∈ inputs(n)) == length(inputs(n)),
        "The values for the Dictionary `input` must be non-negative."
    )
    @assert_or_log(
        :price ∈ keys(n.penalty),
        "The entry :price is required in the field `penalty`"
    )

    # if :surplus ∈ keys(n.penalty) && :deficit ∈ keys(n.penalty)
    #     # The if-condition was checked above.
    #     @assert_or_log(
    #         sum(surplus_penalty(n, t) + deficit_penalty(n, t) ≥ 0 for t ∈ 𝒯) == length(𝒯),
    #         "An inconsistent combination of `:surplus` and `:deficit` leads to an infeasible model."
    #     )
    # end
end

"""
    create_area(m, a::LimitedExchangeArea, 𝒯, ℒᵗʳᵃⁿˢ, modeltype)

Constraint that limit input to a based on the specified exchange_limit.
"""
function EMG.create_area(m, a::BlendArea, 𝒯, ℒᵗʳᵃⁿˢ, modeltype)

    ## TODO: Consider adding additional types for import or export exchange limits
    # @constraint(m, [t ∈ 𝒯, p ∈ elimit_resources(a)],
    #     m[:area_exchange][a, t, p] <= exchange_limit(a, p, t)) # Import limit
    # ℒᶠʳᵒᵐ, ℒᵗᵒ = EMG.trans_sub(ℒᵗʳᵃⁿˢ, a)
    # @constraint(m, [t ∈ 𝒯, p ∈ limit_resources(a)],
    #     sum(EMG.compute_trans_out(m, t, p, tm) for tm ∈ modes(ℒᵗᵒ)) <= exchange_limit(a, p, t)) # Export limit

end

