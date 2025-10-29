"""
    function constraints_proportion(m, n::Node, 𝒳ᵛᵉᶜ, 𝒯, 𝒫)

Ensures keeping track of the proportions of resources from sources at each node `n`. 

Note! It is assumed that all the ResourceComponentPotential and ResourceComponent that meet in a node are blended.
If 𝒫 is not a Vector{ResourcePooling}, no constraints are applied.
"""
# Fallback method for any type of 𝒫 that is not Vector{ResourcePooling}
function constraints_proportion(m, n::EMB.Node, 𝒳ᵛᵉᶜ, 𝒯, 𝒫) end
function constraints_proportion(m, n::EMB.Source, 𝒳ᵛᵉᶜ, 𝒯, 𝒫::Vector{ResourcePooling}) end
function constraints_proportion(m, n::EMB.Node, 𝒳ᵛᵉᶜ, 𝒯, 𝒫::Vector{ResourcePooling})
    for blend ∈ 𝒫
        # Get the subresources for the blend
        sub_res = subresources(blend)

        # Check if the constraints for that blend applies to `n`
        if any(res -> res ∈ EMB.inputs(n), sub_res) || blend ∈ EMB.inputs(n)

            # Get links into `n` which transport any sub_resource or blend
            ℒ = 𝒳ᵛᵉᶜ[2]
            ℒᵗᵒ = get_links_to_node_blend(n, 𝒳ᵛᵉᶜ, sub_res, blend)

            # Get sources associated to `n` whose outputs are any subresource
            𝒮 = sources_upstream_of(n, ℒ, sub_res)

            # The flow proportion of each source in `n` evolves as it moves through the network.
            @constraint(m, [t ∈ 𝒯, s ∈ 𝒮],
                sum(
                    m[:proportion_source][l.from, s, t] * sum(
                        m[:link_in][l, t, p] for
                        p ∈ EMB.link_res(l) if (p ∈ sub_res) || (p == blend)
                    ) for l ∈ ℒᵗᵒ
                )
                -
                m[:proportion_source][n, s, t] * sum(
                    m[:link_in][l, t, p] for l ∈ ℒᵗᵒ for
                    p ∈ EMB.link_res(l) if (p ∈ sub_res) || (p == blend)
                ) == 0
            )

            # @constraint(m, [t ∈ 𝒯, s ∈ 𝒮],
            #     sum(m[:proportion_source][n_adj, s, t] * m[:link_in][l, t, p] for p ∈ EMB.inputs(n) for l ∈ ℒᵗᵒ for n_adj ∈ [l.from] if (p ∈ EMB.link_res(l) && ((p ∈ sub_res) || (p == blend))))
            #     - m[:proportion_source][n, s, t] * sum(m[:link_in][l, t, p] for l ∈ ℒᵗᵒ for p ∈ EMB.link_res(l) if (p ∈ sub_res) || (p == blend)) == 0
            # )

            # @constraint(m, [t ∈ 𝒯, s ∈ 𝒮],
            #     sum(m[:proportion_source][n_adj, s, t] * sum(m[:link_in][l, t, p] for p ∈ EMB.link_res(l) if (p ∈ sub_res) || (p == blend)) for l ∈ ℒᵗᵒ for n_adj ∈ [l.from])
            #     - m[:proportion_source][n, s, t] * sum(m[:link_in][l, t, p] for l ∈ ℒᵗᵒ for p ∈ EMB.link_res(l) if (p ∈ sub_res) || (p == blend)) == 0
            # )

            # The sum of all source proportions of resources forming the blend at node n must equal 1
            @constraint(m, [t ∈ 𝒯],
                sum(m[:proportion_source][n, s, t] for s ∈ 𝒮) == 1.0
            )

            # @constraint(m, [t ∈ 𝒯, l ∈ ℒᵗᵒ],
            #     sum(m[:proportion_source][n, s, t] * m[:link_in][l, t, p] for s ∈ 𝒮 for p ∈ EMB.link_res(l) if p ∈ EMB.outputs(s)) == sum(m[:link_in][l, t, p] for p ∈ EMB.link_res(l) if p ∈ sub_res)
            # )
        end
    end
    # Redundant constraint
    # ℒᶠ = [first(modes(l)) for l ∈ EMG.corr_from(a, ℒᵗʳᵃⁿˢ)] # ASSUMING ONLY ONE MODE PER TRANSMISSION.
    # @constraint(m, [t ∈ 𝒯, tm ∈ ℒᶠ],
    #     sum(m[:prop_source][a, s, t] * m[:trans_in][tm, t] for s ∈ 𝒮ᵗᵐ) - m[:trans_in][tm, t] == 0)
