"""
    EMB.constraints_capacity(m, l::CapDirect, 𝒯, modeltype::EMB.EnergyModel)

Function for creating the constraints on the maximum capacity of a link `CapDirect`.
"""
function EMB.constraints_capacity(m, l::CapDirect, 𝒯, modeltype::EMB.EnergyModel)
    @constraint(m, [t ∈ 𝒯, p ∈ EMB.link_res(l)],
        m[:link_in][l, t, p] <= m[:link_cap_inst][l, t]
    )
end

"""
    EMB.constraints_capacity(m, n::UnitConversion, 𝒯, modeltype::EMB.EnergyModel)

Remove the capacity constraints for UnitConversion nodes. These nodes do not have :cap_use.
"""
function EMB.constraints_capacity(
    m,
    n::UnitConversion,
    𝒯::TimeStructure,
    modeltype::EMB.EnergyModel,
) end

"""
    EMB.constraints_opex_var(m, n::UnitConversion, 𝒯, modeltype::EMB.EnergyModel)

Remove the opex variable constraints for UnitConversion nodes.
"""
function EMB.constraints_opex_var(m, n::UnitConversion, 𝒯ᴵⁿᵛ, modeltype::EMB.EnergyModel) end

"""
    EMB.constraints_opex_fixed(m, n::UnitConversion, 𝒯, modeltype::EMB.EnergyModel)

Remove the opex fixed constraints for UnitConversion nodes.
"""
function EMB.constraints_opex_fixed(m, n::UnitConversion, 𝒯ᴵⁿᵛ, modeltype::EMB.EnergyModel) end

"""
    EMB.constraints_flow_in(m, n::PoolingNode, 𝒯::TimeStructure, modeltype::EMB.EnergyModel)

Function for creating the constraint on the inlet flow of a `PoolingNode`. The sum of the flows
from all input links must be equal to the used capacity of the node. It differs from generic
nodes in that it is not defined as a proportion of the :input and :output fields.
"""
function EMB.constraints_flow_in(
    m,
    n::PoolingNode,
    𝒯::TimeStructure,
    modeltype::EMB.EnergyModel,
)
    # Declaration of the required subsets
    𝒫ⁱⁿ = EMB.inputs(n)

    # Constraint for the individual input stream connections
    @constraint(m, [t ∈ 𝒯],
        sum(m[:flow_in][n, t, p] for p ∈ 𝒫ⁱⁿ) == m[:cap_use][n, t]
    )
end

"""
    EMB.constraints_flow_in(m, n::DiscretizedPoolingNode, 𝒯::TimeStructure, modeltype::EMB.EnergyModel)

Same as `PoolingNode`: the sum of all input flows equals the used capacity of the node.
`DiscretizedPoolingNode` accepts mixed resource inputs (e.g. CH4 and Blend) and the total
throughput is the sum over all inlet resources, not a per-resource equality.
Without this dispatch the default `NetworkNode` implementation would generate one constraint
per input resource (`flow_in[p] == cap_use`), incorrectly forcing all resource flows equal.
"""
function EMB.constraints_flow_in(
    m,
    n::DiscretizedPoolingNode,
    𝒯::TimeStructure,
    modeltype::EMB.EnergyModel,
)
    𝒫ⁱⁿ = EMB.inputs(n)
    @constraint(m, [t ∈ 𝒯],
        sum(m[:flow_in][n, t, p] for p ∈ 𝒫ⁱⁿ) == m[:cap_use][n, t]
    )
end

"""
    EMB.constraints_flow_in(m, n::TransitNode, 𝒯::TimeStructure, modeltype::EMB.EnergyModel)

Same as `PoolingNode`: the sum of all input flows equals the used capacity of the node.
`TransitNode` accepts mixed resource inputs (H2, CH4, Blend) and treats their total as
the throughput, identical to `PoolingNode`.
"""
function EMB.constraints_flow_in(
    m,
    n::TransitNode,
    𝒯::TimeStructure,
    modeltype::EMB.EnergyModel,
)
    𝒫ⁱⁿ = EMB.inputs(n)
    @constraint(m, [t ∈ 𝒯],
        sum(m[:flow_in][n, t, p] for p ∈ 𝒫ⁱⁿ) == m[:cap_use][n, t]
    )
end

