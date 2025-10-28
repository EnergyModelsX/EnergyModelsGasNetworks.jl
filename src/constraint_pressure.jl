"""
    constraint_pressure(m, n::Source, 𝒯, 𝒫::Vector{<:CompoundResource})
    constraint_pressure(m, n::Availability, 𝒯, 𝒫::Vector{<:CompoundResource})
    constraint_pressure(m, n::Sink, 𝒯, 𝒫::Vector{<:CompoundResource})
    constraints_pressure(m, l::EMB.Link, 𝒯, 𝒫::Vector{<:CompoundResource})

Set internal balance pressures between `potential_in` and `potential_out` in Nodes `n` and Links `l``.
Source nodes have always inlet potential 0, Sink nodes have always outlet potential 0, Availability nodes have equal inlet and outlet potential.
"""
function constraints_pressure(m, n::EMB.Availability, 𝒯, 𝒫::Vector{<:CompoundResource})
    # Filter resources CompoundResource that are output of `n`
    𝒫ⁿ = filter(p -> p ∈ EMB.outputs(n), 𝒫)

    # Inlet and Outlet Potential should be equal
    @constraint(m, [t ∈ 𝒯, p ∈ 𝒫ⁿ], m[:potential_in][n, t, p] == m[:potential_out][n, t, p])
end
function constraints_pressure(m, n::SimpleCompressor, 𝒯, 𝒫::Vector{<:CompoundResource})
    # Filter resources CompoundResource that are output of `n`
    𝒫ⁿ = filter(p -> p ∈ EMB.inputs(n), 𝒫)

    # Inlet Potential lower than Outlet Potential
    @constraint(m, [t ∈ 𝒯, p ∈ 𝒫ⁿ], m[:potential_in][n, t, p] <= m[:potential_out][n, t, p])
end
function constraints_pressure(m, n::PoolingNode, 𝒯, 𝒫::Vector{<:CompoundResource})
    # Filter input and output resources
    𝒫ⁱⁿ = filter(p -> p ∈ EMB.inputs(n), 𝒫)
    𝒫ᵒᵘᵗ = filter(p -> p ∈ EMB.outputs(n), 𝒫)

    # Inlet Potential for each input resource should equal the outlet potential of the output (no drop or increase in potential)
    @constraint(m, [t ∈ 𝒯, p_in ∈ 𝒫ⁱⁿ, p_out ∈ 𝒫ᵒᵘᵗ],
        m[:potential_in][n, t, p_in] == m[:potential_out][n, t, p_out])
end
function constraints_pressure(m, l::EMB.Link, 𝒯, 𝒫::Vector{<:CompoundResource})
    # Filter resources CompoundResource that are output of `l`
    𝒫ⁿ = filter(p -> p ∈ EMB.outputs(l), 𝒫)

    # Inlet Potential should be always higher or equal to Outlet Potential (direction)
    @constraint(
        m,
        [t ∈ 𝒯, p ∈ 𝒫ⁿ],
        m[:link_potential_in][l, t, p] >= m[:link_potential_out][l, t, p]
    )

    @constraint(m, [t ∈ 𝒯, p ∈ 𝒫ⁿ],
        m[:link_potential_in][l, t, p] <= 1e4 * m[:has_flow][l, t])
    @constraint(m, [t ∈ 𝒯, p ∈ 𝒫ⁿ],
        m[:link_potential_out][l, t, p] <= 1e4 * m[:has_flow][l, t])
end
function constraints_pressure(m, n::EMB.AbstractElement, 𝒯, 𝒫::Vector{}) end

"""
    constraints_pressure_limit(m, n::Node, data::T, 𝒯, 𝒫::Vector{<:CompoundResource}) where {T<:PressureData}
    constraints_pressure_limit(m, n::Sink, data::T, 𝒯, 𝒫::Vector{<:CompoundResource}) where {T<:PressureData}

Set the pressure limits according to the PressureData `data` assigned to Node `n`.
"""
function constraints_pressure_limit(
    m,
    n::EMB.Node,
    data::MaxPressureData,
    𝒯,
    𝒫::Vector{<:CompoundResource},
)
    # Filter resources CompoundResource that are output of `n`
    𝒫ⁿ = filter(p -> p ∈ outputs(n), 𝒫)

    @constraint(m, [t ∈ 𝒯, p ∈ 𝒫ⁿ],
        m[:potential_out][n, t, p] <= pressure(data, t))
