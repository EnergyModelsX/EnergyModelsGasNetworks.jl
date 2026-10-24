"""
    constraints_balance_pressure(m, n::EMB.Node, 𝒯, 𝒫::Vector)
    constraints_balance_pressure(m, n::EMB.NetworkNode, 𝒯, 𝒫::Vector{<:CompoundResource})
    constraints_balance_pressure(m, n::Compressor, 𝒯, 𝒫::Vector{<:CompoundResource})
    constraints_balance_pressure(m, n::Compressor, 𝒯, 𝒫::Vector{<:ResourcePressure})
    constraints_balance_pressure(m, n::DeblendNode, 𝒯, 𝒫::Vector{<:CompoundResource})
    constraints_balance_pressure(m, n::PoolingNode, 𝒯, 𝒫::Vector{<:ResourcePressure})
    constraints_balance_pressure(m, n::PoolingNode, 𝒯, 𝒫::Vector{<:ResourcePooling{<:ResourcePressure}})
    constraints_balance_pressure(m, l::EMB.Link, 𝒯, 𝒫::Vector{<:CompoundResource})

Set internal balance pressures between `potential_in` and `potential_out` in Nodes `n` and Links `l``.
The balance will depend on type of nodes:
- For `NetworkNode` nodes, the inlet and outlet potentials are equal.
- For `Compressor` nodes, the inlet potential is lower than or equal to the outlet potential.
- For `DeblendNode` nodes, the Blend output equals the Blend input (no pressure drop through the separator); the extracted H₂ output pressure is unconstrained here.
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
    n::EMB.NetworkNode,
    𝒯,
    𝒫::Vector{<:CompoundResource},
)
    # Resources that pass through (both input and output of `n`)
    𝒫ⁿ = filter(p -> p ∈ EMB.inputs(n) && p ∈ EMB.outputs(n), 𝒫)
    # Outlet potential cannot exceed inlet potential — pressure can only be conserved or drop,
    # not created.  Using >= (not ==) matches PoolingNode semantics: when multiple sources feed
    # the node at different pressures, the outlet is limited by the lowest incoming potential.
    @constraint(m, [t ∈ 𝒯, p ∈ 𝒫ⁿ],
        m[:potential_in][n, t, p] >= m[:potential_out][n, t, p])
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
    n::Compressor,
    𝒯,
    𝒫::Vector{<:CompoundResource},
)
    # Filter resources CompoundResource that are output of `n`
    𝒫ⁿ = filter(p -> p ∈ EMB.inputs(n), 𝒫)

    # Inlet Potential lower than Outlet Potential
    @constraint(m, [t ∈ 𝒯, p ∈ 𝒫ⁿ], m[:potential_in][n, t, p] <= m[:potential_out][n, t, p])
end
"""
    constraints_balance_pressure(m, n::Compressor, 𝒯, 𝒫::Vector{<:ResourcePressure})

For a `Compressor` carrying a pure `ResourcePressure` gas (e.g. H₂ without blending), the
outlet potential must be at least as large as the inlet potential — the compressor only raises
pressure, never lowers it.

