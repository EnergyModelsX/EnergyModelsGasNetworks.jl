"""
    constraint_pressure(m, n::Source, 𝒯, 𝒫::Vector{<:CompoundResource})
    constraint_pressure(m, n::Availability, 𝒯, 𝒫::Vector{<:CompoundResource})
    constraint_pressure(m, n::Sink, 𝒯, 𝒫::Vector{<:CompoundResource})

Set internal balance pressures between `potential_in` and `potential_out` in Nodes `n`.
Source nodes have always inlet potential 0, Sink nodes have always outlet potential 0, Availability nodes have equal inlet and outlet potential.
"""
function constraints_pressure(m, n::EMB.Source, 𝒯, 𝒫::Vector{<:CompoundResource})
    # Filter resources CompoundResource that are output of `n``
    𝒫ⁿ = filter(p -> p ∈ EMB.outputs(n), 𝒫)

    # Inlet Potential for Source is always 0
    @constraint(m, [t ∈ 𝒯, p ∈ 𝒫ⁿ], m[:potential_in][n, t, p] == 0)
end
function constraints_pressure(m, n::EMB.Availability, 𝒯, 𝒫::Vector{<:CompoundResource})
    # Filter resources CompoundResource that are output of `n`
    𝒫ⁿ = filter(p -> p ∈ EMB.outputs(n), 𝒫)

    # Inlet and Outlet Potential should be equal
    @constraint(m, [t ∈ 𝒯, p ∈ 𝒫ⁿ], m[:potential_in][n, t, p] == m[:potential_out][n, t, p])
end
function constraints_pressure(m, n::Compressor,  𝒯, 𝒫::Vector{<:CompoundResource})
    # Filter resources CompoundResource that are output of `n`
    𝒫ⁿ = filter(p -> p ∈ EMB.inputs(n), 𝒫)

    # Inlet Potential lower than Outlet Potential
    @constraint(m, [t ∈ 𝒯, p ∈ 𝒫ⁿ], m[:potential_in][n, t, p] <= m[:potential_out][n, t, p])
end
function constraints_pressure(m, n::EMB.Sink, 𝒯, 𝒫::Vector{<:CompoundResource})
    # Filter resources CompoundResource that are output of `n`
    𝒫ⁿ = filter(p -> p ∈ EMB.inputs(n), 𝒫)

    # Outlet Potential for Sink is always 0
    @constraint(m, [t ∈ 𝒯, p ∈ 𝒫ⁿ], m[:potential_out][n, t, p] == 0)
end
function constraints_pressure(m, l::EMB.Link, 𝒯, 𝒫::Vector{<:CompoundResource})
    # Filter resources CompoundResource that are output of `l`
    𝒫ⁿ = filter(p -> p ∈ EMB.outputs(l), 𝒫)

    # Inlet Potential should be always higher or equal to Outlet Potential (direction)
    @constraint(m, [t ∈ 𝒯, p ∈ 𝒫ⁿ], m[:link_potential_in][l, t, p] >= m[:link_potential_out][l, t, p])
end
function constraints_pressure(m, n::EMB.AbstractElement, 𝒯, 𝒫::Vector{}) end

"""
    constraints_pressure_limit(m, n::Node, data::T, 𝒯, 𝒫::Vector{<:CompoundResource}) where {T<:PressureData}
    constraints_pressure_limit(m, n::Sink, data::T, 𝒯, 𝒫::Vector{<:CompoundResource}) where {T<:PressureData}

Set the pressure limits according to the PressureData `data` assigned to Node `n`.
"""
function constraints_pressure_limit(m, n::EMB.Node, data::MaxPressureData, 𝒯, 𝒫::Vector{<:CompoundResource})
    # Filter resources CompoundResource that are output of `n`
    𝒫ⁿ = filter(p -> p ∈ outputs(n), 𝒫)

    @constraint(m, [t ∈ 𝒯, p ∈ 𝒫ⁿ], 
        m[:potential_out][n, t, p] <= pressure(data, t))
end
function constraints_pressure_limit(m, n::EMB.Node, data::MinPressureData, 𝒯, 𝒫::Vector{<:CompoundResource})
    # Filter resources CompoundResource that are output of `n`
    𝒫ⁿ = filter(p -> p ∈ outputs(n), 𝒫)

    @constraint(m, [t ∈ 𝒯, p ∈ 𝒫ⁿ], 
        m[:potential_out][n, t, p] >= pressure(data, t))
