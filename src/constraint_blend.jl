"""
    constraints_proportion(m, n::EMB.Source, ℒ::Vector{<:EMB.Link}, 𝒯, 𝒫::Vector{ResourcePooling})
    constraints_proportion(m, n::EMB.Node, ℒ::Vector{<:EMB.Link}, 𝒯, 𝒫::Vector{ResourcePooling})

Keeps track of the proportions of flows from sources at each node `n`. 
`Source` nodes have their proportions fixed to 1 for their own resource and 0 for others.
"""
function constraints_proportion(m, n::EMB.Source, ℒ::Vector{<:EMB.Link}, 𝒯, 𝒫::Vector{ResourcePooling}) end
function constraints_proportion(m, n::EMB.Node, ℒ::Vector{<:EMB.Link}, 𝒯, 𝒫::Vector{ResourcePooling})
    for blend ∈ 𝒫
        # Get the subresources for the blend
        sub_res = subresources(blend)

        # Check if the constraints for that blend applies to `n`
        if any(res -> res ∈ EMB.inputs(n), sub_res) || blend ∈ EMB.inputs(n)

            # Get links into `n` which transport any sub_resource or blend
            ℒᵗᵒ = get_links_to_node_blend(n, ℒ, sub_res, blend)

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

            # The sum of all source proportions of resources forming the blend at node n must equal 1
            @constraint(m, [t ∈ 𝒯],
                sum(m[:proportion_source][n, s, t] for s ∈ 𝒮) == 1.0
            )
        end
    end
end

"""
    constraints_quality(m, n::EMB.Source, ℒ::Vector{<:EMB.Link}, 𝒯, 𝒫::Vector{<:ResourcePooling})
    constraints_quality(m, n::EMB.Node, ℒ::Vector{<:EMB.Link}, 𝒯, 𝒫::Vector{<:ResourcePooling})

Defines the maximum and minimum quality constraints for a node n based on the blending data.
`Source`nodes do not have quality constraints.
"""
function constraints_quality(m, n::EMB.Source, ℒ::Vector{<:EMB.Link}, 𝒯, 𝒫::Vector{<:ResourcePooling}) end
function constraints_quality(m, n::EMB.Node, ℒ::Vector{<:EMB.Link}, 𝒯, 𝒫::Vector{<:ResourcePooling})
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
                if 𝒫ᵐᵃˣ[p] != 1
                    @constraint(m, [t ∈ 𝒯],
                        sum(
                            (get_source_prop(s, p) - get_max_proportion(data, p)) *
                            m[:proportion_source][l.from, s, t] * m[:link_in][l, t, pp]
                            for l ∈ ℒᵗᵒ for pp ∈ EMB.link_res(l) for s ∈ 𝒮[l.from]
                        ) <= 0
                    )
                end
            end

            # Set constraints for minimum quality of resources
            for p ∈ keys(𝒫ᵐⁱⁿ)
                if 𝒫ᵐⁱⁿ[p] != 0
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
end

"""
    function constraints_proportion_source(m, 𝒩::Vector{<:EMB.Node}, ℒ::Vector{<:EMB.Link}, 𝒯, 𝒫::Vector{<:ResourcePooling})

Set standard proportion_source values for all nodes. 
For nodes of type `Source`, the proportion source from itself is set to 1 and from other sources to 0.
For other nodes, the proportion source from non-associated sources is set to 0. Non-associated sources are those that are not 
upstream of the node.
"""
function constraints_proportion_source(
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
function constraints_proportion_source(
    m,
    ℒ::Vector{<:EMB.Link},
    𝒩::Vector{<:EMB.Node},
    𝒯,
    𝒫::Vector{<:ResourcePooling},
)
    constraints_proportion_source(m, 𝒩, ℒ, 𝒯, 𝒫)
end

"""
    constraints_tracking(m, n::EMB.Source, ℒ::Vector{<:EMB.Link}, 𝒯, 𝒫::Vector{ResourcePooling})
    constraints_tracking(m, n::EMB.Node, ℒ::Vector{<:EMB.Link}, 𝒯, 𝒫::Vector{ResourcePooling})

Tracking the proportion of subresources at node `n`. Required for linking with the pressure constraints.
If n is a `Source`, the :proportion_track variables are fixed to 1 for its own resources and 0 for others.
For other node types, the :proportion_track variables are defined based on the :proportion_source variables of upstream sources.
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
