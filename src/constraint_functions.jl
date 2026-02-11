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

function EMB.constraints_flow_in(m, n::Compressor, 𝒯::TimeStructure, modeltype::EnergyModel)
    # Declaration of the required subsets
    𝒫ⁱⁿ = EMB.inputs(n)
    P = setdiff(𝒫ⁱⁿ, EMB.outputs(n)) # Energy resource

    # Constraint for the individual input stream connections
    @constraint(m, [t ∈ 𝒯, p ∈ setdiff(𝒫ⁱⁿ, P)],
        m[:flow_in][n, t, p] == m[:cap_use][n, t] * EMB.inputs(n, p)
    )
end