end
function constraints_pressure_limit(m, n::EMB.Node, data::FixPressureData, 𝒯, 𝒫::Vector{<:CompoundResource})
    # Filter resources CompoundResource that are output of `n`
    𝒫ⁿ = filter(p -> p ∈ outputs(n), 𝒫)

    @constraint(m, [t ∈ 𝒯, p ∈ 𝒫ⁿ], 
        m[:potential_out][n, t, p] == pressure(data, t))
end
function constraints_pressure_limit(m, n::EMB.Sink, data::MaxPressureData, 𝒯, 𝒫::Vector{<:CompoundResource})
    # Filter resources CompoundResource that are inputs of `n`
    𝒫ⁿ = filter(p -> p ∈ inputs(n), 𝒫)

    @constraint(m, [t ∈ 𝒯, p ∈ 𝒫ⁿ], 
        m[:potential_in][n, t, p] <= pressure(data, t))
end
function constraints_pressure_limit(m, n::EMB.Sink, data::MinPressureData, 𝒯, 𝒫::Vector{<:CompoundResource})
    # Filter resources CompoundResource that are inputs of `n`
    𝒫ⁿ = filter(p -> p ∈ inputs(n), 𝒫)

    @constraint(m, [t ∈ 𝒯, p ∈ 𝒫ⁿ], 
        m[:potential_in][n, t, p] >= pressure(data, t))
end
function constraints_pressure_limit(m, n::EMB.Sink, data::FixPressureData, 𝒯, 𝒫::Vector{<:CompoundResource})
    # Filter resources CompoundResource that are inputs of `n`
    𝒫ⁿ = filter(p -> p ∈ inputs(n), 𝒫)

    @constraint(m, [t ∈ 𝒯, p ∈ 𝒫ⁿ], 
        m[:potential_in][n, t, p] == pressure(data, t))
end
function constraints_pressure_limit(m, l::EMB.Link, data::MaxPressureData, 𝒯, 𝒫::Vector{<:CompoundResource})
    # Filter resources CompoundResource that are inputs of `l`
    𝒫ⁿ = filter(p -> p ∈ inputs(l), 𝒫)

    @constraint(m, [t ∈ 𝒯, p ∈ 𝒫ⁿ], 
        m[:link_potential_in][l, t, p] <= pressure(data, t) * m[:has_flow][l, t])
end
function constraints_pressure_limit(m, l::EMB.Link, data::MinPressureData, 𝒯, 𝒫::Vector{<:CompoundResource})
    # Filter resources CompoundResource that are inputs of `l`
    𝒫ⁿ = filter(p -> p ∈ inputs(l), 𝒫)

    @constraint(m, [t ∈ 𝒯, p ∈ 𝒫ⁿ], 
        m[:link_potential_in][l, t, p] >= pressure(data, t) * m[:has_flow][l, t])
end
function constraints_pressure_limit(m, l::EMB.Link, data::FixPressureData, 𝒯, 𝒫::Vector{<:CompoundResource})
    # Filter resources CompoundResource that are inputs of `l`
    𝒫ⁿ = filter(p -> p ∈ inputs(l), 𝒫)

    @constraint(m, [t ∈ 𝒯, p ∈ 𝒫ⁿ], 
        m[:link_potential_in][l, t, p] == pressure(data, t))
end
function constraints_pressure_limit(m, l::EMB.Link, data::RefPressureData, 𝒯, 𝒫::Vector{}) end

"""
    constraints_pressure_couple(m, n::Source, ℒ, 𝒯, 𝒫::Vector{<:CompoundResource})
    constraints_pressure_couple(m, n::Availability, ℒ, 𝒯, 𝒫::Vector{<:CompoundResource})
    constraints_pressure_couple(m, n::Compressor, ℒ, 𝒯, 𝒫::Vector{<:CompoundResource})
    constraints_pressure_couple(m, n::Sink, ℒ, 𝒯, 𝒫::Vector{<:CompoundResource})

Constraints setting the pressure balance between nodes and links.

Availability nodes do not allow increase in potential, while Compressor nodes allow it.
"""
function constraints_pressure_couple(m, n::EMB.Source, ℒ::Vector{<:EMB.Link}, 𝒯, 𝒫::Vector{<:CompoundResource})
    # Filter resources CompoundResource that are inputs of `n`
    𝒫ⁿ = filter(p -> p ∈ outputs(n), 𝒫)

    # Get links from `n`
    ℒᶠʳᵒᵐ, _ = EMB.link_sub(ℒ, n)

    for l ∈ ℒᶠʳᵒᵐ
        @constraint(m, [t ∈ 𝒯, p ∈ 𝒫ⁿ],
            m[:potential_out][n, t, p] == m[:link_potential_in][l, t, p])
    end