end

"""
    function constraints_quality(m, n::Node, 𝒯, 𝒫)

Defines the maximum and minimum quality constraints for a node n based on the blending data.
"""
function constraints_quality(m, n::EMB.Node, 𝒳ᵛᵉᶜ, 𝒯, 𝒫) end
function constraints_quality(m, n::EMB.Node, 𝒳ᵛᵉᶜ, 𝒯, 𝒫::Vector{<:ResourcePooling})
    # Get blend data for node `n`
    blend_data = get_blenddata(n)

    for blend ∈ 𝒫
        # Get the subresources for the blend
        sub_res = subresources(blend)

        # Check if blend data is available for the current blend
        data_vect = get_blenddata(n, blend)

        if !isempty(data_vect)
            # Get the specific data for blend
            data = only(data_vect)

            # Get maximum and minimum resource proportions for node `n`
            𝒫ᵐᵃˣ, 𝒫ᵐⁱⁿ = res_blendata(data)
            𝒫ᵐᵃˣ = Dict(key => val for (key, val) ∈ 𝒫ᵐᵃˣ) 
            𝒫ᵐⁱⁿ = Dict(key => val for (key, val) ∈ 𝒫ᵐⁱⁿ)

            # Get links into `n` that deliver any sub_resource of blend
            ℒ = 𝒳ᵛᵉᶜ[2]
            _, ℒᵗᵒ = EMB.link_sub(ℒ, n)
            ℒᵗᵒ = filter(
                l ->
                    (blend ∈ EMB.link_res(l)) ||
                    any(res -> res ∈ EMB.link_res(l), sub_res),
                ℒᵗᵒ,
            )

            # Get associated sources to `n` whose outputs are sub_resources of blend
            𝒮 = Dict(
                l_to.from => filter(
                    s -> any(res -> res ∈ sub_res, EMB.outputs(s)),
                    sources_upstream_of(l_to.from, ℒ),
                ) for l_to ∈ ℒᵗᵒ
            )

            # Set constraints for maximum quality of resources
            for p ∈ keys(𝒫ᵐᵃˣ)
                @constraint(m, [t ∈ 𝒯],
                    sum(
                        (get_source_prop(s, p) - get_max_proportion(data, p)) *
                        m[:proportion_source][l.from, s, t] * m[:link_in][l, t, pp]
                        for l ∈ ℒᵗᵒ for pp ∈ EMB.link_res(l) for s ∈ 𝒮[l.from]
                    ) <= 0
                )
            end

            # Set constraints for minimum quality of resources
            for p ∈ keys(𝒫ᵐⁱⁿ)
                @constraint(m, [t ∈ 𝒯],
                    sum(
                        (get_source_prop(s, p) - get_min_proportion(data, p)) *
                        m[:proportion_source][l.from, s, t] * m[:link_in][l, t, pp]
                        for l ∈ ℒᵗᵒ for pp ∈ EMB.link_res(l) for s ∈ 𝒮[l.from]
                    ) >= 0
                )
            end
        end
    end
end
function constraints_quality(m, n::EMB.Source, 𝒳ᵛᵉᶜ, 𝒯, 𝒫::Vector{<:ResourcePooling}) end