end
function constraints_pressure_limit(
    m,
    n::EMB.Node,
    data::MinPressureData,
    𝒯,
    𝒫::Vector{<:CompoundResource},
)
    # Filter resources CompoundResource that are output of `n`
    𝒫ⁿ = filter(p -> p ∈ outputs(n), 𝒫)

    @constraint(m, [t ∈ 𝒯, p ∈ 𝒫ⁿ],
        m[:potential_out][n, t, p] >= pressure(data, t))
end
function constraints_pressure_limit(
    m,
    n::EMB.Node,
    data::FixPressureData,
    𝒯,
    𝒫::Vector{<:CompoundResource},
)
    # Filter resources CompoundResource that are output of `n`
    𝒫ⁿ = filter(p -> p ∈ outputs(n), 𝒫)

    @constraint(m, [t ∈ 𝒯, p ∈ 𝒫ⁿ],
        m[:potential_out][n, t, p] == pressure(data, t))
end
function constraints_pressure_limit(
    m,
    n::EMB.Sink,
    data::MaxPressureData,
    𝒯,
    𝒫::Vector{<:CompoundResource},
)
    # Filter resources CompoundResource that are inputs of `n`
    𝒫ⁿ = filter(p -> p ∈ inputs(n), 𝒫)

    @constraint(m, [t ∈ 𝒯, p ∈ 𝒫ⁿ],
        m[:potential_in][n, t, p] <= pressure(data, t))
end
function constraints_pressure_limit(
    m,
    n::EMB.Sink,
    data::MinPressureData,
    𝒯,
    𝒫::Vector{<:CompoundResource},
)
    # Filter resources CompoundResource that are inputs of `n`
    𝒫ⁿ = filter(p -> p ∈ inputs(n), 𝒫)

    @constraint(m, [t ∈ 𝒯, p ∈ 𝒫ⁿ],
        m[:potential_in][n, t, p] >= pressure(data, t))
end
function constraints_pressure_limit(
    m,
    n::EMB.Sink,
    data::FixPressureData,
    𝒯,
    𝒫::Vector{<:CompoundResource},
)
    # Filter resources CompoundResource that are inputs of `n`
    𝒫ⁿ = filter(p -> p ∈ inputs(n), 𝒫)

    @constraint(m, [t ∈ 𝒯, p ∈ 𝒫ⁿ],
        m[:potential_in][n, t, p] == pressure(data, t))
end
function constraints_pressure_limit(
    m,
    l::EMB.Link,
    data::MaxPressureData,
    𝒯,
    𝒫::Vector{<:CompoundResource},
)
    # Filter resources CompoundResource that are inputs of `l`
    𝒫ⁿ = filter(p -> p ∈ inputs(l), 𝒫)

    @constraint(m, [t ∈ 𝒯, p ∈ 𝒫ⁿ],
        m[:link_potential_out][l, t, p] <= pressure(data, t) * m[:has_flow][l, t])
end
function constraints_pressure_limit(
    m,
    l::EMB.Link,
    data::MinPressureData,
    𝒯,
    𝒫::Vector{<:CompoundResource},
)
    # Filter resources CompoundResource that are inputs of `l`
    𝒫ⁿ = filter(p -> p ∈ inputs(l), 𝒫)

    @constraint(m, [t ∈ 𝒯, p ∈ 𝒫ⁿ],
        m[:link_potential_out][l, t, p] >= pressure(data, t) * m[:has_flow][l, t])