This mirrors `constraints_balance_pressure(m, n::SimpleCompressor, ..., CompoundResource)`.
The equality `potential_out = potential_in + potential_Δ` is enforced in
`constraints_pressure_couple`.
"""
function constraints_balance_pressure(
    m,
    n::Compressor,
    𝒯,
    𝒫::Vector{<:ResourcePressure},
)
    𝒫ⁿ = filter(p -> p ∈ EMB.inputs(n), 𝒫)
    @constraint(m, [t ∈ 𝒯, p ∈ 𝒫ⁿ], m[:potential_in][n, t, p] <= m[:potential_out][n, t, p])
end
# Resolve ambiguity: SimpleCompressor is more specific than Compressor, so it needs its own
# ResourcePressure dispatch to avoid ambiguity with the CompoundResource dispatch above.
function constraints_balance_pressure(
    m,
    n::SimpleCompressor,
    𝒯,
    𝒫::Vector{<:ResourcePressure},
)
    𝒫ⁿ = filter(p -> p ∈ EMB.inputs(n), 𝒫)
    @constraint(m, [t ∈ 𝒯, p ∈ 𝒫ⁿ], m[:potential_in][n, t, p] <= m[:potential_out][n, t, p])
end
function constraints_balance_pressure(m, n::PoolingNode, 𝒯, 𝒫::Vector{<:ResourcePressure})
    𝒫ⁱⁿ = filter(p -> p ∈ EMB.inputs(n), 𝒫)
    𝒫ᵒᵘᵗ = EMB.outputs(n)
    @constraint(m, [t ∈ 𝒯, p_in ∈ 𝒫ⁱⁿ, p_out ∈ 𝒫ᵒᵘᵗ],
        m[:potential_in][n, t, p_in] >= m[:potential_out][n, t, p_out])
end
function constraints_balance_pressure(
    m,
    n::PoolingNode,
    𝒯,
    𝒫::Vector{<:ResourcePooling{<:ResourcePressure}},
)
    𝒫ⁱⁿ  = filter(p -> p ∈ EMB.inputs(n), 𝒫)
    𝒫ᵒᵘᵗ = filter(p -> p ∈ EMB.outputs(n), 𝒫)
    (isempty(𝒫ⁱⁿ) || isempty(𝒫ᵒᵘᵗ)) && return
    @constraint(m, [t ∈ 𝒯, p_in ∈ 𝒫ⁱⁿ, p_out ∈ 𝒫ᵒᵘᵗ],
        m[:potential_in][n, t, p_in] >= m[:potential_out][n, t, p_out])
end
function constraints_balance_pressure(
    m,
    n::DiscretizedPoolingNode,
    𝒯,
    𝒫::Vector{<:ResourcePressure},
)
    𝒫ⁱⁿ = filter(p -> p ∈ EMB.inputs(n), 𝒫)
    𝒫ᵒᵘᵗ = EMB.outputs(n)
    @constraint(m, [t ∈ 𝒯, p_in ∈ 𝒫ⁱⁿ, p_out ∈ 𝒫ᵒᵘᵗ],
        m[:potential_in][n, t, p_in] >= m[:potential_out][n, t, p_out])
end
function constraints_balance_pressure(
    m,
    n::DiscretizedPoolingNode,
    𝒯,
    𝒫::Vector{<:ResourcePooling{<:ResourcePressure}},
)
    𝒫ⁱⁿ  = filter(p -> p ∈ EMB.inputs(n), 𝒫)
    𝒫ᵒᵘᵗ = filter(p -> p ∈ EMB.outputs(n), 𝒫)
    (isempty(𝒫ⁱⁿ) || isempty(𝒫ᵒᵘᵗ)) && return
    @constraint(m, [t ∈ 𝒯, p_in ∈ 𝒫ⁱⁿ, p_out ∈ 𝒫ᵒᵘᵗ],
        m[:potential_in][n, t, p_in] >= m[:potential_out][n, t, p_out])
end
# DeblendNode: the Blend output pressure should be bounded below by the separator's
# minimum operating pressure.  Without this, the NetworkNode dispatch (`potential_in >=
# potential_out`) allows `potential_out[Blend]` to collapse to 0 bar when the H₂
# extraction link is idle (`has_flow[l_H₂] = 0`), decoupling the downstream pressure
# chain.  The actual lower-bound constraint is injected via `MinPressureData` attached to
# the node in the case YAML — no special dispatch needed here.
# (Falls through to the default EMB.Node no-op.)
# BlendingNode uses identical pressure semantics to PoolingNode: all input pressures
# must be at least the single output pressure.
function constraints_balance_pressure(m, n::BlendingNode, 𝒯, 𝒫::Vector{<:ResourcePressure})
    𝒫ⁱⁿ = filter(p -> p ∈ EMB.inputs(n), 𝒫)
    𝒫ᵒᵘᵗ = EMB.outputs(n)
    @constraint(m, [t ∈ 𝒯, p_in ∈ 𝒫ⁱⁿ, p_out ∈ 𝒫ᵒᵘᵗ],
        m[:potential_in][n, t, p_in] >= m[:potential_out][n, t, p_out])
end
function constraints_balance_pressure(
    m,
    n::BlendingNode,
    𝒯,
    𝒫::Vector{<:ResourcePooling{<:ResourcePressure}},
)
    𝒫ⁱⁿ  = filter(p -> p ∈ EMB.inputs(n), 𝒫)
    𝒫ᵒᵘᵗ = filter(p -> p ∈ EMB.outputs(n), 𝒫)
    (isempty(𝒫ⁱⁿ) || isempty(𝒫ᵒᵘᵗ)) && return
    @constraint(m, [t ∈ 𝒯, p_in ∈ 𝒫ⁱⁿ, p_out ∈ 𝒫ᵒᵘᵗ],
        m[:potential_in][n, t, p_in] >= m[:potential_out][n, t, p_out])
end
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
function constraints_balance_pressure(m, l::ZeroDrop, 𝒯, 𝒫::Vector{<:CompoundResource})
    # When flow is active, inlet and outlet potentials are equal (zero pressure drop).
    # The equality is relaxed with a big-M when has_flow = 0, so that zero-flow pipes do not
    # propagate pressure equality across network regions at different pressure levels.
    @constraint(
        m,
        [t ∈ 𝒯, p ∈ 𝒫],
        m[:link_potential_in][l, t, p] <=
        m[:link_potential_out][l, t, p] + 1e4 * (1 - m[:has_flow][l, t])
    )
    @constraint(
        m,
        [t ∈ 𝒯, p ∈ 𝒫],
        m[:link_potential_in][l, t, p] >=
        m[:link_potential_out][l, t, p] - 1e4 * (1 - m[:has_flow][l, t])
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
    constraints_pressure_couple(m, n::EMB.NetworkNode, ℒ, 𝒯, 𝒫::Vector{<:CompoundResource})
    constraints_pressure_couple(m, n::Compressor, ℒ, 𝒯, 𝒫::Vector{<:CompoundResource})
    constraints_pressure_couple(m, n::Compressor, ℒ, 𝒯, 𝒫::Vector{<:ResourcePressure})
    constraints_pressure_couple(m, n::PoolingNode, ℒ, 𝒯, 𝒫::Vector{<:CompoundResource})
    constraints_pressure_couple(m, n::DiscretizedPoolingNode, ℒ, 𝒯, 𝒫::Vector{<:CompoundResource})
    constraints_pressure_couple(m, n::TransitNode, ℒ, 𝒯, 𝒫::Vector{<:CompoundResource})
    constraints_pressure_couple(m, n::EMB.Sink, ℒ, 𝒯, 𝒫::Vector{<:CompoundResource})

Constraints coupling node potentials to the potentials of their connected links.

Each dispatch sets the node's `potential_in` and `potential_out` equal (within a big-M
relaxation) to the corresponding `link_potential_out` and `link_potential_in` of connected
pressure-carrying links. The coupling logic varies by node type:

- **`EMB.Source`**: outlet potential equals each outgoing link's inlet potential (equality, no big-M needed since sources always inject).
- **`EMB.NetworkNode`**, **`PoolingNode`**, **`TransitNode`**, **`EMB.Sink`**: uses `has_flow` big-M for both the upper and lower bound on `potential_in[n]`. When `has_flow=1`, both bounds bind, forcing `potential_in[n] = link_potential_out[l]` for each active link. When multiple links are active, their outlet potentials are all forced equal to the node inlet potential — correct junction physics assuming pressure reduction valves reduce any higher-pressure incoming flows to the node pressure.
- **`Compressor`**: same as NetworkNode, but incoming Power links are filtered out before applying any pressure coupling (pressure coupling applies only to the gas resource, not the power resource).

## Link filtering

In all dispatches, `ℒᵗᵒ` and `ℒᶠʳᵒᵐ` are filtered to include only links that carry at
least one `CompoundResource`. This excludes Power-only links (e.g., compressor power inputs,
output links from unit-conversion nodes) which have no `link_potential_*` variables and
whose `has_flow` binary is not declared.

## Pressure coupling

For each active incoming link (`has_flow=1`), the node inlet potential is bounded above
by the link outlet potential via a `has_flow`-gated big-M constraint:

```julia
potential_in[n] ≤ link_potential_out[l] + 1e4*(1 - has_flow[l])
```

When `has_flow=1` this forces `potential_in[n] ≤ link_potential_out[l]`. When `has_flow=0`
the bound is inactive. With multiple active incoming links the node inlet potential is
bounded above by the minimum of all active link outlet potentials. The optimizer naturally
drives the node pressure up to that minimum (to maximise downstream flow capacity), giving
"lowest incoming pressure" semantics without a separate lower bound constraint.

No explicit lower bound is added for `potential_in[n]` from incoming links; the lower
bound comes from downstream constraints (Weymouth flow requirements, `MinPressureData`).
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

    # Get links from and to `n`, restricted to pressure-carrying links
    ℒᶠʳᵒᵐ, ℒᵗᵒ = EMB.link_sub(ℒ, n)
    ℒᵗᵒ = filter(l -> any(r -> r isa CompoundResource, EMB.inputs(l)), ℒᵗᵒ)
    ℒᶠʳᵒᵐ = filter(l -> any(r -> r isa CompoundResource, EMB.inputs(l)), ℒᶠʳᵒᵐ)

    # Outlet potential of `l` and Inlet Potential of `n`
    @constraint(m, [l_to ∈ ℒᵗᵒ, t ∈ 𝒯, p ∈ [pp for pp ∈ 𝒫ⁿ_in if pp in inputs(l_to)]],
        m[:potential_in][n, t, p] <=
        m[:link_potential_out][l_to, t, p] + 1e4 * (1 - m[:has_flow][l_to, t]))

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

    # Outlet potential of `l` and Inlet Potential of `n`
    @constraint(m, [l_to ∈ ℒᵗᵒ, t ∈ 𝒯, p ∈ [pp for pp ∈ 𝒫ⁿ_in if pp in inputs(l_to)]],
        m[:potential_in][n, t, p] <=
        m[:link_potential_out][l_to, t, p] + 1e4 * (1 - m[:has_flow][l_to, t]))

    # The outlet potential equals the inlet potential plus the compressor pressure increase.
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
"""
    constraints_pressure_couple(m, n::Compressor, ℒ, 𝒯, 𝒫::Vector{<:ResourcePressure})