"""
    function constraints_proportion_couple(m, 𝒩::Vector{<:EMB.Node}, ℒ::Vector{<:EMB.Link}, 𝒯, 𝒫::Vector{<:ResourcePooling})

Sets standard proportion_source values. 
The proportion source of a node n from a source is set to 1 if source == n.
The proportion source of a node n from a source not associated to it is set to 0.
"""
function constraints_proportion_couple(
    m,
    𝒩::Vector{<:EMB.Node},
    ℒ::Vector{<:EMB.Link},
    𝒯,
    𝒫::Vector{<:ResourcePooling},
)
    sub_res = [r for res_blend ∈ 𝒫 for r ∈ subresources(res_blend)]

    # Filter sources with resources for blends
    𝒮 = filter(n -> EMB.is_source(n) &&
                    all(res -> res ∈ sub_res, EMB.outputs(n)), 𝒩)

    # Set proportion_source to 0 at nodes where the source is not associated
    # and set proportion_source to 1 at source nodes.
    for n ∈ 𝒩
        𝒮ⁿ = sources_upstream_of(n, ℒ)
        for source ∈ 𝒮
            if source == n # if `source` is the same as `n`
                for t ∈ 𝒯
                    fix(m[:proportion_source][n, source, t], 1; force = true)
                end
            elseif ~(source in 𝒮ⁿ) # if `source` is not associated to `n`
                for t ∈ 𝒯
                    fix(m[:proportion_source][n, source, t], 0; force = true)
                end
            end
        end
    end
end
function constraints_proportion_couple(
    m,
    ℒ::Vector{<:EMB.Link},
    𝒩::Vector{<:EMB.Node},
    𝒯,
    𝒫::Vector{<:ResourcePooling},
)
    constraints_proportion_couple(m, 𝒩, ℒ, 𝒯, 𝒫)
end

"""
    function constraints_tracking(m, n::Node, ℒ::Vector{<:Link}, 𝒯, 𝒫)

These are constraints required for tracking the proportion of resources each node `n`. This is used for linking with the pressure constraints.
"""
function constraints_tracking(
    m,
    n::EMB.Node,
    ℒ::Vector{<:EMB.Link},
    𝒯,
    𝒫::Vector{ResourcePooling},
)
    for p_blend ∈ 𝒫
        𝒫ʳ = subresources(p_blend)
        𝒮 = sources_upstream_of(n, ℒ)

        for p ∈ 𝒫ʳ
            𝒮ᵖ = filter(s -> p ∈ outputs(s), 𝒮)
            @constraint(m, [t ∈ 𝒯],
                m[:proportion_track][n, t, p] ==
                sum(m[:proportion_source][n, s, t] for s ∈ 𝒮ᵖ)
            )
        end
    end
end
function constraints_tracking(
    m,
    n::EMB.Source,
    ℒ::Vector{<:EMB.Link},
    𝒯,
    𝒫::Vector{ResourcePooling},
)
    for p_blend ∈ 𝒫
        𝒫ʳ = subresources(p_blend)
        𝒫ⁿ = filter(p -> (p ∈ EMB.outputs(n)), 𝒫ʳ)

        # Set the proportion_track for Source `n` as 1 if it p is an output, and 0 otherwise
        for t ∈ 𝒯, p ∈ 𝒫ⁿ
            fix(m[:proportion_track][n, t, p], 1; force = true)
        end
        for t ∈ 𝒯, p ∈ setdiff(𝒫ʳ, 𝒫ⁿ)
            fix(m[:proportion_track][n, t, p], 0; force = true)
        end
    end
end

# function constraints_quality(m, a::TerminalArea, 𝒜, ℒᵗʳᵃⁿˢ, links, 𝒯)
#     blending_sink =[n for n in EMG.getnodesinarea(a, links) if EnergyModelsPooling.is_blending_sink(n)]   # get terminals, one terminal per terinalarea

#     d = first(blending_sink)
#     if !isempty(blending_sink)
#         av = availability_node(a)