end
function constraints_pressure_couple(m, n::EMB.Availability, ℒ::Vector{<:EMB.Link}, 𝒯, 𝒫::Vector{<:CompoundResource})
    # Filter resources CompoundResource that are inputs of `n`
    𝒫ⁿ = filter(p -> p ∈ inputs(n), 𝒫)

    # Get links from and to `n`
    ℒᶠʳᵒᵐ, ℒᵗᵒ = EMB.link_sub(ℒ, n)

    @constraint(m, [t ∈ 𝒯],
    sum(m[:lower_pressure_into_node][l_to, t] for l_to in ℒᵗᵒ) == 1)

    # Outlet potential of `l` and Inlet Potential of `n`
    @constraint(m, [l_to ∈ ℒᵗᵒ, t ∈ 𝒯, p ∈ 𝒫ⁿ],
        m[:potential_in][n, t, p] <= m[:link_potential_out][l_to, t, p] + 1e4 * (1 - m[:has_flow][l_to, t]))

    @constraint(m, [l_to ∈ ℒᵗᵒ, t ∈ 𝒯, p ∈ 𝒫ⁿ],
        m[:potential_in][n, t, p] >= m[:link_potential_out][l_to, t, p] - 1e4 * (1 - m[:lower_pressure_into_node][l_to, t]))

    # Outlet potential of `n` and Inlet Potential of `l`
    @constraint(m, [l_from ∈ ℒᶠʳᵒᵐ, t ∈ 𝒯, p ∈ 𝒫ⁿ],
        m[:link_potential_in][l_from, t, p] <=
        m[:potential_out][n, t, p] + 1e4 * (1 - m[:has_flow][l_from, t]))
    
    @constraint(m, [l_from ∈ ℒᶠʳᵒᵐ, t ∈ 𝒯, p ∈ 𝒫ⁿ],
        m[:link_potential_in][l_from, t, p] >=
        m[:potential_out][n, t, p] - 1e4 * (1 - m[:has_flow][l_from, t]))

end
function constraints_pressure_couple(m, n::Compressor, ℒ::Vector{<:EMB.Link}, 𝒯, 𝒫::Vector{<:CompoundResource})
    # Filter resources CompoundResource that are inputs of `n`
    𝒫ⁿ = filter(p -> p ∈ EMB.inputs(n), 𝒫)

    # Get links from and to `n`
    ℒᶠʳᵒᵐ, ℒᵗᵒ = EMB.link_sub(ℒ, n)

    @constraint(m, [t ∈ 𝒯],
        sum(m[:lower_pressure_into_node][l_to, t] for l_to in ℒᵗᵒ) == 1)
    
    # Outlet potential of `l` and Inlet Potential of `n`
    @constraint(m, [l_to ∈ ℒᵗᵒ, t ∈ 𝒯, p ∈ 𝒫ⁿ],
        m[:potential_in][n, t, p] <= m[:link_potential_out][l_to, t, p] + 1e4 * (1 - m[:has_flow][l_to, t]))
    
    @constraint(m, [l_to ∈ ℒᵗᵒ, t ∈ 𝒯, p ∈ 𝒫ⁿ],
        m[:potential_in][n, t, p] >= m[:link_potential_out][l_to, t, p] - 1e4 * (1 - m[:lower_pressure_into_node][l_to, t]))
    
    # The Outlet Potential in Compressor `n` is equal to the inlet potential + the required increased pressure
    # Note: The potential_Δ will be priced at opex_var in the objective function # TODO: Delete comment when Compressor Power consumption is defined
    @constraint(m, [t ∈ 𝒯, p ∈ 𝒫ⁿ],
        m[:potential_out][n, t, p] == m[:potential_in][n, t, p] + m[:potential_Δ][n, t])

    @constraint(m, [t ∈ 𝒯],
        m[:potential_Δ][n, t] <= get_potential(n, t))

    # Outlet potential of `n` and Inlet Potential of `l`
    @constraint(m, [l_from ∈ ℒᶠʳᵒᵐ, t ∈ 𝒯, p ∈ 𝒫ⁿ],
        m[:link_potential_in][l_from, t, p] <=
        m[:potential_out][n, t, p] + 1e4 * (1 - m[:has_flow][l_from, t]))
    
    @constraint(m, [l_from ∈ ℒᶠʳᵒᵐ, t ∈ 𝒯, p ∈ 𝒫ⁿ],
        m[:link_potential_in][l_from, t, p] >=
        m[:potential_out][n, t, p] - 1e4 * (1 - m[:has_flow][l_from, t]))