Pressure coupling for a `Compressor` carrying a pure `ResourcePressure` gas (e.g. pure H₂,
no blending).  Mirrors the `CompoundResource` dispatch but filters for `ResourcePressure`
links, excluding Power-only links that carry no pressure potential.

Enforces:
- `potential_in[n] ≤ link_potential_out[l_to] + BigM×(1−has_flow[l_to])` (inlet coupling)
- `potential_out[n] = potential_in[n] + potential_Δ[n]`              (pressure rise)
- `potential_Δ[n] ≤ max_incr_potential[n]`                           (compressor limit)
- `link_potential_in[l_from] = potential_out[n]` (bigM equality)     (outlet coupling)
"""
function constraints_pressure_couple(
    m,
    n::Compressor,
    ℒ::Vector{<:EMB.Link},
    𝒯,
    𝒫::Vector{<:ResourcePressure},
)
    𝒫ⁿ_in  = EMB.inputs(n)
    𝒫ⁿ_out = EMB.outputs(n)
    P      = setdiff(𝒫ⁿ_in, 𝒫ⁿ_out)  # energy resource (e.g. Power)

    ℒᶠʳᵒᵐ, ℒᵗᵒ = EMB.link_sub(ℒ, n)
    # Exclude Power-only links (they carry no pressure potential)
    ℒᵗᵒ   = filter(l -> any(r -> r isa ResourcePressure, EMB.inputs(l)), ℒᵗᵒ)
    ℒᶠʳᵒᵐ = filter(l -> any(r -> r isa ResourcePressure, EMB.inputs(l)), ℒᶠʳᵒᵐ)

    # Inlet potential of `n` coupled to the outlet potential of upstream links
    @constraint(m, [l_to ∈ ℒᵗᵒ, t ∈ 𝒯, p ∈ [pp for pp ∈ 𝒫ⁿ_in if pp in inputs(l_to)]],
        m[:potential_in][n, t, p] <=
        m[:link_potential_out][l_to, t, p] + 1e4 * (1 - m[:has_flow][l_to, t]))

    # Outlet potential = inlet potential + pressure rise
    @constraint(m, [t ∈ 𝒯, p ∈ setdiff(𝒫ⁿ_in, P)],
        m[:potential_out][n, t, p] == m[:potential_in][n, t, p] + m[:potential_Δ][n, t])

    @constraint(m, [t ∈ 𝒯],
        m[:potential_Δ][n, t] <= get_max_potential(n, t))

    # Outlet potential of `n` coupled to the inlet potential of downstream links
    @constraint(m, [l_from ∈ ℒᶠʳᵒᵐ, t ∈ 𝒯, p ∈ inputs(l_from), pp ∈ 𝒫ⁿ_out],
        m[:link_potential_in][l_from, t, p] <=
        m[:potential_out][n, t, pp] + 1e4 * (1 - m[:has_flow][l_from, t]))

    @constraint(m, [l_from ∈ ℒᶠʳᵒᵐ, t ∈ 𝒯, p ∈ inputs(l_from), pp ∈ 𝒫ⁿ_out],
        m[:link_potential_in][l_from, t, p] >=
        m[:potential_out][n, t, pp] - 1e4 * (1 - m[:has_flow][l_from, t]))
end
# Resolve dispatch ambiguity: SimpleCompressor is a subtype of both Compressor (matched by
# the ResourcePressure dispatch above) and the existing CompoundResource dispatch. Julia
# requires an explicit, more-specific method to break the tie.
function constraints_pressure_couple(
    m,
    n::SimpleCompressor,
    ℒ::Vector{<:EMB.Link},
    𝒯,
    𝒫::Vector{<:ResourcePressure},
)
    𝒫ⁿ_in  = EMB.inputs(n)
    𝒫ⁿ_out = EMB.outputs(n)
    P      = setdiff(𝒫ⁿ_in, 𝒫ⁿ_out)

    ℒᶠʳᵒᵐ, ℒᵗᵒ = EMB.link_sub(ℒ, n)
    ℒᵗᵒ = filter(l -> any(r -> r isa ResourcePressure, EMB.inputs(l)), ℒᵗᵒ)
    ℒᶠʳᵒᵐ = filter(l -> any(r -> r isa ResourcePressure, EMB.inputs(l)), ℒᶠʳᵒᵐ)

    @constraint(m, [l_to ∈ ℒᵗᵒ, t ∈ 𝒯, p ∈ [pp for pp ∈ 𝒫ⁿ_in if pp in inputs(l_to)]],
        m[:potential_in][n, t, p] <=
        m[:link_potential_out][l_to, t, p] + 1e4 * (1 - m[:has_flow][l_to, t]))

    @constraint(m, [t ∈ 𝒯, p ∈ setdiff(𝒫ⁿ_in, P)],
        m[:potential_out][n, t, p] == m[:potential_in][n, t, p] + m[:potential_Δ][n, t])

    @constraint(m, [t ∈ 𝒯],
        m[:potential_Δ][n, t] <= get_max_potential(n, t))

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

    # Get links from and to `n`, restricted to pressure-carrying links
    ℒᶠʳᵒᵐ, ℒᵗᵒ = EMB.link_sub(ℒ, n)
    ℒᵗᵒ = filter(l -> any(r -> r isa CompoundResource, EMB.inputs(l)), ℒᵗᵒ)
    ℒᶠʳᵒᵐ = filter(l -> any(r -> r isa CompoundResource, EMB.inputs(l)), ℒᶠʳᵒᵐ)

    # Outlet potential of `l` and Inlet Potential of `n`
    @constraint(m, [l_to ∈ ℒᵗᵒ, t ∈ 𝒯, p ∈ [pp for pp ∈ 𝒫ⁿ_in if pp in inputs(l_to)]],
        m[:potential_in][n, t, p] <=
        m[:link_potential_out][l_to, t, p] + 1e4 * (1 - m[:has_flow][l_to, t]))

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
    n::DiscretizedPoolingNode,
    ℒ::Vector{<:EMB.Link},
    𝒯,
    𝒫::Vector{<:CompoundResource},
)
    # Filter resources CompoundResource that are inputs and outputs of `n`
    𝒫ⁿ_in = filter(p -> p ∈ EMB.inputs(n), 𝒫)
    𝒫ⁿ_out = filter(p -> p ∈ EMB.outputs(n), 𝒫)

    # Get links from and to `n`, restricted to pressure-carrying links
    ℒᶠʳᵒᵐ, ℒᵗᵒ = EMB.link_sub(ℒ, n)
    ℒᵗᵒ = filter(l -> any(r -> r isa CompoundResource, EMB.inputs(l)), ℒᵗᵒ)
    ℒᶠʳᵒᵐ = filter(l -> any(r -> r isa CompoundResource, EMB.inputs(l)), ℒᶠʳᵒᵐ)

    # Outlet potential of `l` and Inlet Potential of `n`
    @constraint(m, [l_to ∈ ℒᵗᵒ, t ∈ 𝒯, p ∈ [pp for pp ∈ 𝒫ⁿ_in if pp in inputs(l_to)]],
        m[:potential_in][n, t, p] <=
        m[:link_potential_out][l_to, t, p] + 1e4 * (1 - m[:has_flow][l_to, t]))

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

    # Get links to `n`, restricted to pressure-carrying links
    _, ℒᵗᵒ = EMB.link_sub(ℒ, n)
    ℒᵗᵒ = filter(l -> any(r -> r isa CompoundResource, EMB.inputs(l)), ℒᵗᵒ)

    # Outlet potential of `l` and Inlet Potential of `n`
    @constraint(m, [l_to ∈ ℒᵗᵒ, t ∈ 𝒯, p ∈ [pp for pp ∈ 𝒫ⁿ if pp in inputs(l_to)]],
        m[:potential_in][n, t, p] <=
        m[:link_potential_out][l_to, t, p] + 1e4 * (1 - m[:has_flow][l_to, t]))
end
function constraints_pressure_couple(m, n::EMB.AbstractElement, ℒ, 𝒯, 𝒫) end

"""
    _maximum_link_capacity(m, l, 𝒯)