end
function constraints_pressure_limit(
    m,
    l::EMB.Link,
    data::FixPressureData,
    𝒯,
    𝒫::Vector{<:CompoundResource},
)
    # Filter resources CompoundResource that are inputs of `l`
    𝒫ⁿ = filter(p -> p ∈ inputs(l), 𝒫)

    @constraint(m, [t ∈ 𝒯, p ∈ 𝒫ⁿ],
        m[:link_potential_out][l, t, p] == pressure(data, t))
end

"""
    constraints_pressure_couple(m, n::Source, ℒ, 𝒯, 𝒫::Vector{<:CompoundResource})
    constraints_pressure_couple(m, n::Availability, ℒ, 𝒯, 𝒫::Vector{<:CompoundResource})
    constraints_pressure_couple(m, n::SimpleCompressor, ℒ, 𝒯, 𝒫::Vector{<:CompoundResource})
    constraints_pressure_couple(m, n::Sink, ℒ, 𝒯, 𝒫::Vector{<:CompoundResource})

Constraints setting the pressure balance between nodes and links.

Availability nodes do not allow increase in potential, while SimpleCompressor nodes allow it.
"""
function constraints_pressure_couple(
    m,
    n::EMB.Source,
    ℒ::Vector{<:EMB.Link},
    𝒯,
    𝒫::Vector{<:CompoundResource},
)
    # Filter resources CompoundResource that are inputs of `n`
    𝒫ⁿ = filter(p -> p ∈ outputs(n), 𝒫)

    # Get links from `n`
    ℒᶠʳᵒᵐ, _ = EMB.link_sub(ℒ, n)

    for l ∈ ℒᶠʳᵒᵐ
        @constraint(m, [t ∈ 𝒯, p ∈ 𝒫ⁿ],
            m[:potential_out][n, t, p] == m[:link_potential_in][l, t, p])
    end
end
function constraints_pressure_couple(
    m,
    n::EMB.Availability,
    ℒ::Vector{<:EMB.Link},
    𝒯,
    𝒫::Vector{<:CompoundResource},
)
    # Filter resources CompoundResource that are inputs of `n`
    𝒫ⁿ_in = filter(p -> p ∈ EMB.inputs(n), 𝒫)
    𝒫ⁿ_out = filter(p -> p ∈ EMB.outputs(n), 𝒫)

    # Get links from and to `n`
    ℒᶠʳᵒᵐ, ℒᵗᵒ = EMB.link_sub(ℒ, n)

    @constraint(m, [t ∈ 𝒯],
        sum(m[:lower_pressure_into_node][l_to, t] for l_to ∈ ℒᵗᵒ) == 1)

    @constraint(m, [t ∈ 𝒯, l_to in ℒᵗᵒ],
        m[:lower_pressure_into_node][l_to, t] <= m[:has_flow][l_to, t])

    # Outlet potential of `l` and Inlet Potential of `n`
    @constraint(m, [l_to ∈ ℒᵗᵒ, t ∈ 𝒯, p ∈ [pp for pp ∈ 𝒫ⁿ_in if pp in inputs(l_to)]],
        m[:potential_in][n, t, p] <=
        m[:link_potential_out][l_to, t, p] + 1e4 * (1 - m[:has_flow][l_to, t]))

    @constraint(m, [l_to ∈ ℒᵗᵒ, t ∈ 𝒯, p ∈ [pp for pp ∈ 𝒫ⁿ_in if pp in inputs(l_to)]],
        m[:potential_in][n, t, p] >=
        m[:link_potential_out][l_to, t, p] -
        1e4 * (1 - m[:lower_pressure_into_node][l_to, t]))

    # Outlet potential of `n` and Inlet Potential of `l`
    @constraint(m, [l_from ∈ ℒᶠʳᵒᵐ, t ∈ 𝒯, p ∈ inputs(l_from)],
        m[:link_potential_in][l_from, t, p] <=
        m[:potential_out][n, t, p] + 1e4 * (1 - m[:has_flow][l_from, t]))

    @constraint(m, [l_from ∈ ℒᶠʳᵒᵐ, t ∈ 𝒯, p ∈ inputs(l_from)],
        m[:link_potential_in][l_from, t, p] >=
        m[:potential_out][n, t, p] - 1e4 * (1 - m[:has_flow][l_from, t]))