"""
    EMB.constraints_flow_in(m, n::BlendingNode, 𝒯::TimeStructure, modeltype::EMB.EnergyModel)

Same as `PoolingNode` and `TransitNode`: the sum of all input flows equals the used capacity.
`BlendingNode` accepts mixed resource inputs (H2, CH4, Blend) in variable proportions.
"""
function EMB.constraints_flow_in(
    m,
    n::BlendingNode,
    𝒯::TimeStructure,
    modeltype::EMB.EnergyModel,
)
    𝒫ⁱⁿ = EMB.inputs(n)
    @constraint(m, [t ∈ 𝒯],
        sum(m[:flow_in][n, t, p] for p ∈ 𝒫ⁱⁿ) == m[:cap_use][n, t]
    )
end

function EMB.constraints_flow_in(m, n::Compressor, 𝒯::TimeStructure, modeltype::EnergyModel)
    # Declaration of the required subsets
    𝒫ⁱⁿ = EMB.inputs(n)
    P = setdiff(𝒫ⁱⁿ, EMB.outputs(n)) # Energy resource

    # Constraint for the individual input stream connections
    @constraint(m, [t ∈ 𝒯, p ∈ setdiff(𝒫ⁱⁿ, P)],
        m[:flow_in][n, t, p] == m[:cap_use][n, t] * EMB.inputs(n, p)
    )
end

"""
    EMB.constraints_flow_in(m, n::DeblendNode, 𝒯::TimeStructure, modeltype::EMB.EnergyModel)

Volumetric mass balance for `DeblendNode`: all incoming blend equals the outgoing blend
plus the H₂ extracted from the blend. Extraction > delivery when psa_efficiency < 1:

    flow_in[Blend, t] == flow_out[Blend, t] + Σ_{p ∈ extracted} flow_out[p, t] / η

where η = `psa_efficiency(n)`. The PSA consumes (1−η)/η × flow_out[H₂] internally.
"""
function EMB.constraints_flow_in(
    m,
    n::DeblendNode,
    𝒯::TimeStructure,
    modeltype::EMB.EnergyModel,
)
    blend_res = first(p for p ∈ EMB.inputs(n) if p isa ResourcePooling)
    extracted = [p for p ∈ subresources(blend_res) if p ∈ EMB.outputs(n)]
    η = psa_efficiency(n)
    @constraint(m, [t ∈ 𝒯],
        m[:flow_in][n, t, blend_res] ==
        m[:flow_out][n, t, blend_res] +
        sum(m[:flow_out][n, t, p] for p ∈ extracted) / η
    )
end

"""
    EMB.constraints_flow_out(m, n::DeblendNode, 𝒯::TimeStructure, modeltype::EMB.EnergyModel)

Set `cap_use` equal to the total H₂ *extracted* from the blend (i.e. delivered ÷ η).
This links the investable capacity (`cap_inst`) to the PSA extraction rate via the
standard EMB constraint `cap_use ≤ cap_inst`.

    cap_use[n, t] == Σ_{p ∈ extracted} flow_out[p, t] / η

where η = `psa_efficiency(n)`. The PSA is sized by its extraction throughput, not by the
net delivery, so capacity accounts for the internally consumed fraction.

The outgoing blend flow is NOT constrained here — it is determined by the volumetric
mass balance in `constraints_flow_in`.
"""
function EMB.constraints_flow_out(
    m,
    n::DeblendNode,
    𝒯::TimeStructure,
    modeltype::EMB.EnergyModel,
)
    blend_res = first(p for p ∈ EMB.inputs(n) if p isa ResourcePooling)
    extracted = [p for p ∈ subresources(blend_res) if p ∈ EMB.outputs(n)]
    η = psa_efficiency(n)
    @constraint(m, [t ∈ 𝒯],
        m[:cap_use][n, t] == sum(m[:flow_out][n, t, p] for p ∈ extracted) / η
    )
end

"""
    EMB.constraints_flow_in(m, n::UnitConversion, 𝒯::TimeStructure, modeltype::EMB.EnergyModel)

Remove the flow_in constraints for UnitConversion nodes. These nodes do not use :cap_use, instead flows
are calculated based on their data extension in EMB.constraints_ext_data.
"""
function EMB.constraints_flow_in(
    m,
    n::UnitConversion,
    𝒯::TimeStructure,
    modeltype::EnergyModel,
) end
"""
    EMB.constraints_flow_out(m, n::UnitConversion, 𝒯::TimeStructure, modeltype::EMB.EnergyModel)

Remove the flow_out constraints for UnitConversion nodes. These nodes do not use :cap_use, instead flows
are calculated based on their data extension in EMB.constraints_ext_data.
"""
function EMB.constraints_flow_out(
    m,
    n::UnitConversion,
    𝒯::TimeStructure,
    modeltype::EnergyModel,
) end
