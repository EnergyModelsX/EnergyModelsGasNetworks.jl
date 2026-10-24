""" 
    EMB.variables_node(m, 𝒩ᶜ::Vector{<:Compressor}, 𝒯, modeltype::EMB.EnergyModel)

When the node vector is a `Vector{<:Compressor}` the potential increase (`potential_Δ`) variables are created for each compressor and timestep.
"""
function EMB.variables_node(m, 𝒩ᶜ::Vector{<:Compressor}, 𝒯, modeltype::EnergyModel)
    @variable(m, potential_Δ[𝒩ᶜ, 𝒯] >= 0)
end

"""
    EMB.variables_flow_resource(m, 𝒩::Vector{<:EMB.Node}, 𝒫::Vector{<:ResourcePressure}, 𝒯, modeltype::EMB.EnergyModel)

Define the potential variables `potential_in` and `potential_out` of the nodes if the system
has `ResourcePressure`s. The blend composition variables `proportion_out` are created
together with the link variables, as they depend on the network topology.
"""
function EMB.variables_flow_resource(
    m,
    𝒩::Vector{<:EMB.Node},
    𝒫::Vector{<:ResourcePressure},
    𝒯,
    modeltype::EMB.EnergyModel,
)
    @variable(m, potential_in[n ∈ 𝒩, 𝒯, EMB.inputs(n)] >= 0)
    @variable(m, potential_out[n ∈ 𝒩, 𝒯, EMB.outputs(n)] >= 0)
end
"""
    EMB.variables_flow_resource(m, ℒ::Vector{<:EMB.Link}, 𝒫::Vector{<:ResourcePressure}, 𝒯, modeltype::EnergyModel)
    EMB.variables_flow_resource(m, ℒ::Vector{<:EMB.Link}, 𝒫::Vector{<:ResourcePooling}, 𝒯, modeltype::EnergyModel)

Define additional pressure-related variables for links if there are `ResourcePressure` in the system.
For `ResourcePooling` blends, define `flow_component` variables on each blend-carrying link.

For the `ResourcePooling` dispatch, `proportion_out[n, t, p]` is also created for the nodes
that track the blend composition explicitly, see [`blend_share_plan`](@ref).

For the `ResourcePressure` dispatch, the following variables are created:

- `link_potential_in[l ∈ ℒ, 𝒯, inputs(l.to)]` — inlet potential for each link (all links, all resources of the destination node).
- `link_potential_out[l ∈ ℒ, 𝒯, outputs(l.from)]` — outlet potential for each link (all links, all resources of the source node).
- `has_flow[l ∈ ℒ_pressure, 𝒯]` — binary; equals 1 when a link is active (carrying flow). Used as a big-M switch in pressure-balance and capacity constraints to deactivate idle links. Note: `has_flow = 1` is not sufficient to guarantee actual flow — it is only a necessary condition.
The binary variable is declared only for `ℒ_pressure` — the subset of links carrying at least one `CompoundResource` (`ResourcePressure` or `ResourcePooling{<:ResourcePressure}`). Links that carry only non-pressure resources such as `ResourceCarrier` (e.g., Power) do not require pressure binaries and are excluded to keep the MINLP compact.
"""
function EMB.variables_flow_resource(
    m,
    ℒ::Vector{<:EMB.Link},
    𝒫::Vector{<:ResourcePressure},
    𝒯,
    modeltype::EnergyModel,
)
    # Create the link potential variables
    @variable(m, link_potential_in[l ∈ ℒ, 𝒯, EMB.inputs(l.to)] >= 0)
    @variable(m, link_potential_out[l ∈ ℒ, 𝒯, EMB.outputs(l.from)] >= 0)

    # Add link binary variables — only for links that carry at least one pressure resource.
    # Power-only links (e.g., Power_to_Compressor, ConversionToDunkerque) never appear in
    # any pressure constraint, so allocating binaries for them is pure overhead.
    ℒ_pressure = filter(l -> any(r -> r isa CompoundResource, EMB.link_res(l)), ℒ)
    @variable(m, has_flow[l ∈ ℒ_pressure, 𝒯], Bin) # auxiliary binary that ensures that all links with flow take value 1, it can take value 1 without flow as well. Careful with this detail, it cannot be used to check actual flows.
end

function EMB.variables_flow_resource(
    m,
    ℒ::Vector{<:EMB.Link},
    𝒫::Vector{<:ResourcePooling},
    𝒯,
    modeltype::EnergyModel,
)
    # Get the unique subresources across all blend resources
    𝒫ˢᵘᵇ = unique([r for blend ∈ 𝒫 for r ∈ subresources(blend)])

    # Filter to links that carry at least one ResourcePooling resource
    ℒ_blend = filter(l -> any(p -> p isa ResourcePooling, EMB.link_res(l)), ℒ)

    @variable(m, 0 <= flow_component[ℒ_blend, 𝒯, 𝒫ˢᵘᵇ])

    # Only the nodes selected by `blend_share_plan` track the composition explicitly. The
    # plan needs the topology, hence it is made here and not with the node variables. The
    # link constraints (PWA) and the coupling constraints use it.
    𝒩 = unique(EMB.Node[n for l ∈ ℒ_blend for n ∈ (l.from, l.to)])
    plan = blend_share_plan(𝒩, ℒ, 𝒫)
    m.ext[:emgn_blend_plan] = plan
    @variable(m, 0.0 <= proportion_out[plan.share_nodes, 𝒯, 𝒫ˢᵘᵇ] <= 1.0)