end
function constraints_pressure_couple(
    m,
    n::SimpleCompressor,
    ℒ::Vector{<:EMB.Link},
    𝒯,
    𝒫::Vector{<:CompoundResource},
)
    # Filter resources CompoundResource that are inputs of `n`
    𝒫ⁿ_in = filter(p -> p ∈ EMB.inputs(n), 𝒫)
    𝒫ⁿ_out = filter(p -> p ∈ EMB.outputs(n), 𝒫)

    # Get links from and to `n`
    ℒᶠʳᵒᵐ, ℒᵗᵒ = EMB.link_sub(ℒ, n)

    @constraint(m, [t ∈ 𝒯],
        sum(m[:lower_pressure_into_node][l_to, t] for l_to ∈ ℒᵗᵒ) == 1)

    @constraint(m, [t ∈ 𝒯, l_to in ℒᵗᵒ],
        m[:lower_pressure_into_node][l_to, t] <= m[:has_flow][l_to, t])

    # Outlet potential of `l` and Inlet Potential of `n`
    @constraint(m, [l_to ∈ ℒᵗᵒ, t ∈ 𝒯, p ∈ [pp for pp ∈ 𝒫ⁿ_in if pp in inputs(l_to)]],
        m[:potential_in][n, t, p] <=
        m[:link_potential_out][l_to, t, p] + 1e4 * (1 - m[:has_flow][l_to, t]))

    @constraint(m, [l_to ∈ ℒᵗᵒ, t ∈ 𝒯, p ∈ [pp for pp ∈ 𝒫ⁿ_in if pp in inputs(l_to)]],
        m[:potential_in][n, t, p] >=
        m[:link_potential_out][l_to, t, p] -
        1e4 * (1 - m[:lower_pressure_into_node][l_to, t]))

    # The Outlet Potential in SimpleCompressor `n` is equal to the inlet potential + the required increased pressure
    # Note: The potential_Δ will be priced at opex_var in the objective function # TODO: Delete comment when SimpleCompressor Power consumption is defined
    @constraint(m, [t ∈ 𝒯, p ∈ 𝒫ⁿ_in],
        m[:potential_out][n, t, p] == m[:potential_in][n, t, p] + m[:potential_Δ][n, t])

    @constraint(m, [t ∈ 𝒯],
        m[:potential_Δ][n, t] <= get_potential(n, t))

    # Outlet potential of `n` and Inlet Potential of `l`
    @constraint(m, [l_from ∈ ℒᶠʳᵒᵐ, t ∈ 𝒯, p ∈ inputs(l_from), pp ∈ 𝒫ⁿ_out],
        m[:link_potential_in][l_from, t, p] <=
        m[:potential_out][n, t, pp] + 1e4 * (1 - m[:has_flow][l_from, t]))

    @constraint(m, [l_from ∈ ℒᶠʳᵒᵐ, t ∈ 𝒯, p ∈ inputs(l_from), pp ∈ 𝒫ⁿ_out],
        m[:link_potential_in][l_from, t, p] >=
        m[:potential_out][n, t, pp] - 1e4 * (1 - m[:has_flow][l_from, t]))
