"""
    constraints_balance_pressure(m, n::EMB.Node, 𝒯, 𝒫::Vector)
    constraints_balance_pressure(m, n::EMB.NetworkNode, 𝒯, 𝒫::Vector{<:CompoundResource})
    constraints_balance_pressure(m, n::SimpleCompressor, 𝒯, 𝒫::Vector{<:CompoundResource})
    constraints_balance_pressure(m, n::PoolingNode, 𝒯, 𝒫::Vector{<:ResourcePressure})
    constraints_balance_pressure(m, n::PoolingNode, 𝒯, 𝒫::Vector{<:ResourcePooling{ResourcePressure}})
    constraints_balance_pressure(m, l::EMB.Link, 𝒯, 𝒫::Vector{<:CompoundResource})

Set internal balance pressures between `potential_in` and `potential_out` in Nodes `n` and Links `l``.
The balance will depend on type of nodes:
- For `NetworkNode` nodes, the inlet and outlet potentials are equal.
- For `SimpleCompressor` nodes, the inlet potential is lower than or equal to the outlet potential.
- For `PoolingNode` nodes, the inlet potential of all input resources is equal to the outlet potential of all output resources.
- For Links, the inlet potential is higher than or equal to the outlet potential. if there is no flow through `l`, both potentials are set to zero.

Note: Sinks and Source nodes do not have internal pressure balances, as their potentials are only defined at inlet or outlet respectively.
"""
function constraints_balance_pressure(
    m,
    n::EMB.Availability,
    𝒯,
    𝒫::Vector{<:CompoundResource},
)
    # Filter resources CompoundResource that are output of `n`
    𝒫ⁿ = filter(p -> p ∈ EMB.outputs(n), 𝒫)

    # Inlet and Outlet Potential should be equal
    @constraint(m, [t ∈ 𝒯, p ∈ 𝒫ⁿ], m[:potential_in][n, t, p] == m[:potential_out][n, t, p])
end
function constraints_balance_pressure(
    m,
    n::UnitConversion,
    𝒯,
    𝒫::Vector{<:CompoundResource},
)
    # Filter resources CompoundResource that are output of `n`
    p_out = first(EMB.outputs(n))

    # Inlet and Outlet Potential should be equal
    @constraint(m, [t ∈ 𝒯], m[:potential_out][n, t, p_out] == 0)
end
function constraints_balance_pressure(
    m,
    n::SimpleCompressor,
    𝒯,
    𝒫::Vector{<:CompoundResource},
)
    # Filter resources CompoundResource that are output of `n`
    𝒫ⁿ = filter(p -> p ∈ EMB.inputs(n), 𝒫)

    # Inlet Potential lower than Outlet Potential
    @constraint(m, [t ∈ 𝒯, p ∈ 𝒫ⁿ], m[:potential_in][n, t, p] <= m[:potential_out][n, t, p])
end
function constraints_balance_pressure(m, n::PoolingNode, 𝒯, 𝒫::Vector{<:ResourcePressure})
    # Filter input and output resources
    𝒫ⁱⁿ = filter(p -> p ∈ EMB.inputs(n), 𝒫)
    𝒫ᵒᵘᵗ = EMB.outputs(n)

    # Inlet Potential for each input resource should equal the outlet potential of the output (no drop or increase in potential)
    @constraint(m, [t ∈ 𝒯, p_in ∈ 𝒫ⁱⁿ, p_out ∈ 𝒫ᵒᵘᵗ],
        m[:potential_in][n, t, p_in] == m[:potential_out][n, t, p_out])
end
function constraints_balance_pressure(
    m,
    n::PoolingNode,
    𝒯,
    𝒫::Vector{<:ResourcePooling{ResourcePressure}},
) end
function constraints_balance_pressure(m, l::EMB.Link, 𝒯, 𝒫::Vector{<:CompoundResource})

    # Inlet Potential should be always higher or equal to Outlet Potential (direction)
    @constraint(
        m,
        [t ∈ 𝒯, p ∈ 𝒫],
        m[:link_potential_in][l, t, p] >= m[:link_potential_out][l, t, p]
    )

    @constraint(m, [t ∈ 𝒯, p ∈ 𝒫],
        m[:link_potential_in][l, t, p] <= 1e4 * m[:has_flow][l, t])
    @constraint(m, [t ∈ 𝒯, p ∈ 𝒫],
        m[:link_potential_out][l, t, p] <= 1e4 * m[:has_flow][l, t])