#         ℒᵗᵒ = EMG.corr_to(a, ℒᵗʳᵃⁿˢ)
#         𝒜ᵃ = setdiff(getadjareas(a, ℒᵗᵒ), [a])
#         𝒮ᵃ = Dict(ad => track_source(ad, links, 𝒜, ℒᵗʳᵃⁿˢ) for ad ∈ 𝒜ᵃ)
#         TM = Dict(ad => modes(EMG.corr_from_to(ad.name, a.name, ℒᵗᵒ)) for ad ∈ 𝒜ᵃ)

#         𝒫ᵘ = res_upper(d)
#         @constraint(m, [t ∈ 𝒯, p ∈ 𝒫ᵘ],
#             sum((get_quality(s, p) - get_upper(d, p)) * m[:prop_source][ad, s, t] * m[:trans_out][tm, t] for ad ∈ 𝒜ᵃ for s ∈ 𝒮ᵃ[ad] for tm ∈ TM[ad]) <= 0)
#         𝒫ˡ = res_lower(d)
#         @constraint(m, [t ∈ 𝒯, p ∈ 𝒫ˡ],
#             sum((get_quality(s, p) - get_lower(d, p)) * m[:prop_source][ad, s, t] * m[:trans_out][tm, t] for ad ∈ 𝒜ᵃ for s ∈ 𝒮ᵃ[ad] for tm ∈ TM[ad]) >= 0)
#     else
#         throw(ArgumentError("Trying to create a TerminalArea with Blending behaviour without a BlendingSink node."))
#     end
# end

# function constraints_tracking(m, a::Area, 𝒜, 𝒞, ℒᵗʳᵃⁿˢ, links, 𝒯)
#     𝒞ꜝ = filter(r -> is_component_track(r), 𝒞)
#     c = isempty(𝒞ꜝ) ? nothing : first(𝒞ꜝ)
#     if isnothing(c)
#         throw(ArgumentError("Trying to build a blending node without a component to track."))
#     else
#         𝒮ᵗᵐ = track_source(a, links, 𝒜, ℒᵗʳᵃⁿˢ)
#         𝒮ˢ  = getsource(a, links)
#         # filter sources of ResourceComponentTrack
#         𝒮 = filter(s -> c ∈ components(s), union(𝒮ᵗᵐ, 𝒮ˢ))
#         println("For area $(a.name) and component $(c.id), sources are $(𝒮)")

#         @constraint(m, [t ∈ 𝒯],
#             m[:prop_track][c, a, t] == sum(get_quality(s, c) * m[:prop_source][a, s, t] for s ∈ 𝒮))

#         # add_blend_limit(m, a, 𝒞, ℒᵗʳᵃⁿˢ, links, 𝒯)
#     end
# end

# function create_blending_node(m, a::TerminalArea, 𝒜, 𝒞, ℒᵗʳᵃⁿˢ, links, 𝒯)

#     𝒮ᵗᵐ = track_source(a, links, 𝒜, ℒᵗʳᵃⁿˢ)
#     𝒜ᵃ = setdiff(getadjareas(a, ℒᵗʳᵃⁿˢ), [a])
#     ℒ = Dict(ad => EMG.modes(l) for ad ∈ 𝒜ᵃ for l ∈ [EMG.corr_from_to(ad.name, a.name, ℒᵗʳᵃⁿˢ)])
#     ℒᶠ = [first(modes(l)) for l ∈ EMG.corr_from(a, ℒᵗʳᵃⁿˢ)] # ASSUMING ONLY ONE MODE PER TRANSMISSION.

#     @constraint(m, [t ∈ 𝒯, s ∈ 𝒮ᵗᵐ],
#         sum(m[:prop_source][ad, s, t] * m[:trans_out][tm, t] for ad ∈ 𝒜ᵃ for tm ∈ ℒ[ad])
#         - m[:prop_source][a, s, t] * sum(m[:trans_out][tm, t] for ad ∈ 𝒜ᵃ for tm ∈ ℒ[ad]) == 0)

#     @constraint(m, [t ∈ 𝒯],
#         sum(m[:prop_source][a, s, t] for s ∈ 𝒮ᵗᵐ) == 1.0)

