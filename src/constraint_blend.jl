
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
        throw(ArgumentError("Trying to create a TerminalArea with Blending behaviour without a BlendingSink node."))
    end
end


"""
    variables_node(m, 𝒩ˢⁱⁿᵏ::Vector{<:BlendingSink}, 𝒯, modeltype::EnergyModel)

Declaration of deficit (`:sink_deficit`) variables
for `BlendingSink` nodes `𝒩ˢⁱⁿᵏ` to quantify when there is too much or too little energy for
satisfying the demand.
"""
function EMB.variables_node(m, 𝒩ˢⁱⁿᵏ::Vector{<:BlendingSink}, 𝒯, modeltype::EnergyModel) #TODO: The variables are still generated, although not used.
    # @variable(m, sink_surplus[𝒩ˢⁱⁿᵏ, 𝒯] >= 0)
    # @variable(m, sink_deficit[𝒩ˢⁱⁿᵏ, 𝒯] >= 0)
end

"""
    constraints_capacity(m, n::BlendingSink, 𝒯::TimeStructure, modeltype::EnergyModel)

Function for creating the constraint on the maximum capacity of a generic `BlendingSink`.
This function serves as fallback option if no other function is specified for a `BlendingSink`.
"""
function EMB.constraints_capacity(m, n::BlendingSink, 𝒯::TimeStructure, modeltype::EnergyModel)
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
function EMB.constraints_opex_var(m, n::BlendingSink, 𝒯ᴵⁿᵛ, modeltype::EnergyModel)
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
function EMB.check_node(n::BlendingSink, 𝒯, modeltype::EnergyModel, check_timeprofiles::Bool)
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