end
function constraints_pressure_couple(m, n::EMB.Sink, ℒ::Vector{<:EMB.Link}, 𝒯, 𝒫::Vector{<:CompoundResource})
    # Filter resources CompoundResource that are inputs of `n`
    𝒫ⁿ = filter(p -> p ∈ EMB.inputs(n), 𝒫)

    # Get links from and to `n`
    _, ℒᵗᵒ = EMB.link_sub(ℒ, n)

    for l ∈ ℒᵗᵒ
        @constraint(m, [t ∈ 𝒯, p ∈ 𝒫ⁿ],
            m[:potential_in][n, t, p] == m[:link_potential_out][l, t, p])
    end
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
        m[:link_in][l, t, p] <= capacity(l, t) * m[:has_flow][l, t]
    )

    @constraint(m, [t ∈ 𝒯, p ∈ 𝒫ⁿ],
        m[:link_potential_in][l, t, p] <= 1e4 * m[:has_flow][l, t]
    )
end

""" 
    constraints_flow_pressure(m, l::Link, 𝒯, 𝒫::Vector{<:CompoundResource})

Setting Weymouth constraints in link `l` to define the link_in according to its pressure drop.
The Weymouth equation will be approximated using the first-order Taylor expansion when the Resource is a `ResourcePotential`.
For `ResourceComponentPotential`, a Piecewise Affine Approximation (PWA) will be used.`
"""
function constraints_flow_pressure(m, l::EMB.Link, 𝒯, 𝒫::Vector{<:ResourcePotential})
    # Filter resources CompoundResource that are inputs of `l`
    𝒫ⁿ = filter(p -> p ∈ EMB.inputs(l), 𝒫)

    if !isempty(𝒫ⁿ)
        # Retrieve elements from PressureLinkData in `l`
        # TODO: Make a check that ensures that a `l` with CompoundResource as input has LinkPressureData
        pressure_data = first(filter(data -> data isa PressureLinkData, l.data))
        weymouth_ct = weymouth_constant(pressure_data)
        POut, PIn = potential_data(pressure_data)

        # Determine the (p_in, p_out) points for the Taylor approximation
        pressures_points = [(PIn, p) for p in range(PIn, POut, length=150)[2:end]]

        # Create Taylor constraint for each point
        for (p_in, p_out) ∈ pressures_points
            @constraint(m, [t ∈ 𝒯, p ∈ 𝒫ⁿ],
            m[:link_in][l, t, p] <= sqrt(weymouth_ct) * (
                                            (p_in/(sqrt(p_in^2 - p_out^2))) * m[:link_potential_in][l, t, p] -
                                            (p_out/(sqrt(p_in^2 - p_out^2))) * m[:link_potential_out][l, t, p]
                                            ))
        end
    end
end
function constraints_flow_pressure(m, l::EMB.Link, 𝒯, 𝒫::Vector{<:ResourceComponentPotential})
    # Filter resources CompoundResource that are inputs of `l`
    𝒫ⁿ = filter(p -> p ∈ inputs(l), 𝒫)

    # Retrieve elements from PressureLinkData in `l`
    if !isempty(𝒫ⁿ)
        pressure_data = first(filter(data -> data isa PressureLinkData, l.data))
        blend_data = []
        pwa = get_pwa(pressure_data)
        # for (k, plane) ∈ enumerate(pwa.planes)
        #     constraints_pwa(m, a, p, tm, 𝒯, plane, pwa)
        # end
        #TODO: Finish when defining ResourceComponentPotential and BlendData
    end
end
# function constraints_pwa(m, a::Union{PoolingArea, SourceArea}, p::ComponentTrack, tm, 𝒯, plane, pwa::PWAFunc{C1, D1}) where {C1, D1}
#     for t ∈ 𝒯
#         PiecewiseAffineApprox.constr(C1, m, m[:trans_in][tm, t], plane, (m[:p_in][tm, t], m[:p_out][tm, t], m[:prop_track][p, a, t]))
#     end
# end