Return a finite upper bound on the installed capacity of link `l`, or `nothing`.

Investment links use the upper bounds on `link_cap_current`. Fixed-capacity links use fixed
values or upper bounds on `link_cap_inst`. The physical capacity is the final fallback.
"""
function _maximum_link_capacity(m, l, 𝒯)
    if haskey(m, :link_cap_current) && l ∈ axes(m[:link_cap_current], 1)
        bounds = [
            has_upper_bound(m[:link_cap_current][l, t_inv]) ?
            upper_bound(m[:link_cap_current][l, t_inv]) : Inf for
            t_inv ∈ axes(m[:link_cap_current], 2)
        ]
        return all(isfinite, bounds) ? maximum(bounds) : nothing
    end

    if haskey(m, :link_cap_inst) && l ∈ axes(m[:link_cap_inst], 1)
        bounds = [
            is_fixed(m[:link_cap_inst][l, t]) ? fix_value(m[:link_cap_inst][l, t]) :
            has_upper_bound(m[:link_cap_inst][l, t]) ?
            upper_bound(m[:link_cap_inst][l, t]) : Inf for
            t ∈ axes(m[:link_cap_inst], 2)
        ]
        all(isfinite, bounds) && return maximum(bounds)
    end

    capacities = [EMB.capacity(l, t) for t ∈ 𝒯]
    return all(isfinite, capacities) ? maximum(capacities) : nothing
end

"""
    _maximum_node_capacity(m, n, 𝒯)

