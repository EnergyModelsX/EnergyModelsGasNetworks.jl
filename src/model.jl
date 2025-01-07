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
    𝒜ᵇ = filter(x -> is_blendarea(x), 𝒜)
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
    𝒜ⁿᵗ = filter(a -> !is_terminalarea(a), 𝒜)
    𝒞ꜝ = filter(r -> is_component_track(r),  𝒞)
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
        @variable(m, has_flow[TM, 𝒯], Bin)
        @variable(m, lower_pressure_into_node[TM, 𝒯], Bin) # binary for tracking lowest pressure going into a node
        
        constraints_flow(m, ℒᵗʳᵃⁿˢ, 𝒯)
    end
end
function constraints_flow(m, ℒᵗʳᵃⁿˢ, 𝒯)
    TM = [tm for l ∈ ℒᵗʳᵃⁿˢ for tm ∈ EMG.modes(l) if is_pressurepipe(tm)]

    @constraint(
        m, [tm ∈ TM, t ∈ 𝒯],
        m[:trans_in][tm, t] <= EMG.capacity(tm, t) * m[:has_flow][tm, t]
    )
end

### CONSTRAINTS PRESSURE
function constraints_pressure(m, 𝒜, 𝒞, ℒᵗʳᵃⁿˢ, links, 𝒯, 𝒫, pwa)
    𝒜ᵖ = filter(x -> is_pressurearea(x), 𝒜)

    for a ∈ 𝒜ᵖ
        pressure_balance(m, a, ℒᵗʳᵃⁿˢ, links, 𝒯, 𝒫)
        constraints_weymouth(m, a, pwa, 𝒫, 𝒞, ℒᵗʳᵃⁿˢ, links, 𝒯)
    end
end
function pressure_balance(m, a::Area, ℒᵗʳᵃⁿˢ, links, 𝒯, 𝒫)
    return nothing
end
function pressure_balance(m, a::SourceArea, ℒᵗʳᵃⁿˢ, links, 𝒯, 𝒫)
    ℒᵒᵘᵗ = EMG.corr_from(a, ℒᵗʳᵃⁿˢ)
    
    for l ∈ ℒᵒᵘᵗ, tm ∈ EMG.modes(l)
        @constraint(m, [t ∈ 𝒯], 
        m[:p_in][tm, t] <= pressure(a) * m[:has_flow][tm, t])
    end
end
function pressure_balance(m, a::PoolingArea, ℒᵗʳᵃⁿˢ, links, 𝒯, 𝒫)
    ℒⁱⁿ = EMG.corr_to(a, ℒᵗʳᵃⁿˢ)
    ℒᵒᵘᵗ = EMG.corr_from(a, ℒᵗʳᵃⁿˢ)

    TM_in = [tm for l_in ∈ ℒⁱⁿ for tm in EMG.modes(l_in) ]
    TM_out = [tm for l_out ∈ ℒᵒᵘᵗ for tm in EMG.modes(l_out)]

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
function pressure_balance(m, a::TerminalArea, ℒᵗʳᵃⁿˢ, links, 𝒯, 𝒫)
    ℒⁱⁿ = EMG.corr_to(a, ℒᵗʳᵃⁿˢ)
    TM_in = [tm for l_in ∈ ℒⁱⁿ for tm in EMG.modes(l_in)]

    for tm_in ∈ TM_in
        @constraint(m, [t ∈ 𝒯],
            m[:p_out][tm_in, t] >= pressure(a) * m[:has_flow][tm_in, t])
    end
end

"""
    constraints_weymouth(m, a::Union{SourceArea, PoolingArea}, pwa::PWAFunc{C1, D1}, 𝒫, 𝒞, ℒᵗʳᵃⁿˢ, links, 𝒯)

    When pwa::PWAFunc, the problem must contain two components (1 resource) as the pwa is used for approximating the Weymouth with 2 resources.
    When pwa::Any, the problem is for one resources and the Weymouth will be approximated using the Taylor first-order approximation.
"""
function constraints_weymouth(m, a::Union{SourceArea, PoolingArea}, pwa::PWAFunc{C1, D1}, 𝒫, 𝒞, ℒᵗʳᵃⁿˢ, links, 𝒯) where {C1, D1} 
    
    if length(𝒞) == 2 #TODO: Examine the possibility of just using Resources rather than components
        p = first(filter(p -> is_component_track(r), 𝒞))
        if isnothing(p)
            throw(ArgumentError("One of the Components must be of type ComponentTrack."))
        end

        for (k, plane) ∈ enumerate(pwa.planes)
            for t ∈ 𝒯
                add_weymouth(m, a, p, ℒᵗʳᵃⁿˢ, t, plane)
            end
        end
    else
        throw(ArgumentError("Pressure capabilities not supported for more than 2 Components."))
    end