#     constraints_quality(m, a, 𝒜, ℒᵗʳᵃⁿˢ, links, 𝒯)
#     constraints_tracking(m, a, 𝒜, 𝒞, ℒᵗʳᵃⁿˢ, links, 𝒯)
#     constraints_energy_content(m, a, 𝒞, ℒᵗʳᵃⁿˢ, 𝒯)

# end
# function create_blending_node(m, a::PoolingArea, 𝒜, 𝒞, ℒᵗʳᵃⁿˢ, links, 𝒯)

#     𝒮ᵗᵐ = track_source(a, links, 𝒜, ℒᵗʳᵃⁿˢ)
#     𝒜ᵃ = setdiff(getadjareas(a, ℒᵗʳᵃⁿˢ), [a])
#     ℒ = Dict(ad => EMG.modes(l) for ad ∈ 𝒜ᵃ for l ∈ [EMG.corr_from_to(ad.name, a.name, ℒᵗʳᵃⁿˢ)])
#     ℒᶠ = [first(modes(l)) for l ∈ EMG.corr_from(a, ℒᵗʳᵃⁿˢ)] # ASSUMING ONLY ONE MODE PER TRANSMISSION.

#     @constraint(m, [t ∈ 𝒯, s ∈ 𝒮ᵗᵐ],
#         sum(m[:prop_source][ad, s, t] * m[:trans_out][tm, t] for ad ∈ 𝒜ᵃ for tm ∈ ℒ[ad])
#         - sum(m[:prop_source][a, s, t] * m[:trans_in][tm, t] for tm ∈ ℒᶠ) == 0)

#     @constraint(m, [t ∈ 𝒯],
#         sum(m[:prop_source][a, s, t] for s ∈ 𝒮ᵗᵐ) == 1.0)

#     @constraint(m, [t ∈ 𝒯, tm ∈ ℒᶠ],
#         sum(m[:prop_source][a, s, t] * m[:trans_in][tm, t] for s ∈ 𝒮ᵗᵐ) - m[:trans_in][tm, t] == 0)

#     constraints_tracking(m, a, 𝒜, 𝒞, ℒᵗʳᵃⁿˢ, links, 𝒯)
# end
# function create_blending_node(m, a::SourceArea, 𝒜, 𝒞, ℒᵗʳᵃⁿˢ, links, 𝒯)
#     constraints_tracking(m, a, 𝒜, 𝒞, ℒᵗʳᵃⁿˢ, links, 𝒯)
# end
# function create_blending_node(m, a::Area, 𝒜, 𝒞, ℒᵗʳᵃⁿˢ, links, 𝒯)
#     return nothing
# end

# function add_blend_limit(m, a::PoolingArea, 𝒞, ℒᵗʳᵃⁿˢ, links, 𝒯)
#     p = first(filter(is_component_track, 𝒞))

#     @constraint(m, [t ∈ 𝒯],
#         m[:prop_track][p, a, t] <= upper_level(p)
#     )
# end
# function add_blend_limit(m, a::Area, 𝒞, ℒᵗʳᵃⁿˢ, links, 𝒯)
#     return nothing
# end

# TODO: Include energy content constraints
# function constraints_energy_content(m, a::TerminalArea, 𝒞, ℒᵗʳᵃⁿˢ, 𝒯)

#     ℒᵗᵒ = EMG.corr_to(a, ℒᵗʳᵃⁿˢ)
#     c = first(filter(is_component_track, 𝒞))
#     d = first(setdiff(𝒞, [c]))

#     if !isnothing(energy_delivery(a))
#         for (idx, t) in enumerate(𝒯)
#             @constraint(m,
#                 m[:energy_content][a, t] >= energy_delivery(a, idx))
#             @constraint(m,
#                 m[:energy_content][a, t] == sum(m[:trans_out][tm_mode, t] * (m[:prop_track][c, tm.from, t] * energy_content(c) + (1-m[:prop_track][c, tm.from, t]) * energy_content(d)) for tm ∈ ℒᵗᵒ for tm_mode ∈ modes(tm)))
#         end
#     end
# end