Return a finite upper bound on the installed capacity of node `n`, or `nothing`.

Same logic as [`_maximum_link_capacity`](@ref), using `cap_current` (investments) and
`cap_inst`.
"""
function _maximum_node_capacity(m, n, 𝒯)
    if haskey(m, :cap_current) && n ∈ axes(m[:cap_current], 1)
        bounds = [
            has_upper_bound(m[:cap_current][n, t_inv]) ?
            upper_bound(m[:cap_current][n, t_inv]) : Inf for
            t_inv ∈ axes(m[:cap_current], 2)
        ]
        return all(isfinite, bounds) ? maximum(bounds) : nothing
    end

    if haskey(m, :cap_inst) && n ∈ axes(m[:cap_inst], 1)
        bounds = [
            is_fixed(m[:cap_inst][n, t]) ? fix_value(m[:cap_inst][n, t]) :
            has_upper_bound(m[:cap_inst][n, t]) ?
            upper_bound(m[:cap_inst][n, t]) : Inf for
            t ∈ axes(m[:cap_inst], 2)
        ]
        all(isfinite, bounds) && return maximum(bounds)
    end

    capacities = [EMB.capacity(n, t) for t ∈ 𝒯]
    return all(isfinite, capacities) ? maximum(capacities) : nothing
end

"""
    constraints_flow_capacity(m, l::EMB.Link, 𝒯, 𝒫::Vector{<:CompoundResource})

Limit flow to the installed capacity and deactivate it when `has_flow[l, t]` is zero.