end
function constraints_weymouth(m, a::Union{SourceArea, PoolingArea}, pwa::Any, 𝒫, 𝒞, ℒᵗʳᵃⁿˢ, links, 𝒯)
    𝒫ꜝ = filter(p -> !EMB.is_resource_emit(p), 𝒫)
    
    if length(𝒫ꜝ) > 1
        throw(ArgumentError("Pressure constraints only available for 1 Resource and 1 Resource + 2 Components"))
    elseif length(𝒞) != 0
        throw(ArgumentError("For systems with Components, ensure you add the pwa (plane approximations)."))
    else
        p = first(𝒫ꜝ)

        for t ∈ 𝒯
            add_weymouth(m, a, p, ℒᵗʳᵃⁿˢ, t)
        end
    end
end
function constraints_weymouth(m, a::TerminalArea, pwa::Any, 𝒫, 𝒞, ℒᵗʳᵃⁿˢ, links, 𝒯)
    return nothing
end
function add_weymouth(m, a::Union{PoolingArea, SourceArea}, p::ComponentTrack, ℒᵗʳᵃⁿˢ, t, plane)
    ℒᵒᵘᵗ = EMG.corr_from(a, ℒᵗʳᵃⁿˢ)

    for l ∈ ℒᵒᵘᵗ, tm ∈ EMG.modes(l)
        PiecewiseAffineApprox.constr(C1, m, m[:trans_in][tm, t], plane, (m[:p_in][tm, t], m[:p_out][tm, t], m[:prop_track][p, a, t]))
    end 
end
function add_weymouth(m, a::Union{PoolingArea, SourceArea}, p::Resource, ℒᵗʳᵃⁿˢ, t)
    ℒᵒᵘᵗ = EMG.corr_from(a, ℒᵗʳᵃⁿˢ)

    for l ∈ ℒᵒᵘᵗ, tm ∈ EMG.modes(l)
        K_W = weymouth_ct(tm)
        P = linearised_pressures(tm)
        for (PIn, POut) ∈ P
            @constraint(m, 
            m[:trans_in][tm, t] <= K_W * (
                                            (PIn/(sqrt(PIn^2 - POut^2))) * m[:p_in][tm, t] -
                                            (POut/(sqrt(PIn^2 - POut^2))) * m[:p_out][tm, t]
                                          ))
        end
    end
end   
function PiecewiseAffineApprox.constr(::Type{Concave}, m, z, p, x)
    @constraint(m, z <= dot(-1 .* p.α, x) - p.β)
end

### CONSTRAINTS BLENDING
function constraints_blending(m, 𝒜, 𝒞, ℒᵗʳᵃⁿˢ, links, 𝒯)
    𝒜ᵇ = filter(x -> is_blendarea(x), 𝒜)
    for a ∈ 𝒜ᵇ
        create_blending_node(m, a, 𝒜, 𝒞, ℒᵗʳᵃⁿˢ, links, 𝒯)
    end
end

function create_blending_node(m, a::TerminalArea, 𝒜, 𝒞, ℒᵗʳᵃⁿˢ, links, 𝒯)
    constraints_quality(m, a, 𝒜, ℒᵗʳᵃⁿˢ, links, 𝒯)
end
function create_blending_node(m, a::PoolingArea, 𝒜, 𝒞, ℒᵗʳᵃⁿˢ, links, 𝒯)

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
    
    constraints_tracking(m, a, 𝒜, 𝒞, ℒᵗʳᵃⁿˢ, links, 𝒯)
end
function create_blending_node(m, a::SourceArea, 𝒜, 𝒞, ℒᵗʳᵃⁿˢ, links, 𝒯)
    constraints_tracking(m, a, 𝒜, 𝒞, ℒᵗʳᵃⁿˢ, links, 𝒯)
end
function create_blending_node(m, a::Area, 𝒜, 𝒞, ℒᵗʳᵃⁿˢ, links, 𝒯)
    return nothing
end

function constraints_tracking(m, a::Union{SourceArea, PoolingArea}, 𝒜, 𝒞, ℒᵗʳᵃⁿˢ, links, 𝒯)
    𝒞ꜝ = filter(r -> is_component_track(r), 𝒞)
    c = isempty(𝒞ꜝ) ? nothing : first(𝒞ꜝ)
    if isnothing(c)
        throw(ArgumentError("Trying to build a blending node without a component to track."))
    else
        𝒮ᵗᵐ = track_source(a, links, 𝒜, ℒᵗʳᵃⁿˢ)
        𝒮ˢ  = getsource(a, links)
        # filter sources of ResourceComponentTrack
        𝒮 = filter(s -> c ∈ components(s), union(𝒮ᵗᵐ, 𝒮ˢ))

        @constraint(m, [t ∈ 𝒯],
            m[:prop_track][c, a, t] == sum(get_quality(s, c) * m[:prop_source][a, s, t] for s ∈ 𝒮))
    end
end
function constraints_quality(m, a::TerminalArea, 𝒜, ℒᵗʳᵃⁿˢ, links, 𝒯)
    blending_sink =[n for n in EMG.getnodesinarea(a, links) if EnergyModelsPooling.is_blending_sink(n)]   # get terminals, one terminal per terinalarea

    if !isempty(blending_sink)
        d = first(blending_sink)
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
    else
        throw(ArgumentError("Trying to create a TerminalArea with Blending behaviour without a RefBlendingSink node."))
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
            ) * EMB.scale_op_sp(t_inv, t) for t ∈ t_inv
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
