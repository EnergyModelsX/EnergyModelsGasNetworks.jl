
function create_blending_node(m, a::TerminalArea, 𝒜, 𝒞, ℒᵗʳᵃⁿˢ, links, 𝒯)

    𝒮ᵗᵐ = track_source(a, links, 𝒜, ℒᵗʳᵃⁿˢ)
    𝒜ᵃ = setdiff(getadjareas(a, ℒᵗʳᵃⁿˢ), [a])
    ℒ = Dict(ad => EMG.modes(l) for ad ∈ 𝒜ᵃ for l ∈ [EMG.corr_from_to(ad.name, a.name, ℒᵗʳᵃⁿˢ)])
    ℒᶠ = [first(modes(l)) for l ∈ EMG.corr_from(a, ℒᵗʳᵃⁿˢ)] # ASSUMING ONLY ONE MODE PER TRANSMISSION.

    @constraint(m, [t ∈ 𝒯, s ∈ 𝒮ᵗᵐ],
        sum(m[:prop_source][ad, s, t] * m[:trans_out][tm, t] for ad ∈ 𝒜ᵃ for tm ∈ ℒ[ad])
        - m[:prop_source][a, s, t] * sum(m[:trans_out][tm, t] for ad ∈ 𝒜ᵃ for tm ∈ ℒ[ad]) == 0)

    @constraint(m, [t ∈ 𝒯],
        sum(m[:prop_source][a, s, t] for s ∈ 𝒮ᵗᵐ) == 1.0)

    constraints_quality(m, a, 𝒜, ℒᵗʳᵃⁿˢ, links, 𝒯)
    constraints_tracking(m, a, 𝒜, 𝒞, ℒᵗʳᵃⁿˢ, links, 𝒯)
    constraints_energy_content(m, a, 𝒞, ℒᵗʳᵃⁿˢ, 𝒯)
    
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

function constraints_tracking(m, a::Area, 𝒜, 𝒞, ℒᵗʳᵃⁿˢ, links, 𝒯)
    𝒞ꜝ = filter(r -> is_component_track(r), 𝒞)
    c = isempty(𝒞ꜝ) ? nothing : first(𝒞ꜝ)
    if isnothing(c)
        throw(ArgumentError("Trying to build a blending node without a component to track."))
    else
        𝒮ᵗᵐ = track_source(a, links, 𝒜, ℒᵗʳᵃⁿˢ)
        𝒮ˢ  = getsource(a, links)
        # filter sources of ResourceComponentTrack
        𝒮 = filter(s -> c ∈ components(s), union(𝒮ᵗᵐ, 𝒮ˢ))
        println("For area $(a.name) and component $(c.id), sources are $(𝒮)")

        @constraint(m, [t ∈ 𝒯],
            m[:prop_track][c, a, t] == sum(get_quality(s, c) * m[:prop_source][a, s, t] for s ∈ 𝒮))

        # add_blend_limit(m, a, 𝒞, ℒᵗʳᵃⁿˢ, links, 𝒯)
    end
end
# function add_blend_limit(m, a::PoolingArea, 𝒞, ℒᵗʳᵃⁿˢ, links, 𝒯)
#     p = first(filter(is_component_track, 𝒞))

#     @constraint(m, [t ∈ 𝒯],
#         m[:prop_track][p, a, t] <= upper_level(p)
#     )
# end
# function add_blend_limit(m, a::Area, 𝒞, ℒᵗʳᵃⁿˢ, links, 𝒯)
#     return nothing
# end
function constraints_quality(m, a::TerminalArea, 𝒜, ℒᵗʳᵃⁿˢ, links, 𝒯)
    blending_sink =[n for n in EMG.getnodesinarea(a, links) if EnergyModelsPooling.is_blending_sink(n)]   # get terminals, one terminal per terinalarea

    d = first(blending_sink)
    if !isempty(blending_sink)
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

function constraints_energy_content(m, a::TerminalArea, 𝒞, ℒᵗʳᵃⁿˢ, 𝒯)

    ℒᵗᵒ = EMG.corr_to(a, ℒᵗʳᵃⁿˢ)
    c = first(filter(is_component_track, 𝒞))
    d = first(setdiff(𝒞, [c]))
    
    if !isnothing(energy_delivery(a))
        for (idx, t) in enumerate(𝒯)
            @constraint(m,
                m[:energy_content][a, t] >= energy_delivery(a, idx))
            @constraint(m,
                m[:energy_content][a, t] == sum(m[:trans_out][tm_mode, t] * (m[:prop_track][c, tm.from, t] * energy_content(c) + (1-m[:prop_track][c, tm.from, t]) * energy_content(d)) for tm ∈ ℒᵗᵒ for tm_mode ∈ modes(tm)))
        end
    end
end

"""
    variables_node(m, 𝒩ˢⁱⁿᵏ::Vector{<:BlendingSink}, 𝒯, modeltype::EnergyModel)

Declaration of deficit (`:sink_deficit`) variables
for `BlendingSink` nodes `𝒩ˢⁱⁿᵏ` to quantify when there is too much or too little energy for
satisfying the demand.
"""
function EMB.variables_node(m, 𝒩ˢⁱⁿᵏ::Vector{<:BlendingSink}, 𝒯, modeltype::EnergyModel)
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
            m[:cap_use][n, t] * surplus_penalty(n, t) 
            ) * EMB.scale_op_sp(t_inv, t) for t ∈ t_inv
        )
    )
end