The installed-capacity constraint remains time-dependent. The `has_flow` constraint uses a
finite upper bound on the maximum installed capacity as its big-M. If no finite bound exists,
the constraint can only be omitted when `PressureLinkData` is present. Taylor cuts then
force zero flow at zero potentials, and `constraints_flow_pressure` adds a PWA-derived
big-M for blend links.
"""
function constraints_flow_capacity(m, l::EMB.Link, 𝒯, 𝒫::Vector{<:CompoundResource})
    max_capacity = _maximum_link_capacity(m, l, 𝒯)
    if isnothing(max_capacity)
        pressure_deactivation =
            !(l isa EMB.Direct) && !(l isa ZeroDrop) &&
            any(data -> data isa PressureLinkData, EMB.element_data(l))
        if !pressure_deactivation
            error(
                "Cannot derive a finite flow big-M for $l. Provide a finite maximum " *
                "installed capacity, a finite physical capacity, or PressureLinkData " *
                "with Weymouth/PWA flow constraints.",
            )
        end
        return
    end
    @constraint(
        m, [t ∈ 𝒯, p ∈ 𝒫],
        m[:link_in][l, t, p] <= max_capacity * m[:has_flow][l, t])
end

"""
    _constraints_flow_pressure_taylor(m, l, 𝒯, 𝒫, pressure_data)

Add first-order Taylor linearisation cuts of the Weymouth equation for link `l`.

Generates 149 linearisation points along the pressure envelope defined by `pressure_data`
(from `PIn` down to `POut`) and adds one constraint per point, per time period, and per
resource in `𝒫`:

    link_in[l,t,p] ≤ √W · [∂f/∂p_in · link_potential_in[l,t,p] + ∂f/∂p_out · link_potential_out[l,t,p]]

where `W` is the Weymouth constant and the partial-derivative coefficients are evaluated at
each linearisation point. Called by [`constraints_flow_pressure`](@ref) for
[`ResourcePressure`](@ref) links and as a fallback for blend links without
[`BlendData`](@ref).
"""
function _constraints_flow_pressure_taylor(m, l, 𝒯, 𝒫, pressure_data)
    weymouth_ct = get_weymouth(pressure_data)
    POut, PIn = potential_data(pressure_data)
    pressures_points = [(PIn, p) for p ∈ range(PIn, POut, length = 150)[2:end]]
    for (p_in, p_out) ∈ pressures_points
        @constraint(m, [t ∈ 𝒯, p ∈ 𝒫],
            m[:link_in][l, t, p] <=
            sqrt(weymouth_ct) * (
                (p_in / (sqrt(p_in^2 - p_out^2))) * m[:link_potential_in][l, t, p] -
                (p_out / (sqrt(p_in^2 - p_out^2))) * m[:link_potential_out][l, t, p]
            ))
    end
end
"""
    constraints_flow_pressure(m, l::EMB.Link, 𝒯, 𝒫::Vector{<:ResourcePressure})
    constraints_flow_pressure(m, l::EMB.Link, 𝒯, 𝒫::Vector{<:ResourcePooling{<:ResourcePressure}})
    constraints_flow_pressure(m, l::EMB.Link, 𝒯, 𝒫::Vector{<:Resource})
    constraints_flow_pressure(m, l::EMB.Direct, 𝒯, 𝒫::Vector)

Set Weymouth constraints in link `l`, calculating the flow based on the pressure difference
between inlet and outlet.

The Weymouth equation is approximated using the first-order Taylor expansion when the
resource is a [`ResourcePressure`](@ref). For a [`ResourcePooling`](@ref) of
`ResourcePressure` sub-resources (blend links), a Piecewise Affine Approximation (PWA) in `(p_in, p_out, proportion_H2)` is
used when a `BlendData` object is attached to the link. If no `BlendData` is present — for
example when `blend: nothing` is set in YAML for a link that still carries a blend resource
due to its node types — the function falls back to the 2D Taylor approximation at the
reference (pure-component) composition encoded in [`PressureLinkData`](@ref). This fallback
is conservative: it uses the capacity at zero H₂ fraction, which is the minimum possible
capacity (since adding H₂ lightens the gas and increases throughput).