end
function constraints_pressure_couple(
    m,
    n::PoolingNode,
    ℒ::Vector{<:EMB.Link},
    𝒯,
    𝒫::Vector{<:CompoundResource},
)
    # Filter resources CompoundResource that are inputs and outputs of `n`
    𝒫ⁿ_in = filter(p -> p ∈ EMB.inputs(n), 𝒫)
    𝒫ⁿ_out = filter(p -> p ∈ EMB.outputs(n), 𝒫)

    # Get links from and to `n`
    ℒᶠʳᵒᵐ, ℒᵗᵒ = EMB.link_sub(ℒ, n)

    @constraint(m, [t ∈ 𝒯],
        sum(m[:lower_pressure_into_node][l_to, t] for l_to ∈ ℒᵗᵒ) == 1)

    @constraint(m, [t ∈ 𝒯, l_to in ℒᵗᵒ],
        m[:lower_pressure_into_node][l_to, t] <= m[:has_flow][l_to, t])

    # Outlet potential of `l` and Inlet Potential of `n`
    @constraint(m, [l_to ∈ ℒᵗᵒ, t ∈ 𝒯, p ∈ [pp for pp ∈ 𝒫ⁿ_in if pp in inputs(l_to)]],
        m[:potential_in][n, t, p] <=
        m[:link_potential_out][l_to, t, p] + 1e4 * (1 - m[:has_flow][l_to, t]))

    @constraint(m, [l_to ∈ ℒᵗᵒ, t ∈ 𝒯, p ∈ [pp for pp ∈ 𝒫ⁿ_in if pp in inputs(l_to)]],
        m[:potential_in][n, t, p] >=
        m[:link_potential_out][l_to, t, p] -
        1e4 * (1 - m[:lower_pressure_into_node][l_to, t]))

    # Outlet potential of `n` and Inlet Potential of `l`
    @constraint(m, [l_from ∈ ℒᶠʳᵒᵐ, t ∈ 𝒯, p ∈ inputs(l_from), pp ∈ 𝒫ⁿ_out],
        m[:link_potential_in][l_from, t, p] <=
        m[:potential_out][n, t, pp] + 1e4 * (1 - m[:has_flow][l_from, t]))

    @constraint(m, [l_from ∈ ℒᶠʳᵒᵐ, t ∈ 𝒯, p ∈ inputs(l_from), pp ∈ 𝒫ⁿ_out],
        m[:link_potential_in][l_from, t, p] >=
        m[:potential_out][n, t, pp] - 1e4 * (1 - m[:has_flow][l_from, t]))
end
function constraints_pressure_couple(
    m,
    n::EMB.Sink,
    ℒ::Vector{<:EMB.Link},
    𝒯,
    𝒫::Vector{<:CompoundResource},
)
    # Filter resources CompoundResource that are inputs of `n`
    𝒫ⁿ = filter(p -> p ∈ EMB.inputs(n), 𝒫)

    # Get links from and to `n`
    _, ℒᵗᵒ = EMB.link_sub(ℒ, n)

    @constraint(m, [t ∈ 𝒯],
        sum(m[:lower_pressure_into_node][l_to, t] for l_to ∈ ℒᵗᵒ) == 1)

    @constraint(m, [t ∈ 𝒯, l_to in ℒᵗᵒ],
        m[:lower_pressure_into_node][l_to, t] <= m[:has_flow][l_to, t])

    # Outlet potential of `l` and Inlet Potential of `n`
    @constraint(m, [l_to ∈ ℒᵗᵒ, t ∈ 𝒯, p ∈ [pp for pp ∈ 𝒫ⁿ if pp in inputs(l_to)]],
        m[:potential_in][n, t, p] <=
        m[:link_potential_out][l_to, t, p] + 1e4 * (1 - m[:has_flow][l_to, t]))

    @constraint(m, [l_to ∈ ℒᵗᵒ, t ∈ 𝒯, p ∈ [pp for pp ∈ 𝒫ⁿ if pp in inputs(l_to)]],
        m[:potential_in][n, t, p] >=
        m[:link_potential_out][l_to, t, p] -
        1e4 * (1 - m[:lower_pressure_into_node][l_to, t]))
end
function constraints_pressure_couple(m, n::EMB.AbstractElement, ℒ, 𝒯, 𝒫) end

"""
    constraints_flow_limit(m, l::CapDirect, 𝒯, 𝒫::Vector{<:CompoundResource}) 

Constraints setting the maximum flow through link `l` at time `t` according to its capacity and whether it has flow or not.
"""
function constraints_flow_limit(m, l::EMB.Link, 𝒯, 𝒫::Vector{<:CompoundResource})
    # Filter resources CompoundResource that are inputs of `l`
    𝒫ⁿ = filter(p -> p ∈ EMB.inputs(l), 𝒫)

    @constraint(
        m, [t ∈ 𝒯, p ∈ 𝒫ⁿ],
        m[:link_in][l, t, p] <= capacity(l, t) * m[:has_flow][l, t])