end

""" 
    EMB.constraints_resource(m, n::EMB.Node, 𝒯, 𝒫::Vector{:ResourcePressure}, modeltype::EMB.EnergyModel)
    EMB.constraints_resource(m, n::EMB.Node, 𝒯, 𝒫::Vector{:ResourcePooling{Any}}, modeltype::EMB.EnergyModel)  
    EMB.constraints_resource(m, n::EMB.Node, 𝒯, 𝒫::Vector{:ResourcePooling{ResourcePressure}}, modeltype::EMB.EnergyModel)

Add blending and/or pressure related constraints to node `n` based on specific resource types.
- If 𝒫::Vector{<:ResourcePressure} then it adds only pressure related constraints
- If 𝒫::Vector{<:ResourcePooling{Any}} then it adds only blending related constraints
- If 𝒫::Vector{<:ResourcePooling{ResourcePressure}} then it adds both pressure and blending related constraints

Note! The blending constraints for nodes require ℒ:Vector{<:EMB.Link} to be passed as argument. Thus, all of them are 
defined in `constraints_couple_resource()` functions.
"""
function EMB.constraints_resource(
    m,
    n::EMB.Node,
    𝒯,
    𝒫::Vector{<:ResourcePressure},
    modeltype::EMB.EnergyModel,
)
    # Define internal pressure balance constraints
    constraints_balance_pressure(m, n, 𝒯, 𝒫)

    # Get AbstractPressureData and generate limit constraints if any
    constraints_pressure_bounds_element(m, n, 𝒯, 𝒫)

    # Define energy-increase potential relationship constraints for type `Compressor`
    constraints_energy_potential(m, n, 𝒯, 𝒫, modeltype)
end
function EMB.constraints_resource(
    m,
    n::EMB.Node,
    𝒯,
    𝒫::Vector{<:ResourcePooling},
    modeltype::EMB.EnergyModel,
) end
function EMB.constraints_resource(
    m,
    n::EMB.Node,
    𝒯,
    𝒫::Vector{<:ResourcePooling{<:ResourcePressure}},
    modeltype::EMB.EnergyModel,
)
    # Add pressure and blending constraints
    constraints_balance_pressure(m, n, 𝒯, 𝒫)

    # Get AbstractPressureData and generate limit constraints if any
    constraints_pressure_bounds_element(m, n, 𝒯, 𝒫)

    # Define energy-increase potential relationship constraints for type `Compressor`
    constraints_energy_potential(m, n, 𝒯, 𝒫, modeltype)
end

""" 
    EMB.constraints_resource(m, l::EMB.Link, 𝒯, 𝒫::Vector{<:ResourcePressure}, modeltype::EMB.EnergyModel)
    EMB.constraints_resource(m, l::EMB.Link, 𝒯, 𝒫::Vector{<:ResourcePooling{Any}}, modeltype::EMB.EnergyModel)  
    EMB.constraints_resource(m, l::EMB.Link, 𝒯, 𝒫::Vector{<:ResourcePooling{ResourcePressure}}, modeltype::EMB.EnergyModel)

Add blending and/or pressure related constraints to node `l` based on specific resource types transported through `l``.
- If 𝒫::Vector{<:ResourcePressure} then it adds only pressure related constraints
- If 𝒫::Vector{<:ResourcePooling{Any}} then it adds only blending related constraints
- If 𝒫::Vector{<:ResourcePooling{ResourcePressure}} then it adds both pressure and blending related constraints

Note! The blending constraints for nodes require ℒ:Vector{<:EMB.Link} to be passed as argument. Thus, all of them are 
defined in `constraints_couple_resource()` functions.
"""
function EMB.constraints_resource(
    m,
    l::EMB.Link,
    𝒯,
    𝒫::Vector{<:ResourcePressure},
    modeltype::EMB.EnergyModel,
)
    # Define internal pressure balance constraints
    constraints_balance_pressure(m, l, 𝒯, 𝒫)

    # Get AbstractPressureData and generate pressure bounds constraints, if any
    constraints_pressure_bounds_element(m, l, 𝒯, 𝒫)

    # Define capacity limit constraints
    constraints_flow_capacity(m, l, 𝒯, 𝒫)

    # Define weymouth flow-pressure constraints based on the resources flowing into the link.
    constraints_flow_pressure(m, l, 𝒯, 𝒫)