No-op methods are defined for `EMB.Direct` links and plain `Resource` vectors where no
Weymouth constraint is needed.
"""
function constraints_flow_pressure(
    m,
    l::EMB.Link,
    𝒯,
    𝒫::Vector{<:ResourcePressure},
)
    pressure_data_list = filter(data -> data isa PressureLinkData, l.data)
    isempty(pressure_data_list) && return  # no Weymouth data → pure capacity limit, skip
    @info "Taylor Approximation for $l"
    pressure_data = first(pressure_data_list)
    _constraints_flow_pressure_taylor(m, l, 𝒯, 𝒫, pressure_data)
end
function constraints_flow_pressure(
    m,
    l::EMB.Link,
    𝒯,
    𝒫::Vector{<:ResourcePooling{<:ResourcePressure}},
)
    # Extract PressureLinkData from link `l`; skip if absent (pure capacity mode)
    pressure_data_list = filter(data -> data isa PressureLinkData, l.data)
    isempty(pressure_data_list) && return

    pressure_data = first(pressure_data_list)

    # Fall back to 2D Taylor when no BlendData is present (e.g., blend:nothing in YAML for a
    # link that still carries a blend resource because of its node types). This is conservative:
    # the pure-component (zero H2) capacity is the minimum, so the bound is never violated.
    blend_data_list = filter(data -> data isa BlendData, l.data)
    if isempty(blend_data_list)
        @info "Taylor Approximation (no blend data) for $l"
        _constraints_flow_pressure_taylor(m, l, 𝒯, 𝒫, pressure_data)
        return
    end

    blend_data = first(blend_data_list)

    p_blend = get_blendres(blend_data)
    p_track = get_trackres(blend_data)

    @info "PWA for $l"
    # The PWA optimizer is only needed here; the Taylor fallback above does not fit a PWA.
    pwa = get_pwa(pressure_data, blend_data, _get_optimizer())
    for (k, plane) ∈ enumerate(pwa.planes)
        constraints_pwa(m, l, p_blend, p_track, 𝒯, plane, pwa)
    end

    # Without a capacity bound, `constraints_flow_capacity` adds no `has_flow` switch. The
    # PWA does not shut off flow by itself: at zero potentials each plane still allows
    # `link_in ≤ -α₃·prop - β`. Use the PWA's own maximum as the big-M instead.
    if isnothing(_maximum_link_capacity(m, l, 𝒯))
        M = _pwa_flow_bound(pwa)
        @constraint(m, [t ∈ 𝒯], m[:link_in][l, t, p_blend] <= M * m[:has_flow][l, t])
    end
end

"""
    _pwa_flow_bound(pwa::PWAFunc)

Return a finite upper bound on the flow allowed by the concave PWA `pwa` over the box
`p_in, p_out ∈ [0, 1e4]` (the big-M bound on link potentials in
`constraints_balance_pressure`) and `proportion ∈ [0, 1]`.

Each plane `k` gives `z ≤ -α_k⋅x - β_k`. The maximum of an affine function over a box lies
at a corner, and the PWA lies below every plane, so `min_k max_corners (-α_k⋅x - β_k)` is
a valid bound.
"""
function _pwa_flow_bound(pwa::PWAFunc)
    corners =
        [(p_in, p_out, prop) for p_in ∈ (0.0, 1e4), p_out ∈ (0.0, 1e4), prop ∈ (0.0, 1.0)]
    M = minimum(
        maximum(-sum(plane.α .* x) - plane.β for x ∈ corners) for plane ∈ pwa.planes
    )
    return max(M, 0.0)
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
# ZeroDrop: zero-drop pipeline, no Weymouth constraint for any resource type
function constraints_flow_pressure(m, l::ZeroDrop, 𝒯, 𝒫::Vector{<:ResourcePressure}) end
function constraints_flow_pressure(
    m,
    l::ZeroDrop,
    𝒯,
    𝒫::Vector{<:ResourcePooling{<:ResourcePressure}},
) end
function constraints_flow_pressure(m, l::ZeroDrop, 𝒯, 𝒫::Vector{<:Resource}) end

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
    # The node whose share equals the composition in the link, see `blend_share_plan`
    n = m.ext[:emgn_blend_plan].pwa_reader[(l, p_blend)]
    for t ∈ 𝒯
        PiecewiseAffineApprox.constr(
            C1,
            m,
            m[:link_in][l, t, p_blend],
            plane,
            (
                m[:link_potential_in][l, t, p_blend],
                m[:link_potential_out][l, t, p_blend],
                m[:proportion_out][n, t, p_track],
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
"""
    constraints_energy_potential(m, n::FlowPressureCompressor, 𝒯, 𝒫, modeltype::EMB.EnergyModel)

For a `FlowPressureCompressor`, the energy input must cover both the flow-dependent and the
pressure-dependent components of compression work:

    flow_in[n, t, PowerRes] ≥ flow_weight(n, t) × cap_use[n, t]
                              + pressure_weight(n, t) × potential_Δ[n, t]

The energy resource `PowerRes` is identified as the input resource that is NOT in the gas
outputs (i.e., `setdiff(inputs(n), outputs(n))`), exactly as in `SimpleCompressor`.
"""
function constraints_energy_potential(
    m,
    n::FlowPressureCompressor,
    𝒯,
    𝒫,
    modeltype::EMB.EnergyModel,
)
    𝒫ⁿ_in = EMB.inputs(n)
    𝒫ⁿ_out = EMB.outputs(n)
    P = setdiff(𝒫ⁿ_in, 𝒫ⁿ_out)

    @constraint(m, [t ∈ 𝒯, p ∈ P],
        m[:flow_in][n, t, p] >=
        flow_weight(n, t) * m[:cap_use][n, t] +
        pressure_weight(n, t) * m[:potential_Δ][n, t])
end
function constraints_energy_potential(m, n::EMB.Node, 𝒯, 𝒫, modeltype::EMB.EnergyModel) end

""""
    constraints_bidirectional_pressure(m, l::EMB.Link, ℒ, 𝒯, 𝒫)
    constraints_bidirectional_pressure(m, l::EMB.Direct, ℒ, 𝒯, 𝒫)