end
function constraints_balance_pressure(m, l::EMB.Direct, 𝒯, 𝒫::Vector{<:CompoundResource})
    # Inlet Potential should be always higher or equal to Outlet Potential (direction)
    @constraint(
        m,
        [t ∈ 𝒯, p ∈ 𝒫],
        m[:link_potential_in][l, t, p] == m[:link_potential_out][l, t, p]
    )
end
function constraints_balance_pressure(m, n::EMB.Node, 𝒯, 𝒫::Vector) end

"""
    constraints_pressure_bounds_element(m, x, 𝒯, 𝒫::Vector{<:CompoundResource})

This function calls subfunctions to set the pressure bounds for each `AbstractPressureData` assigned to element `x`.
"""
function constraints_pressure_bounds_element(m, x, 𝒯, 𝒫::Vector{<:CompoundResource})
    # Get AbstractPressureData and generate limit constraints if any
    pressure_data = filter(d -> d isa AbstractPressureData, get_pressuredata(x))
    if !isempty(pressure_data)
        for d ∈ pressure_data
            constraints_pressure_bounds(m, x, d, 𝒯, 𝒫)
        end
    end
end
"""
    constraints_pressure_bounds(m, n::Node, data::T, 𝒯, 𝒫::Vector{<:CompoundResource}) where {T<:PressureData}
    constraints_pressure_bounds(m, n::Sink, data::T, 𝒯, 𝒫::Vector{<:CompoundResource}) where {T<:PressureData}
    constraints_pressure_bounds(m, l::Link, data::T, 𝒯, 𝒫::Vector{<:CompoundResource}) where {T<:PressureData}

Set the pressure limits according to the PressureData `data` assigned to Node `n` and Link `l`.
If n is a Sink, the limits are applied to the inlet potential. Otherwise, the limits are applied to the outlet potential.
For Links, the limits are applied to the outlet potential only if the link has flow.

The data can be of type:
- MaxPressureData, which will set a maximum pressure bound.
- MinPressureData, which will set a minimum pressure bound.
- FixPressureData, which will set an equality pressure bound.
"""
function constraints_pressure_bounds(
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
function constraints_pressure_bounds(
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
function constraints_pressure_bounds(
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
function constraints_pressure_bounds(
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
function constraints_pressure_bounds(
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
function constraints_pressure_bounds(
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
function constraints_pressure_bounds(
    m,
    l::EMB.Link,
    data::MaxPressureData,
    𝒯,
    𝒫::Vector{<:CompoundResource},
)
    @constraint(m, [t ∈ 𝒯, p ∈ 𝒫],
        m[:link_potential_out][l, t, p] <= pressure(data, t) * m[:has_flow][l, t])
end
function constraints_pressure_bounds(
    m,
    l::EMB.Link,
    data::MinPressureData,
    𝒯,
    𝒫::Vector{<:CompoundResource},
)
    @constraint(m, [t ∈ 𝒯, p ∈ 𝒫],
        m[:link_potential_out][l, t, p] >= pressure(data, t) * m[:has_flow][l, t])
end
function constraints_pressure_bounds(
    m,
    l::EMB.Link,
    data::FixPressureData,
    𝒯,
    𝒫::Vector{<:CompoundResource},
)
    @constraint(m, [t ∈ 𝒯, p ∈ 𝒫],
        m[:link_potential_out][l, t, p] == pressure(data, t))
end

"""
    constraints_pressure_couple(m, n::EMB.Source, ℒ, 𝒯, 𝒫::Vector{<:CompoundResource})
    constraints_pressure_couple(m, n::EMB.Availability, ℒ, 𝒯, 𝒫::Vector{<:CompoundResource})
    constraints_pressure_couple(m, n::SimpleCompressor, ℒ, 𝒯, 𝒫::Vector{<:CompoundResource})
    constraints_pressure_couple(m, n::PoolingNode, ℒ, 𝒯, 𝒫::Vector{<:CompoundResource})
    constraints_pressure_couple(m, n::EMB.Sink, ℒ, 𝒯, 𝒫::Vector{<:CompoundResource})

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
    n::EMB.NetworkNode,
    ℒ::Vector{<:EMB.Link},
    𝒯,
    𝒫::Vector{<:CompoundResource},
)
    # Filter resources CompoundResource that are inputs of `n`
    𝒫ⁿ_in = filter(p -> p ∈ EMB.inputs(n), 𝒫)
    𝒫ⁿ_out = filter(p -> p ∈ EMB.outputs(n), 𝒫)

    # Get links from and to `n`
    ℒᶠʳᵒᵐ, ℒᵗᵒ = EMB.link_sub(ℒ, n)

    if !isempty(ℒᵗᵒ)
        @constraint(m, [t ∈ 𝒯],
            sum(m[:lower_pressure_into_node][l_to, t] for l_to ∈ ℒᵗᵒ) == 1)
    end

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
    n::Compressor,
    ℒ::Vector{<:EMB.Link},
    𝒯,
    𝒫::Vector{<:CompoundResource},
)
    # Filter resources CompoundResource that are inputs of `n`
    𝒫ⁿ_in = EMB.inputs(n)
    𝒫ⁿ_out = EMB.outputs(n)
    P = setdiff(𝒫ⁿ_in, 𝒫ⁿ_out)

    # Get links from and to `n`
    ℒᶠʳᵒᵐ, ℒᵗᵒ = EMB.link_sub(ℒ, n)
    ℒᵗᵒ = filter(l -> inputs(l) != P, ℒᵗᵒ) # Filter out links whose resource is not relevant for pressure coupling

    if !isempty(ℒᵗᵒ)
        @constraint(m, [t ∈ 𝒯],
            sum(m[:lower_pressure_into_node][l_to, t] for l_to ∈ ℒᵗᵒ) == 1)
    end

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
    @constraint(m, [t ∈ 𝒯, p ∈ setdiff(𝒫ⁿ_in, P)],
        m[:potential_out][n, t, p] == m[:potential_in][n, t, p] + m[:potential_Δ][n, t])

    @constraint(m, [t ∈ 𝒯],
        m[:potential_Δ][n, t] <= get_max_potential(n, t))

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

    if !isempty(ℒᵗᵒ)
        @constraint(m, [t ∈ 𝒯],
            sum(m[:lower_pressure_into_node][l_to, t] for l_to ∈ ℒᵗᵒ) == 1)
    end

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

    if !isempty(ℒᵗᵒ)
        @constraint(m, [t ∈ 𝒯],
            sum(m[:lower_pressure_into_node][l_to, t] for l_to ∈ ℒᵗᵒ) == 1)
    end

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
    constraints_flow_capacity(m, l::EMB.Link, 𝒯, 𝒫::Vector{<:CompoundResource}) 

Constraints setting the maximum flow through link `l` at time `t` whether it has flow or not.
"""
function constraints_flow_capacity(m, l::EMB.Link, 𝒯, 𝒫::Vector{<:CompoundResource})
    @constraint(
        m, [t ∈ 𝒯, p ∈ 𝒫],
        m[:link_in][l, t, p] <= 1e6 * m[:has_flow][l, t])
end

""" 
    constraints_flow_pressure(m, l::EMB.Link, 𝒯, 𝒫::Vector{<:ResourcePressure})
    constraints_flow_pressure(m, l::EMB.Link, 𝒯, 𝒫::Vector{<:ResourcePooling{<:ResourcePressure}})
    constraints_flow_pressure(m, l::EMB.Link, 𝒯, 𝒫::Vector{<:Resource})  
    constraints_flow_pressure(m, l::EMB.Direct, 𝒯, 𝒫::Vector)

Setting Weymouth constraints in link `l`. This calculates the flow through l based on the pressure difference between inlet and outlet.
The Weymouth equation will be approximated using the first-order Taylor expansion when the Resource is a `ResourcePressure`.
For `ResourceComponentPotential`, a Piecewise Affine Approximation (PWA) will be used.`
"""
function constraints_flow_pressure(
    m,
    l::EMB.Link,
    𝒯,
    𝒫::Vector{<:ResourcePressure},
)
    @info "Taylor Approximation for $l"
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
        @constraint(m, [t ∈ 𝒯, p ∈ 𝒫],
            m[:link_in][l, t, p] <=
            sqrt(weymouth_ct) * (
                (p_in / (sqrt(p_in^2 - p_out^2))) * m[:link_potential_in][l, t, p] -
                (p_out / (sqrt(p_in^2 - p_out^2))) * m[:link_potential_out][l, t, p]
            ))
    end
end
function constraints_flow_pressure(
    m,
    l::EMB.Link,
    𝒯,
    𝒫::Vector{<:ResourcePooling{<:ResourcePressure}},
)
    # Extract optimizer from model
    optimizer = _get_optimizer()

    # Extract PressureLinkData and BlendData from link `l`
    pressure_data = first(filter(data -> data isa PressureLinkData, l.data))
    blend_data = first(filter(data -> data isa BlendData, l.data))

    p_blend = get_blendres(blend_data)
    p_track = get_trackres(blend_data)

    @info "PWA for $l"
    pwa = get_pwa(pressure_data, blend_data, optimizer)
    for (k, plane) ∈ enumerate(pwa.planes)
        constraints_pwa(m, l, p_blend, p_track, 𝒯, plane, pwa)
    end
end
function constraints_flow_pressure(m, l::EMB.Link, 𝒯, 𝒫::Vector{<:Resource}) end
function constraints_flow_pressure(m, l::EMB.Direct, 𝒯, 𝒫::Vector{<:ResourcePressure}) end
function constraints_flow_pressure(
    m,
    l::EMB.Direct,
    𝒯,
    𝒫::Vector{<:ResourcePooling{<:ResourcePressure}},
) end
function constraints_flow_pressure(m, l::EMB.Direct, 𝒯, 𝒫::Vector{<:Resource}) end

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

"""
    constraints_energy_potential(m, n::SimpleCompressor, 𝒯, 𝒫, modeltype::EMB.EnergyModel)
    constraints_energy_potential(m, n::EMB.Node, 𝒯, 𝒫, modeltype::EMB.EnergyModel)

Sets the relationship between energy needs and pressure increase, or any other parameter in Compressor `n` that determines its energy consumption.
Skip if the node is not a type `Compressor`.

If n is a `SimpleCompressor`, the energy consumption will be calculated as the product of the flow through the compressor, and the energy input required per unit of flow.
This is defined with the default constraint `constraints_flow_in()`.

Note! If new Compressor types are created with different relationships between energy flow and pressure increase, 
this function should be updated to include the new type and relationship.
"""
function constraints_energy_potential(
    m,
    n::SimpleCompressor,
    𝒯,
    𝒫,
    modeltype::EMB.EnergyModel,
)
    # Filter resources CompoundResource that are inputs of `n`
    𝒫ⁿ_in = EMB.inputs(n)
    𝒫ⁿ_out = EMB.outputs(n)
    P = setdiff(𝒫ⁿ_in, 𝒫ⁿ_out)

    @constraint(m, [t ∈ 𝒯, p ∈ P],
        m[:flow_in][n, t, p] >= EMB.inputs(n, p) * m[:potential_Δ][n, t])
end
function constraints_energy_potential(m, n::EMB.Node, 𝒯, 𝒫, modeltype::EMB.EnergyModel) end

""""
    constraints_bidirectional_pressure(m, l::EMB.Link, ℒ, 𝒯, 𝒫)
    constraints_bidirectional_pressure(m, l::EMB.Direct, ℒ, 𝒯, 𝒫)

Ensure that parallel links defining bidirectionality cannot have flow at the same time. The link without flow will automatically have zero 
link_in_potential and link_out_potential due to the `constraints_balance_pressure` constraints.
"""
function constraints_bidirectional_pressure(m, l::EMB.Link, ℒ::Vector{<:EMB.Link}, 𝒯, 𝒫)
    ℒᵇ = filter(ll -> (ll.from == l.to && ll.to == l.from), ℒ)

    @constraint(m, [ll ∈ ℒᵇ, t ∈ 𝒯],
        m[:has_flow][ll, t] + m[:has_flow][l, t] <= 1)
end
function constraints_bidirectional_pressure(m, l::EMB.Direct, ℒ::Vector{<:EMB.Link}, 𝒯, 𝒫) end