end
function EMB.constraints_resource(
    m,
    l::EMB.Link,
    𝒯,
    𝒫::Vector{<:ResourcePooling},
    modeltype::EMB.EnergyModel,
) end
function EMB.constraints_resource(
    m,
    l::EMB.Link,
    𝒯,
    𝒫::Vector{<:ResourcePooling{<:ResourcePressure}},
    modeltype::EMB.EnergyModel,
)

    # Add pressure and blending constraints
    constraints_balance_pressure(m, l, 𝒯, 𝒫)

    # Get AbstractPressureData and generate limit constraints if any
    constraints_pressure_bounds_element(m, l, 𝒯, 𝒫)

    # Define capacity limit constraints
    constraints_flow_capacity(m, l, 𝒯, 𝒫)

    # Define weymouth flow-pressure constraints based on the resources flowing into the link.
    constraints_flow_pressure(m, l, 𝒯, 𝒫)
end

"""
    EMB.constraints_couple_resource(m, 𝒩::Vector{<:EMB.Node}, ℒ::Vector{<:EMB.Link}, 𝒫::Vector{<:ResourcePressure}, 𝒯, modeltype::EMB.EnergyModel)
    EMB.constraints_couple_resource(m, 𝒩::Vector{<:EMB.Node}, ℒ::Vector{<:EMB.Link}, 𝒫::Vector{<:ResourcePooling{Any}}, 𝒯, modeltype::EMB.EnergyModel)
    EMB.constraints_couple_resource(m, 𝒩::Vector{<:EMB.Node}, ℒ::Vector{<:EMB.Link}, 𝒫::Vector{<:ResourcePooling{ResourcePressure}}, 𝒯, modeltype::EMB.EnergyModel)

Add blending and/or pressure related coupling constraints between nodes and links based on specific resource types.
"""
function EMB.constraints_couple_resource(
    m,
    𝒩::Vector{<:EMB.Node},
    ℒ::Vector{<:EMB.Link},
    𝒫::Vector{<:ResourcePressure},
    𝒯,
    modeltype::EMB.EnergyModel,
)
    for n ∈ 𝒩
        constraints_pressure_couple(m, n, ℒ, 𝒯, 𝒫)
    end

    for l ∈ ℒ
        constraints_bidirectional_pressure(m, l, ℒ, 𝒯, 𝒫)
    end
end
function EMB.constraints_couple_resource(
    m,
    𝒩::Vector{<:EMB.Node},
    ℒ::Vector{<:EMB.Link},
    𝒫::Vector{<:ResourcePooling},
    𝒯,
    modeltype::EMB.EnergyModel,
)
    constraints_component_blend(m, 𝒩, ℒ, 𝒯, 𝒫)
end
function EMB.constraints_couple_resource(
    m,
    𝒩::Vector{<:EMB.Node},
    ℒ::Vector{<:EMB.Link},
    𝒫::Vector{<:ResourcePooling{<:ResourcePressure}},
    𝒯,
    modeltype::EMB.EnergyModel,
)
    for n ∈ 𝒩
        constraints_pressure_couple(m, n, ℒ, 𝒯, 𝒫)
    end

    # Set blending couple constraints
    constraints_component_blend(m, 𝒩, ℒ, 𝒯, 𝒫)

    for l ∈ ℒ
        constraints_bidirectional_pressure(m, l, ℒ, 𝒯, 𝒫)
    end
end

"""
    EMB.create_link(m, l::ZeroDrop, 𝒯, 𝒫, modeltype::EMB.EnergyModel)

Dispatched function for setting the flow-balance constraints for a `ZeroDrop` link.

`ZeroDrop` is a zero-pressure-drop pipeline: outlet flow equals inlet flow for every
resource.  It is declared as `<: EMB.Link` (not `<: EMB.Direct`) so that the
bidirectional mutual-exclusion constraint in `constraints_bidirectional_pressure` still
applies when two anti-parallel `ZeroDrop` links model a reversible pipeline.
"""
function EMB.create_link(m, l::ZeroDrop, 𝒯, 𝒫, modeltype::EMB.EnergyModel)
    @constraint(m, [t ∈ 𝒯, p ∈ EMB.link_res(l)],
        m[:link_out][l, t, p] == m[:link_in][l, t, p]
    )
end

"""
    EMB.create_link(m, l::CapDirect, 𝒯, 𝒫::Vector{<:CompoundResource}, modeltype::EMB.EnergyModel) 

Dispatched function for setting the constraints for a link of type `CapDirect`.
"""
function EMB.create_link(m, l::CapDirect, 𝒯, 𝒫, modeltype::EMB.EnergyModel)
    # Generic link in which each output corresponds to the input
    @constraint(m, [t ∈ 𝒯, p ∈ EMB.link_res(l)],
        m[:link_out][l, t, p] == m[:link_in][l, t, p]
    )

    EMB.constraints_capacity(m, l, 𝒯, modeltype)

    if has_capacity(l)
        EMB.constraints_capacity_installed(m, l, 𝒯, modeltype) # calls the function in EMB
    end
end