end

""" 
    constraints_flow_pressure(m, l::Link, 𝒯, 𝒫::Vector{<:CompoundResource})

Setting Weymouth constraints in link `l` to define the link_in according to its pressure drop.
The Weymouth equation will be approximated using the first-order Taylor expansion when the Resource is a `ResourcePressure`.
For `ResourceComponentPotential`, a Piecewise Affine Approximation (PWA) will be used.`
"""
function constraints_flow_pressure(
    m,
    l::EMB.Link,
    𝒯,
    𝒫::Vector{<:ResourcePressure},
    optimizer,
)
    # Filter resources CompoundResource that are inputs of `l`
    𝒫ⁿ = filter(p -> p ∈ EMB.inputs(l), 𝒫)

    if !isempty(𝒫ⁿ)
        # Retrieve elements from PressureLinkData in `l`
        # TODO: Make a check that ensures that a `l` with CompoundResource as input has AbstractLinkPressureData
        pressure_data = first(filter(data -> data isa PressureLinkData, l.data))
        weymouth_ct = get_weymouth(pressure_data)
        POut, PIn = potential_data(pressure_data)

        # Determine the (p_in, p_out) points for the Taylor approximation
        pressures_points = [(PIn, p) for p ∈ range(PIn, POut, length = 150)[2:end]]

        # Create Taylor constraint for each point
        # TODO: Doubt, if link_potential_in and link_potenntial_out are equal, there is still a flow
        for (p_in, p_out) ∈ pressures_points
            @constraint(m, [t ∈ 𝒯, p ∈ 𝒫ⁿ],
                m[:link_in][l, t, p] <=
                sqrt(weymouth_ct) * (
                    (p_in / (sqrt(p_in^2 - p_out^2))) * m[:link_potential_in][l, t, p] -
                    (p_out / (sqrt(p_in^2 - p_out^2))) * m[:link_potential_out][l, t, p]
                ))
        end
    end
end
function constraints_flow_pressure(
    m,
    l::EMB.Link,
    𝒯,
    𝒫::Vector{<:ResourcePooling{<:ResourcePressure}},
    optimizer,
)

    # Get inputs of `l` that are ResourcePooling
    𝒫ⁿ = [p for p ∈ EMB.inputs(l) if p ∈ 𝒫]

    if !isempty(𝒫ⁿ)
        pressure_data = first(filter(data -> data isa PressureLinkData, l.data))
        blend_data = first(filter(data -> data isa BlendData, l.data))

        p_blend = get_blendres(blend_data)
        p_track = get_trackres(blend_data)

        pwa = get_pwa(pressure_data, blend_data, optimizer)
        for (k, plane) ∈ enumerate(pwa.planes)
            constraints_pwa(m, l, p_blend, p_track, 𝒯, plane, pwa)
        end
    end
end
function constraints_flow_pressure(m, l::EMB.Link, 𝒯, 𝒫::Vector{<:Resource}, optimizer) end

"""
    constraints_pwa(m, l::Link, p_blend::ResourcePooling, p_track::ResourcePressure, 𝒯, plane, pwa::PWAFunc)
"""
function constraints_pwa(
    m,
    l::EMB.Link,
    p_blend::ResourcePooling,
    p_track::ResourcePressure,
    𝒯,
    plane,
    pwa::PWAFunc{C1,D1},
) where {C1,D1}
    n = l.from
    for t ∈ 𝒯
        PiecewiseAffineApprox.constr(
            C1,
            m,
            m[:link_in][l, t, p_blend],
            plane,
            (
                m[:link_potential_in][l, t, p_blend],
                m[:link_potential_out][l, t, p_blend],
                m[:proportion_track][n, t, p_track],
            ),
        )
    end
end