Ensure that parallel links defining bidirectionality cannot have flow at the same time. The link without flow will automatically have zero 
link_in_potential and link_out_potential due to the `constraints_balance_pressure` constraints.
"""
function constraints_bidirectional_pressure(m, l::EMB.Link, ℒ::Vector{<:EMB.Link}, 𝒯, 𝒫)
    # `has_flow` only exists for links carrying a `CompoundResource`
    ℒ_pressure = axes(m[:has_flow], 1)
    l ∈ ℒ_pressure || return
    ℒᵇ = filter(ll -> (ll.from == l.to && ll.to == l.from && ll ∈ ℒ_pressure), ℒ)

    @constraint(m, [ll ∈ ℒᵇ, t ∈ 𝒯],
        m[:has_flow][ll, t] + m[:has_flow][l, t] <= 1)
end
function constraints_bidirectional_pressure(m, l::EMB.Direct, ℒ::Vector{<:EMB.Link}, 𝒯, 𝒫) end

# --- TransitNode pressure coupling and balance ---
# TransitNode is semantically a pass-through junction: no injection, no extraction.
# The pressure coupling and balance constraints are identical to PoolingNode.

"""
    constraints_pressure_couple(m, n::TransitNode, ℒ, 𝒯, 𝒫::Vector{<:CompoundResource})

Couple inlet/outlet potentials of links to the `potential_in`/`potential_out` of a
`TransitNode`. Uses `has_flow` big-M for both upper and lower bounds, coupling each
active link's outlet potential to the node inlet potential.
"""
function constraints_pressure_couple(
    m,
    n::TransitNode,
    ℒ::Vector{<:EMB.Link},
    𝒯,
    𝒫::Vector{<:CompoundResource},
)
    # Filter resources CompoundResource that are inputs and outputs of `n`
    𝒫ⁿ_in = filter(p -> p ∈ EMB.inputs(n), 𝒫)
    𝒫ⁿ_out = filter(p -> p ∈ EMB.outputs(n), 𝒫)

    # Get links from and to `n`, restricted to pressure-carrying links
    ℒᶠʳᵒᵐ, ℒᵗᵒ = EMB.link_sub(ℒ, n)
    ℒᵗᵒ = filter(l -> any(r -> r isa CompoundResource, EMB.inputs(l)), ℒᵗᵒ)
    ℒᶠʳᵒᵐ = filter(l -> any(r -> r isa CompoundResource, EMB.inputs(l)), ℒᶠʳᵒᵐ)

    # Outlet potential of `l` and Inlet Potential of `n`
    @constraint(m, [l_to ∈ ℒᵗᵒ, t ∈ 𝒯, p ∈ [pp for pp ∈ 𝒫ⁿ_in if pp in inputs(l_to)]],
        m[:potential_in][n, t, p] <=
        m[:link_potential_out][l_to, t, p] + 1e4 * (1 - m[:has_flow][l_to, t]))

    # Outlet potential of `n` and Inlet Potential of `l`
    @constraint(m, [l_from ∈ ℒᶠʳᵒᵐ, t ∈ 𝒯, p ∈ inputs(l_from), pp ∈ 𝒫ⁿ_out],
        m[:link_potential_in][l_from, t, p] <=
        m[:potential_out][n, t, pp] + 1e4 * (1 - m[:has_flow][l_from, t]))

    @constraint(m, [l_from ∈ ℒᶠʳᵒᵐ, t ∈ 𝒯, p ∈ inputs(l_from), pp ∈ 𝒫ⁿ_out],
        m[:link_potential_in][l_from, t, p] >=
        m[:potential_out][n, t, pp] - 1e4 * (1 - m[:has_flow][l_from, t]))
end

# --- TransitNode pressure balance ---
# Identical semantics to PoolingNode: all incoming resource potentials bound the output
# from above (>=). This ensures that the corridor junction output pressure cannot exceed
# the minimum of the incoming pipeline delivery pressure and composition-tracking potentials.

function constraints_balance_pressure(m, n::TransitNode, 𝒯, 𝒫::Vector{<:ResourcePressure})
    𝒫ⁱⁿ  = filter(p -> p ∈ EMB.inputs(n), 𝒫)
    𝒫ᵒᵘᵗ = EMB.outputs(n)
    @constraint(m, [t ∈ 𝒯, p_in ∈ 𝒫ⁱⁿ, p_out ∈ 𝒫ᵒᵘᵗ],
        m[:potential_in][n, t, p_in] >= m[:potential_out][n, t, p_out])
end

function constraints_balance_pressure(
    m,
    n::TransitNode,
    𝒯,
    𝒫::Vector{<:ResourcePooling{<:ResourcePressure}},
)
    𝒫ⁱⁿ  = filter(p -> p ∈ EMB.inputs(n), 𝒫)
    𝒫ᵒᵘᵗ = filter(p -> p ∈ EMB.outputs(n), 𝒫)
    (isempty(𝒫ⁱⁿ) || isempty(𝒫ᵒᵘᵗ)) && return
    @constraint(m, [t ∈ 𝒯, p_in ∈ 𝒫ⁱⁿ, p_out ∈ 𝒫ᵒᵘᵗ],
        m[:potential_in][n, t, p_in] >= m[:potential_out][n, t, p_out])
end
